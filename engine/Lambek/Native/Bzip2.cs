// Reading bzip2 files (Tatoeba, the dumps of Wikimedia), which .NET does not read: the format of Julian Seward,
// decoded step by step as its specification says (Huffman codes, move-to-front, Burrows-Wheeler, runs). Every block is
// checked against its CRC; a file that does not check is refused.
using System;
using System.Collections.Generic;
using System.IO;

public class LambekBzip2Reader : Stream
{
    readonly Stream input;
    long bits;
    int bitCount;
    byte[] block = new byte[0];
    int blockAt;
    int blockLength;
    bool finished;

    public LambekBzip2Reader(Stream source)
    {
        input = source;
        StartStream();
    }

    // The next bit of the input, the first bit of each byte first
    int Bit()
    {
        if (bitCount == 0)
        {
            int next = input.ReadByte();
            if (next < 0) throw new InvalidDataException("bzip2: the file ends inside a block.");
            bits = next;
            bitCount = 8;
        }
        bitCount--;
        return (int) ((bits >> bitCount) & 1);
    }

    int Bits(int count)
    {
        int value = 0;
        for (int i = 0; i < count; i++) value = (value << 1) | Bit();
        return value;
    }

    bool StartStream()
    {
        int b = input.ReadByte();
        if (b < 0) return false;
        int z = input.ReadByte(), h = input.ReadByte(), level = input.ReadByte();
        if (b != 'B' || z != 'Z' || h != 'h' || level < '1' || level > '9') throw new InvalidDataException("bzip2: not a bzip2 stream.");
        bitCount = 0;
        return true;
    }

