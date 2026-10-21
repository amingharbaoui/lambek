// How a language sounds: a Kneser-Ney model of the shapes of its sentences, learned from free corpora (Common Voice,
// Europarl). It never chooses what Lambek says, only how: the words of the meaning are fixed, so every word that is not
// one of the frequent small words of the language (articles, pronouns, "donc", "car", "est"...) is read as its kind
// (a name, a noun, an adjective, a verb, a number). "Socrate est un homme, donc il est mortel" is learned and scored as
// "<Name> est un <n> , donc il est <a>": what is judged is the way the sentence is built, never the facts in it.
// Interpolated Kneser-Ney (Chen and Goodman): the highest order on counts, the lower ones on the number of different
// words seen before (continuation counts), one discount per order. Saved small: n-grams sorted, keys as deltas,
// log probabilities on 16 bits.
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

public sealed class LambekFluency
{
    public string Language = "";
    public int Order = 3;
    // The symbols: the kept words, then the kinds, the punctuation, the start and the end of a sentence
    public string[] Symbols = new string[0];
    Dictionary<string, int> ids = new Dictionary<string, int>(StringComparer.Ordinal);
    // Per order k (index k - 1): p*(w | h) for the n-grams kept, gamma(h) for the contexts (the weight left to the lower order)
    Dictionary<ulong, float>[] probability = new Dictionary<ulong, float>[0];
    Dictionary<ulong, float>[] backoff = new Dictionary<ulong, float>[0];
    Dictionary<string, string> kinds = new Dictionary<string, string>(StringComparer.Ordinal);
    public long Tokens;
    public int Sentences;

    const int Bits = 16;
    const string Start = "<s>";
    const string End = "</s>";
    static readonly string[] Kinds = { "<Name>", "<Num>", "<Unk>", "<n>", "<a>", "<v>", "<r>", "<an>", "<nv>", "<av>", "<anv>", "<nr>", "<ar>", "<anr>", "<vr>", "<nvr>", "<avr>", "<anvr>" };