    // Decodes the next block into "block"; false at the end of the file
    bool NextBlock()
    {
        while (true)
        {
            long magic = ((long) Bits(24) << 24) | (long) Bits(24);
            if (magic == 0x177245385090L)
            {
                Bits(32);
                // A file may hold several streams one after the other (the multistream dumps): go on with the next
                bitCount = 0;
                if (!StartStream()) return false;
                continue;
            }
            if (magic != 0x314159265359L) throw new InvalidDataException("bzip2: a block does not start as it should.");
            break;
        }
        uint crc = (uint) Bits(32);
        if (Bit() != 0) throw new InvalidDataException("bzip2: randomised blocks are not read.");
        int origin = Bits(24);

        // The bytes used in the block
        int used = Bits(16);
        List<byte> symbols = new List<byte>();
        for (int i = 0; i < 16; i++)
        {
            if ((used & (0x8000 >> i)) == 0) continue;
            int sixteen = Bits(16);
            for (int j = 0; j < 16; j++) if ((sixteen & (0x8000 >> j)) != 0) symbols.Add((byte) (i * 16 + j));
        }
        int alphabet = symbols.Count + 2;

        // The Huffman tables and which one each group of 50 symbols uses
        int groups = Bits(3);
        int selectorCount = Bits(15);
        if (groups < 2 || groups > 6 || selectorCount == 0) throw new InvalidDataException("bzip2: bad tables.");
        byte[] order = new byte[groups];
        for (int i = 0; i < groups; i++) order[i] = (byte) i;
        byte[] selectors = new byte[selectorCount];
        for (int i = 0; i < selectorCount; i++)
        {
            int j = 0;
            while (Bit() == 1) { j++; if (j >= groups) throw new InvalidDataException("bzip2: bad selector."); }
            byte chosen = order[j];
            for (int k = j; k > 0; k--) order[k] = order[k - 1];
            order[0] = chosen;
            selectors[i] = chosen;
        }
        int[][] limits = new int[groups][];
        int[][] bases = new int[groups][];
        int[][] perms = new int[groups][];
        int[] minimum = new int[groups];
        for (int t = 0; t < groups; t++)
        {
            int[] lengths = new int[alphabet];
            int length = Bits(5);
            for (int i = 0; i < alphabet; i++)
            {
                while (true)
                {
                    if (length < 1 || length > 20) throw new InvalidDataException("bzip2: bad code length.");
                    if (Bit() == 0) break;
                    length += Bit() == 0 ? 1 : -1;
                }
                lengths[i] = length;
            }
            // Canonical codes, by length then by symbol
            int min = 32, max = 0;
            foreach (int l in lengths) { if (l < min) min = l; if (l > max) max = l; }
            minimum[t] = min;
            List<int> perm = new List<int>();
            for (int l = min; l <= max; l++) for (int s = 0; s < alphabet; s++) if (lengths[s] == l) perm.Add(s);
            perms[t] = perm.ToArray();
            int[] limit = new int[22];
            int[] baseValue = new int[22];
            int code = 0, index = 0;
            for (int l = min; l <= max; l++)
            {
                int count = 0;
                for (int s = 0; s < alphabet; s++) if (lengths[s] == l) count++;
                baseValue[l] = index - code;
                code += count;
                index += count;
                limit[l] = code - 1;
                code <<= 1;
            }
            for (int l = max + 1; l < 22; l++) limit[l] = int.MaxValue;
            limits[t] = limit;
            bases[t] = baseValue;
        }

        // The symbols: runs of zeros (RUNA, RUNB), move-to-front positions, end of block
        byte[] front = symbols.ToArray();
        int[] counts = new int[256];
        List<byte> bwt = new List<byte>(1 << 16);
        int run = 0, runWeight = 1;
        int group = -1, left = 0;
        int end = alphabet - 1;
        while (true)
        {
            if (left == 0)
            {
                group++;
                if (group >= selectorCount) throw new InvalidDataException("bzip2: too few selectors.");
                left = 50;
            }
            left--;
            int table = selectors[group];
            int lengthNow = minimum[table];
            int value = Bits(lengthNow);
            while (value > limits[table][lengthNow])
            {
                lengthNow++;
                if (lengthNow > 20) throw new InvalidDataException("bzip2: bad code.");
                value = (value << 1) | Bit();
            }
            int symbol = perms[table][value + bases[table][lengthNow]];
            if (symbol == 0 || symbol == 1)
            {
                run += symbol == 0 ? runWeight : 2 * runWeight;
                runWeight <<= 1;
                continue;
            }
            if (run > 0)
            {
                byte b = front[0];
                counts[b] += run;
                for (int i = 0; i < run; i++) bwt.Add(b);
                run = 0;
                runWeight = 1;
            }
            if (symbol == end) break;
            int position = symbol - 1;
            byte moved = front[position];
            Array.Copy(front, 0, front, 1, position);
            front[0] = moved;
            counts[moved]++;
            bwt.Add(moved);
        }

        // Burrows-Wheeler undone
        int n = bwt.Count;
        if (origin >= n && n > 0) throw new InvalidDataException("bzip2: bad origin.");
        int[] starts = new int[256];
        for (int i = 0, sum = 0; i < 256; i++) { starts[i] = sum; sum += counts[i]; }
        int[] next = new int[n];
        for (int i = 0; i < n; i++) next[starts[bwt[i]]++] = i;
        byte[] plain = new byte[n];
        int at = n > 0 ? next[origin] : 0;
        for (int i = 0; i < n; i++)
        {
            plain[i] = bwt[at];
            at = next[at];
        }

        // Runs of four bytes followed by a count
        List<byte> output = new List<byte>(n + n / 4);
        int same = 0;
        int previous = -1;
        for (int i = 0; i < n; i++)
        {
            byte b = plain[i];
            if (same == 4)
            {
                for (int k = 0; k < b; k++) output.Add((byte) previous);
                same = 0;
                previous = -1;
                continue;
            }
            output.Add(b);
            if (b == previous) same++; else { same = 1; previous = b; }
        }
        block = output.ToArray();
        if (Crc(block) != crc) throw new InvalidDataException("bzip2: a block does not match its CRC.");
        blockAt = 0;
        blockLength = block.Length;
        return true;
    }

    static uint[] crcTable;
    static uint Crc(byte[] data)
    {
        if (crcTable == null)
        {
            uint[] table = new uint[256];
            for (uint i = 0; i < 256; i++)
            {
                uint c = i << 24;
                for (int k = 0; k < 8; k++) c = (c & 0x80000000) != 0 ? (c << 1) ^ 0x04C11DB7 : c << 1;
                table[i] = c;
            }
            crcTable = table;
        }
        uint crc = 0xFFFFFFFF;
        foreach (byte b in data) crc = (crc << 8) ^ crcTable[(crc >> 24) ^ b];
        return ~crc;
    }

    public override int Read(byte[] buffer, int offset, int count)
    {
        int written = 0;
        while (written < count)
        {
            if (blockAt >= blockLength)
            {
                if (finished || !NextBlock()) { finished = true; break; }
                continue;
            }
            int take = Math.Min(count - written, blockLength - blockAt);
            Array.Copy(block, blockAt, buffer, offset + written, take);
            blockAt += take;
            written += take;
        }
        return written;
    }

    public override bool CanRead { get { return true; } }
    public override bool CanSeek { get { return false; } }
    public override bool CanWrite { get { return false; } }
    public override long Length { get { throw new NotSupportedException(); } }
    public override long Position { get { throw new NotSupportedException(); } set { throw new NotSupportedException(); } }
    public override void Flush() { }
    public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
    public override void SetLength(long value) { throw new NotSupportedException(); }
    public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
    protected override void Dispose(bool disposing) { if (disposing) input.Dispose(); base.Dispose(disposing); }
}