    // Words, elided words with their apostrophe ("l'", "c'"), and each mark on its own
    static readonly Regex TokenPattern = new Regex(@"\d+(?:[.,]\d+)*|\p{L}+(?:['\u2019](?=\p{L}|\s|$))?|[^\s\p{L}\d]", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public static string[] Tokenize(string text)
    {
        List<string> tokens = new List<string>();
        foreach (Match m in TokenPattern.Matches(text ?? ""))
        {
            string t = m.Value.Replace('\u2019', '\'');
            if (t == "\u00ab" || t == "\u00bb" || t == "\"" || t == "\u201c" || t == "\u201d") t = "\"";
            if (t == "\u2014" || t == "\u2013") t = "-";
            tokens.Add(t);
        }
        return tokens.ToArray();
    }

    // The symbol a word is learned and scored as
    public string Symbol(string token, bool first, ILambekWords dictionary)
    {
        if (token.Length == 0) return "<Unk>";
        if (char.IsDigit(token[0])) return "<Num>";
        if (!char.IsLetter(token[0])) return token;
        string lower = token.ToLowerInvariant();
        bool capital = char.IsUpper(token[0]);
        // A capital inside a sentence is a name; at its start, a name only when it is no word of the language
        if (capital && !first) return "<Name>";
        if (ids.ContainsKey(lower) && Array.IndexOf(Kinds, lower) < 0) return lower;
        string kind = KindOf(lower, dictionary);
        if (capital && kind == "<Unk>") return "<Name>";
        return kind;
    }

    string KindOf(string lower, ILambekWords dictionary)
    {
        string found;
        if (kinds.TryGetValue(lower, out found)) return found;
        string kind = "<Unk>";
        if (dictionary != null && Regex.IsMatch(lower, @"^\p{L}+(?:-\p{L}+)*'?$"))
        {
            string bare = lower.TrimEnd('\'');
            HashSet<char> pos = new HashSet<char>();
            foreach (LambekLemma lemma in dictionary.Lemmas(bare, Language))
            {
                if (lemma.Pos == "n" || lemma.Pos == "a" || lemma.Pos == "v" || lemma.Pos == "r") pos.Add(lemma.Pos[0]);
            }
            if (pos.Count > 0)
            {
                StringBuilder b = new StringBuilder("<");
                foreach (char c in "anvr") if (pos.Contains(c)) b.Append(c);
                b.Append('>');
                kind = b.ToString();
                if (Array.IndexOf(Kinds, kind) < 0) kind = "<Unk>";
            }
        }
        kinds[lower] = kind;
        return kind;
    }

    int Id(string symbol)
    {
        int id;
        if (ids.TryGetValue(symbol, out id)) return id;
        return ids["<Unk>"];
    }

    static ulong Key(int[] s, int from, int count)
    {
        ulong key = 0;
        for (int i = 0; i < count; i++) key = (key << Bits) | (uint)s[from + i];
        return key;
    }

    int[] Encode(string[] tokens, ILambekWords dictionary)
    {
        int[] s = new int[tokens.Length + Order];
        for (int i = 0; i < Order - 1; i++) s[i] = ids[Start];
        for (int i = 0; i < tokens.Length; i++) s[Order - 1 + i] = Id(Symbol(tokens[i], i == 0, dictionary));
        s[s.Length - 1] = ids[End];
        return s;
    }

    // Learned from sentences, one per line; the same line twice counts once. Keep: how many frequent words are kept as
    // themselves. Least: the fewest times an n-gram of each order (2 and up) must be seen to be kept
    public static LambekFluency Train(IEnumerable<string> lines, string language, ILambekWords dictionary, int order, int keep, int[] least)
    {
        LambekFluency model = new LambekFluency { Language = language, Order = order };
        List<string[]> sentences = new List<string[]>();
        HashSet<ulong> seen = new HashSet<ulong>();
        Dictionary<string, long> frequency = new Dictionary<string, long>(StringComparer.Ordinal);
        foreach (string line in lines)
        {
            string text = (line ?? "").Trim();
            if (text.Length < 2) continue;
            if (!seen.Add(LambekSpeech.Hash(LambekDictionary.Normalize(Regex.Replace(text, @"\s+", " "))))) continue;
            string[] tokens = Tokenize(text);
            if (tokens.Length < 2 || tokens.Length > 60) continue;
            sentences.Add(tokens);
            for (int i = 0; i < tokens.Length; i++)
            {
                if (!char.IsLetter(tokens[i][0])) continue;
                // (a capital inside a sentence is a name, never one of the words kept)
                if (i > 0 && char.IsUpper(tokens[i][0])) continue;
                string lower = tokens[i].ToLowerInvariant();
                long n;
                frequency.TryGetValue(lower, out n);
                frequency[lower] = n + 1;
            }
        }
        List<string> symbols = new List<string> { Start, End };
        symbols.AddRange(Kinds);
        foreach (string word in frequency.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal).Take(keep).Select(p => p.Key)) symbols.Add(word);
        // The marks, as they come
        HashSet<string> marks = new HashSet<string>(StringComparer.Ordinal);
        foreach (string[] tokens in sentences) foreach (string t in tokens) if (!char.IsLetterOrDigit(t[0])) marks.Add(t);
        foreach (string mark in marks.OrderBy(m => m, StringComparer.Ordinal)) symbols.Add(mark);
        model.Symbols = symbols.Distinct(StringComparer.Ordinal).ToArray();
        if (model.Symbols.Length >= (1 << Bits)) throw new InvalidOperationException("Too many symbols.");
        for (int i = 0; i < model.Symbols.Length; i++) model.ids[model.Symbols[i]] = i;

        // Counts of the highest order; the lower orders count how many different symbols came before (continuation)
        Dictionary<ulong, int>[] counts = new Dictionary<ulong, int>[order];
        for (int k = 0; k < order; k++) counts[k] = new Dictionary<ulong, int>();
        HashSet<ulong>[] continued = new HashSet<ulong>[order];
        for (int k = 0; k < order; k++) continued[k] = new HashSet<ulong>();
        foreach (string[] tokens in sentences)
        {
            int[] s = model.Encode(tokens, dictionary);
            model.Tokens += tokens.Length + 1;
            for (int end = order - 1; end < s.Length; end++)
            {
                // The highest order: counted
                ulong top = Key(s, end - order + 1, order);
                int c;
                counts[order - 1].TryGetValue(top, out c);
                counts[order - 1][top] = c + 1;
                // Lower order k (k + 1 symbols): one more when this (k + 2)-gram is new, so N1+(. w)
                for (int k = order - 2; k >= 0; k--)
                {
                    ulong longer = Key(s, end - k - 1, k + 2);
                    if (!continued[k + 1].Add(longer)) break;
                    ulong key = Key(s, end - k, k + 1);
                    counts[k].TryGetValue(key, out c);
                    counts[k][key] = c + 1;
                }
            }
        }
        model.Sentences = sentences.Count;
        continued = null;

        // Discounts: D = n1 / (n1 + 2 n2), for each order
        model.probability = new Dictionary<ulong, float>[order];
        model.backoff = new Dictionary<ulong, float>[order];
        for (int k = 0; k < order; k++)
        {
            long n1 = counts[k].Values.LongCount(v => v == 1), n2 = counts[k].Values.LongCount(v => v == 2);
            double d = n1 + 2 * n2 > 0 ? (double)n1 / (n1 + 2 * n2) : 0.5;
            d = Math.Min(Math.Max(d, 0.1), 0.95);
            // Totals and the number of different words after each context
            Dictionary<ulong, long> total = new Dictionary<ulong, long>();
            Dictionary<ulong, int> types = new Dictionary<ulong, int>();
            foreach (KeyValuePair<ulong, int> p in counts[k])
            {
                ulong context = k == 0 ? 0 : p.Key >> Bits;
                long t; total.TryGetValue(context, out t); total[context] = t + p.Value;
                int u; types.TryGetValue(context, out u); types[context] = u + 1;
            }
            int floor = k == 0 ? 1 : (least != null && least.Length > k - 1 ? least[k - 1] : 1);
            Dictionary<ulong, float> p1 = new Dictionary<ulong, float>();
            foreach (KeyValuePair<ulong, int> p in counts[k])
            {
                if (p.Value < floor) continue;
                ulong context = k == 0 ? 0 : p.Key >> Bits;
                double value = Math.Max(p.Value - d, 0) / total[context];
                if (k == 0) value = (p.Value - d) / total[0] + d * types[0] / (double)total[0] / model.Symbols.Length;
                p1[p.Key] = (float)Math.Log10(Math.Max(value, 1e-12));
            }
            Dictionary<ulong, float> g = new Dictionary<ulong, float>();
            foreach (KeyValuePair<ulong, long> t in total) g[t.Key] = (float)Math.Log10(Math.Max(d * types[t.Key] / (double)t.Value, 1e-12));
            model.probability[k] = p1;
            model.backoff[k] = g;
        }
        return model;
    }

    // log10 P(w | the order - 1 symbols before it), interpolated down to the uniform
    double Conditional(int[] s, int at)
    {
        double p = 1.0 / Symbols.Length;
        // From the lowest order up: P_k = p*_k + gamma_k(h) P_(k-1)
        for (int k = 0; k < Order; k++)
        {
            if (at - k < 0) break;
            ulong key = Key(s, at - k, k + 1);
            ulong context = k == 0 ? 0 : key >> Bits;
            float g;
            float star;
            bool has = probability[k].TryGetValue(key, out star);
            if (k == 0)
            {
                p = has ? Math.Pow(10, star) : p * 0.5;
                continue;
            }
            if (!backoff[k].TryGetValue(context, out g)) continue;
            p = (has ? Math.Pow(10, star) : 0) + Math.Pow(10, g) * p;
        }
        return Math.Log10(Math.Max(p, 1e-12));
    }

    // The log10 probability of a sentence, with its end, and how many symbols it has
    public double[] Score(string text, ILambekWords dictionary)
    {
        string[] tokens = Tokenize(text);
        int[] s = Encode(tokens, dictionary);
        double sum = 0;
        for (int at = Order - 1; at < s.Length; at++) sum += Conditional(s, at);
        return new double[] { sum, tokens.Length + 1 };
    }

    // The symbols a sentence is read as (to see what the model sees)
    public string[] Shape(string text, ILambekWords dictionary)
    {
        string[] tokens = Tokenize(text);
        string[] shape = new string[tokens.Length];
        for (int i = 0; i < tokens.Length; i++) shape[i] = Symbols[Id(Symbol(tokens[i], i == 0, dictionary))];
        return shape;
    }

    // Saved: symbols, then per order the n-grams (sorted keys as deltas) with their log probabilities on 16 bits
    public void Save(string path)
    {
        using (FileStream file = File.Create(path))
        using (GZipStream zip = new GZipStream(file, CompressionLevel.Optimal))
        using (BinaryWriter w = new BinaryWriter(zip, Encoding.UTF8))
        {
            w.Write("LambekFluency1");
            w.Write(Language);
            w.Write(Order);
            w.Write(Tokens);
            w.Write(Sentences);
            w.Write(Symbols.Length);
            foreach (string symbol in Symbols) w.Write(symbol);
            for (int k = 0; k < Order; k++)
            {
                Table(w, probability[k]);
                Table(w, backoff[k]);
            }
        }
    }

    static void Table(BinaryWriter w, Dictionary<ulong, float> table)
    {
        ulong[] keys = table.Keys.ToArray();
        Array.Sort(keys);
        w.Write(keys.Length);
        ulong last = 0;
        foreach (ulong key in keys)
        {
            ulong delta = key - last;
            last = key;
            while (delta >= 0x80) { w.Write((byte)(delta | 0x80)); delta >>= 7; }
            w.Write((byte)delta);
        }
        foreach (ulong key in keys) w.Write((short)Math.Max(short.MinValue, Math.Round(table[key] * 3000)));
    }

    static Dictionary<ulong, float> Table(BinaryReader r)
    {
        int n = r.ReadInt32();
        ulong[] keys = new ulong[n];
        ulong last = 0;
        for (int i = 0; i < n; i++)
        {
            ulong delta = 0;
            int shift = 0;
            byte b;
            do { b = r.ReadByte(); delta |= (ulong)(b & 0x7F) << shift; shift += 7; } while ((b & 0x80) != 0);
            last += delta;
            keys[i] = last;
        }
        Dictionary<ulong, float> table = new Dictionary<ulong, float>(n);
        for (int i = 0; i < n; i++) table[keys[i]] = r.ReadInt16() / 3000f;
        return table;
    }

    public static LambekFluency Load(string path)
    {
        using (FileStream file = File.OpenRead(path))
        using (GZipStream zip = new GZipStream(file, CompressionMode.Decompress))
        using (BufferedStream buffered = new BufferedStream(zip, 1 << 16))
        using (BinaryReader r = new BinaryReader(buffered, Encoding.UTF8))
        {
            if (r.ReadString() != "LambekFluency1") throw new InvalidDataException("Not a fluency model.");
            LambekFluency model = new LambekFluency { Language = r.ReadString(), Order = r.ReadInt32(), Tokens = r.ReadInt64(), Sentences = r.ReadInt32() };
            int n = r.ReadInt32();
            model.Symbols = new string[n];
            for (int i = 0; i < n; i++) { model.Symbols[i] = r.ReadString(); model.ids[model.Symbols[i]] = i; }
            model.probability = new Dictionary<ulong, float>[model.Order];
            model.backoff = new Dictionary<ulong, float>[model.Order];
            for (int k = 0; k < model.Order; k++)
            {
                model.probability[k] = Table(r);
                model.backoff[k] = Table(r);
            }
            return model;
        }
    }

    public int Size()
    {
        int n = 0;
        for (int k = 0; k < Order; k++) n += probability[k].Count + backoff[k].Count;
        return n;
    }
}
