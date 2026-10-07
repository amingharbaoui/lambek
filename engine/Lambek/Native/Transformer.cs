// An optional proposer: a very small transformer that reads a request and gives the probability of each action.
// It never decides: it only proposes "did you mean ...?" when Lambek did not understand.
// Words and their character trigrams are hashed (FNV-1a) into one table of vectors, so there is no vocabulary file.
// Pre-norm transformer blocks (Vaswani et al. 2017), mean pooling, a linear head, softmax, cross-entropy, Adam.
// The backward pass is written by hand and checked by finite differences in the tests.
// LoRA adapters (Hu et al. 2021): W' = W + (alpha / r) * B * A on the query and value matrices and on the head.
// Everything is in double precision, on one thread, from a seeded xorshift generator: same data, same file.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

// The seeded generator of every random number of the proposer (xorshift64, Marsaglia 2003)
public class LambekXorShift
{
    private ulong state;

    public LambekXorShift(ulong seed)
    {
        // Zero is the one state xorshift never leaves
        state = seed == 0 ? 0x9E3779B97F4A7C15UL : seed;
    }

    public ulong Next()
    {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        return state;
    }

    // A number in [0, 1) from the 53 high bits
    public double NextDouble()
    {
        return (Next() >> 11) * (1.0 / 9007199254740992.0);
    }

    // A whole number in [0, count)
    public int NextInt(int count)
    {
        return (int)(Next() % (ulong)count);
    }

    // A normal number (Box-Muller): sqrt(-2 ln u) cos(2 pi v)
    public double NextGaussian()
    {
        double u = 1.0 - NextDouble();
        double v = NextDouble();
        return Math.Sqrt(-2.0 * Math.Log(u)) * Math.Cos(2.0 * Math.PI * v);
    }
}

// From a request to its words, and from a word to the rows of the table
public static class LambekTransformerText
{
    public const string PathToken = "<path>";
    public const string QuotedToken = "<quoted>";
    public const string FileToken = "<file>";
    public const string ExtensionToken = "<ext>";
    public const string NumberToken = "<num>";
    public const string LinkToken = "<link>";
    public const string EmptyToken = "<empty>";

    // What is the same in every language: quoted names, addresses, paths, file names, extensions, numbers
    private static readonly Regex Special = new Regex(
        "(?<quoted>\"[^\"]*\"|\u00AB[^\u00BB]*\u00BB|\u201C[^\u201D]*\u201D)" +
        "|(?<link>https?://\\S+)" +
        "|(?<path>(?<![\\p{L}\\p{N}])[a-z]:[\\\\/]\\S*|\\\\\\\\\\S+|(?<!\\w)~?/\\S+|(?<!\\w)~\\\\\\S*)" +
        "|(?<file>(?<![\\w.])[\\w-]+\\.[a-z][a-z0-9]{0,9}(?!\\w))" +
        "|(?<ext>(?<![\\w.])\\*?\\.[a-z0-9]{1,10}\\b)" +
        "|(?<num>(?<![\\p{L}\\p{N}])\\d+(?:[.,]\\d+)*)",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    private static readonly Regex JoinedPronoun = new Regex(
        "(?<=\\p{L})-(?=(?:les|le|la|lui|leur|moi|toi|nous|vous|en|y|them|it|os|as|o|a|lhes?|los|las|lo)\\b)",
        RegexOptions.CultureInvariant);

    private static readonly Regex Apostrophe = new Regex("['\u2019\u2018`]", RegexOptions.CultureInvariant);
    private static readonly Regex Spaces = new Regex("\\s+", RegexOptions.CultureInvariant);
    private static readonly Regex NotWord = new Regex("[^\\p{L}\\p{N}]+", RegexOptions.CultureInvariant);

    // The same text as ConvertTo-LambekNormalizedText gives: no accents, lower case, plain spaces
    public static string Normalize(string text)
    {
        if (text == null) return "";
        string decomposed = text.Normalize(NormalizationForm.FormD);
        StringBuilder builder = new StringBuilder();
        foreach (char character in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark) builder.Append(character);
        }
        string result = builder.ToString().Normalize(NormalizationForm.FormC);
        result = result.ToLowerInvariant().Replace("\u00DF", "ss");
        result = JoinedPronoun.Replace(result, " ");
        result = Apostrophe.Replace(result, " ");
        result = Spaces.Replace(result, " ");
        return result.Trim();
    }

    // The words of a request, with a placeholder for each path, quoted name, file name, extension and number
    public static string[] Words(string text)
    {
        List<string> words = new List<string>();
        if (text == null) text = "";
        int position = 0;
        foreach (Match match in Special.Matches(text))
        {
            AddPlainWords(words, text.Substring(position, match.Index - position));
            if (match.Groups["quoted"].Success) words.Add(QuotedToken);
            else if (match.Groups["link"].Success) words.Add(LinkToken);
            else if (match.Groups["path"].Success) words.Add(PathToken);
            else if (match.Groups["file"].Success) words.Add(FileToken);
            else if (match.Groups["ext"].Success) words.Add(ExtensionToken);
            else words.Add(NumberToken);
            position = match.Index + match.Length;
        }
        AddPlainWords(words, text.Substring(position));
        if (words.Count == 0) words.Add(EmptyToken);
        return words.ToArray();
    }

    private static void AddPlainWords(List<string> words, string piece)
    {
        foreach (string word in NotWord.Split(Normalize(piece)))
        {
            if (word.Length > 0) words.Add(word);
        }
    }

    // FNV-1a, 32 bits, on the UTF-8 bytes: h = (h xor byte) * 16777619, from 2166136261
    public static uint Fnv1a(string text)
    {
        uint hash = 2166136261;
        foreach (byte one in Encoding.UTF8.GetBytes(text))
        {
            hash ^= one;
            hash = unchecked(hash * 16777619);
        }
        return hash;
    }

    // The character trigrams of a word between its two ends: "^de", "del", ... , "te$"
    public static string[] Trigrams(string word)
    {
        string framed = "^" + word + "$";
        List<string> trigrams = new List<string>();
        for (int start = 0; start + 3 <= framed.Length; start++) trigrams.Add(framed.Substring(start, 3));
        return trigrams.ToArray();
    }

    // The rows of the table a word adds up: one for the word, one for each trigram (a placeholder has its own row only)
    public static int[] RowsOf(string word, int rows)
    {
        List<int> found = new List<int>();
        found.Add((int)(Fnv1a("w:" + word) % (uint)rows));
        if (!word.StartsWith("<", StringComparison.Ordinal))
        {
            foreach (string trigram in Trigrams(word)) found.Add((int)(Fnv1a("t:" + trigram) % (uint)rows));
        }
        return found.ToArray();
    }

    // One variation of a sentence for training: another form of a word, placeholders, a dropped word, a typo,
    // a word of another language, two words swapped. All drawn from the generator given, so it is the same every time
    public static string[] Vary(string[] words, LambekXorShift random, Dictionary<string, string[]> forms, string[] foreign)
    {
        List<string> result = new List<string>(words);

        // Another form of the same word ("delete" for "deleting", "borra" for "eliminar")
        if (forms != null)
        {
            for (int i = 0; i < result.Count; i++)
            {
                if (forms.ContainsKey(result[i]) && random.NextDouble() < 0.35)
                {
                    string[] choices = forms[result[i]];
                    result[i] = choices[random.NextInt(choices.Length)];
                }
            }
        }

        // What a real request holds and an example does not: a path, an extension, a number, a name
        if (random.NextDouble() < 0.6)
        {
            string[] placeholders = { PathToken, PathToken, PathToken, ExtensionToken, ExtensionToken, NumberToken, FileToken, QuotedToken };
            int count = 1 + random.NextInt(2);
            for (int k = 0; k < count; k++)
            {
                string placeholder = placeholders[random.NextInt(placeholders.Length)];
                result.Insert(1 + random.NextInt(result.Count), placeholder);
            }
        }

        // A word left out
        if (result.Count >= 3 && random.NextDouble() < 0.25) result.RemoveAt(random.NextInt(result.Count));

        // A word of another language mixed in
        if (foreign != null && foreign.Length > 0 && random.NextDouble() < 0.12)
        {
            string word = foreign[random.NextInt(foreign.Length)];
            if (random.NextDouble() < 0.5) result[random.NextInt(result.Count)] = word;
            else result.Insert(random.NextInt(result.Count + 1), word);
        }

        // Two neighbours swapped
        if (result.Count >= 3 && random.NextDouble() < 0.08)
        {
            int at = random.NextInt(result.Count - 1);
            string kept = result[at];
            result[at] = result[at + 1];
            result[at + 1] = kept;
        }

        // A typo in one word
        if (random.NextDouble() < 0.35)
        {
            int at = random.NextInt(result.Count);
            result[at] = Misspell(result[at], random);
        }
        return result.ToArray();
    }

    // One typing mistake in a word of four letters or more: two letters swapped, one lost, one doubled, one replaced
    public static string Misspell(string word, LambekXorShift random)
    {
        if (word.Length < 4 || word.StartsWith("<", StringComparison.Ordinal)) return word;
        char[] letters = word.ToCharArray();
        int at = random.NextInt(letters.Length - 1);
        int kind = random.NextInt(4);
        if (kind == 0)
        {
            char kept = letters[at];
            letters[at] = letters[at + 1];
            letters[at + 1] = kept;
            return new string(letters);
        }
        if (kind == 1) return word.Remove(at, 1);
        if (kind == 2) return word.Insert(at, word[at].ToString());
        letters[at] = (char)('a' + random.NextInt(26));
        return new string(letters);
    }

    // Plain words of a dictionary file of Lambek (lines "W<tab>word<tab>..."), evenly spread over the file.
    // They are the words of sentences that ask for no action
    public static string[] DictionaryWords(string path, int count)
    {
        List<string> all = new List<string>();
        using (FileStream file = File.OpenRead(path))
        using (GZipStream unzipped = new GZipStream(file, CompressionMode.Decompress))
        using (StreamReader reader = new StreamReader(unzipped, Encoding.UTF8))
        {
            string line;
            string previous = "";
            while ((line = reader.ReadLine()) != null)
            {
                if (!line.StartsWith("W\t", StringComparison.Ordinal)) continue;
                int end = line.IndexOf('\t', 2);
                if (end < 0) continue;
                string word = Normalize(line.Substring(2, end - 2));
                if (word.Length < 3 || word.Length > 10 || word == previous) continue;
                bool plain = true;
                foreach (char letter in word)
                {
                    if (letter < 'a' || letter > 'z') { plain = false; break; }
                }
                if (!plain) continue;
                all.Add(word);
                previous = word;
            }
        }
        if (all.Count == 0) return new string[0];
        string[] picked = new string[Math.Min(count, all.Count)];
        for (int i = 0; i < picked.Length; i++) picked[i] = all[(int)((long)i * all.Count / picked.Length)];
        return picked;
    }

    // The numbers 0..count-1 in a shuffled order (Fisher-Yates)
    public static int[] Shuffle(int count, LambekXorShift random)
    {
        int[] order = new int[count];
        for (int i = 0; i < count; i++) order[i] = i;
        for (int i = count - 1; i > 0; i--)
        {
            int j = random.NextInt(i + 1);
            int kept = order[i];
            order[i] = order[j];
            order[j] = kept;
        }
        return order;
    }
}

// Adam (Kingma and Ba 2015): m = b1 m + (1 - b1) g, v = b2 v + (1 - b2) g^2, w = w - rate * mhat / (sqrt(vhat) + eps)
public class LambekAdam
{
    public double Rate = 0.001;
    public double Beta1 = 0.9;
    public double Beta2 = 0.999;
    public double Epsilon = 1e-8;
    public int Steps;
    private Dictionary<string, double[]> first = new Dictionary<string, double[]>(StringComparer.Ordinal);
    private Dictionary<string, double[]> second = new Dictionary<string, double[]>(StringComparer.Ordinal);

    // Called once before the updates of one mini-batch
    public void Begin()
    {
        Steps++;
    }

    public void Update(string name, double[] weights, double[] gradient)
    {
        if (!first.ContainsKey(name))
        {
            first[name] = new double[weights.Length];
            second[name] = new double[weights.Length];
        }
        double[] m = first[name];
        double[] v = second[name];
        double correction1 = 1.0 - Math.Pow(Beta1, Steps);
        double correction2 = 1.0 - Math.Pow(Beta2, Steps);
        for (int i = 0; i < weights.Length; i++)
        {
            m[i] = Beta1 * m[i] + (1.0 - Beta1) * gradient[i];
            v[i] = Beta2 * v[i] + (1.0 - Beta2) * gradient[i] * gradient[i];
            weights[i] -= Rate * (m[i] / correction1) / (Math.Sqrt(v[i] / correction2) + Epsilon);
        }
    }
}

// A LoRA adapter: for each matrix it adapts, A (rank x columns, small random) and B (rows x rank, zero at start)
public class LambekAdapter
{
    public const string Format = "lambek-adapter-1";
    // How many confirmed requests an adapter keeps
    public const int MaxExamples = 200;
    public string Name = "";
    // The base the adapter was trained on: on another base it means nothing
    public string Base = "";
    public int Rank;
    public double Alpha;
    public ulong Seed;
    public List<string> Targets = new List<string>();
    public Dictionary<string, double[]> A = new Dictionary<string, double[]>(StringComparer.Ordinal);
    public Dictionary<string, double[]> B = new Dictionary<string, double[]>(StringComparer.Ordinal);
    // The confirmed requests it learned from, so they are all learned again at each new one
    public List<string> Texts = new List<string>();
    public List<string> Labels = new List<string>();

    // alpha / r: how much of B * A is added to the matrix
    public double Scale
    {
        get { return Alpha / Rank; }
    }

    public string Save()
    {
        using (MemoryStream stream = new MemoryStream())
        {
            JsonWriterOptions options = new JsonWriterOptions();
            options.Indented = true;
            using (Utf8JsonWriter writer = new Utf8JsonWriter(stream, options))
            {
                writer.WriteStartObject();
                writer.WriteString("Format", Format);
                writer.WriteString("Name", Name);
                writer.WriteString("Base", Base);
                writer.WriteNumber("Rank", Rank);
                writer.WriteNumber("Alpha", Alpha);
                writer.WriteNumber("Seed", Seed);
                writer.WriteStartObject("Targets");
                foreach (string target in Targets)
                {
                    writer.WriteStartObject(target);
                    writer.WriteString("A", LambekTransformer.Pack(A[target]));
                    writer.WriteString("B", LambekTransformer.Pack(B[target]));
                    writer.WriteEndObject();
                }
                writer.WriteEndObject();
                writer.WriteStartArray("Examples");
                for (int i = 0; i < Texts.Count; i++)
                {
                    writer.WriteStartObject();
                    writer.WriteString("Text", Texts[i]);
                    writer.WriteString("Action", Labels[i]);
                    writer.WriteEndObject();
                }
                writer.WriteEndArray();
                writer.WriteEndObject();
            }
            return Encoding.UTF8.GetString(stream.ToArray()).Replace("\r\n", "\n") + "\n";
        }
    }

    public static LambekAdapter Load(string json)
    {
        using (JsonDocument document = JsonDocument.Parse(json))
        {
            JsonElement root = document.RootElement;
            if (root.GetProperty("Format").GetString() != Format) throw new InvalidDataException("This is not a Lambek adapter file.");
            LambekAdapter adapter = new LambekAdapter();
            adapter.Name = root.GetProperty("Name").GetString();
            adapter.Base = root.GetProperty("Base").GetString();
            adapter.Rank = root.GetProperty("Rank").GetInt32();
            adapter.Alpha = root.GetProperty("Alpha").GetDouble();
            adapter.Seed = root.GetProperty("Seed").GetUInt64();
            foreach (JsonProperty target in root.GetProperty("Targets").EnumerateObject())
            {
                adapter.Targets.Add(target.Name);
                adapter.A[target.Name] = LambekTransformer.Unpack(target.Value.GetProperty("A").GetString());
                adapter.B[target.Name] = LambekTransformer.Unpack(target.Value.GetProperty("B").GetString());
            }
            foreach (JsonElement example in root.GetProperty("Examples").EnumerateArray())
            {
                adapter.Texts.Add(example.GetProperty("Text").GetString());
                adapter.Labels.Add(example.GetProperty("Action").GetString());
            }
            return adapter;
        }
    }
}

// What the forward pass of one block keeps for its backward pass
public class LambekBlockTrace
{
    public double[][] Input;
    public double[][] Norm1Hat;
    public double[] Norm1Sigma;
    public double[][] Normed1;
    public double[][] Query;
    public double[][] Key;
    public double[][] Value;
    // Attention[head][i][j]: how much word i looks at word j
    public double[][][] Attention;
    public double[][] Mixed;
    public double[][] Middle;
    public double[][] Norm2Hat;
    public double[] Norm2Sigma;
    public double[][] Normed2;
    public double[][] Before;
    public double[][] After;
}

// What the forward pass of one request keeps
public class LambekTransformerTrace
{
    public int[][] Rows;
    public LambekBlockTrace[] Blocks;
    public double[][] Last;
    public double[][] NormHat;
    public double[] NormSigma;
    public double[] Pooled;
    public double[] Probabilities;
}

public class LambekTransformer
{
    public const string Format = "lambek-proposer-1";
    public const double NormEpsilon = 1e-5;
    public int Rows;
    public int Dim;
    public int Heads;
    public int Layers;
    public int Hidden;
    public int MaxWords;
    public ulong Seed;
    // The action of each output; the last one is "none"
    public string[] Classes = new string[0];
    // Under this probability nothing is proposed (fitted on held-out requests)
    public double Threshold = 1.0;
    // How the file was made (counts and measures), for the reader
    public SortedDictionary<string, string> Notes = new SortedDictionary<string, string>(StringComparer.Ordinal);
    public List<string> Names = new List<string>();
    public Dictionary<string, double[]> Weights = new Dictionary<string, double[]>(StringComparer.Ordinal);
    public Dictionary<string, int[]> Shapes = new Dictionary<string, int[]>(StringComparer.Ordinal);
    public List<LambekAdapter> Adapters = new List<LambekAdapter>();
    // Each matrix as it is used: the base, plus the adapters attached
    private Dictionary<string, double[]> effective = new Dictionary<string, double[]>(StringComparer.Ordinal);
    private double[][] positions = new double[0][];

    // ---- Formulas, one small function each ----

    // softmax(x)_i = exp(x_i - max) / sum_j exp(x_j - max)
    public static double[] Softmax(double[] values)
    {
        double highest = values[0];
        for (int i = 1; i < values.Length; i++) highest = Math.Max(highest, values[i]);
        double[] result = new double[values.Length];
        double total = 0;
        for (int i = 0; i < values.Length; i++)
        {
            result[i] = Math.Exp(values[i] - highest);
            total += result[i];
        }
        for (int i = 0; i < values.Length; i++) result[i] /= total;
        return result;
    }

    // GELU (Hendrycks and Gimpel 2016), tanh form: 0.5 x (1 + tanh(sqrt(2 / pi) (x + 0.044715 x^3)))
    public static double Gelu(double x)
    {
        double inner = Math.Sqrt(2.0 / Math.PI) * (x + 0.044715 * x * x * x);
        return 0.5 * x * (1.0 + Math.Tanh(inner));
    }

    // Its derivative: 0.5 (1 + t) + 0.5 x (1 - t^2) sqrt(2 / pi) (1 + 3 * 0.044715 x^2), t the tanh above
    public static double GeluSlope(double x)
    {
        double scale = Math.Sqrt(2.0 / Math.PI);
        double t = Math.Tanh(scale * (x + 0.044715 * x * x * x));
        return 0.5 * (1.0 + t) + 0.5 * x * (1.0 - t * t) * scale * (1.0 + 3.0 * 0.044715 * x * x);
    }

    // Sinusoidal position: P(pos, 2i) = sin(pos / 10000^(2i / d)), P(pos, 2i + 1) = cos(the same)
    public static double[] Position(int position, int dim)
    {
        double[] result = new double[dim];
        for (int i = 0; i < dim; i++)
        {
            int pair = i / 2;
            double angle = position / Math.Pow(10000.0, 2.0 * pair / dim);
            result[i] = (i % 2 == 0) ? Math.Sin(angle) : Math.Cos(angle);
        }
        return result;
    }

    // Layer norm (Ba et al. 2016): y = gain * (x - mean) / sqrt(variance + epsilon) + bias
    public static double[] LayerNorm(double[] x, double[] gain, double[] bias)
    {
        double[] hat;
        double sigma;
        return NormForward(x, gain, bias, out hat, out sigma);
    }

    private static double[] NormForward(double[] x, double[] gain, double[] bias, out double[] hat, out double sigma)
    {
        int n = x.Length;
        double mean = 0;
        for (int i = 0; i < n; i++) mean += x[i];
        mean /= n;
        double variance = 0;
        for (int i = 0; i < n; i++) variance += (x[i] - mean) * (x[i] - mean);
        variance /= n;
        sigma = Math.Sqrt(variance + NormEpsilon);
        hat = new double[n];
        double[] y = new double[n];
        for (int i = 0; i < n; i++)
        {
            hat[i] = (x[i] - mean) / sigma;
            y[i] = gain[i] * hat[i] + bias[i];
        }
        return y;
    }

    // Backward of the layer norm: dx = (dhat - mean(dhat) - hat * mean(dhat * hat)) / sigma, with dhat = dy * gain
    private static double[] NormBackward(double[] dy, double[] hat, double sigma, double[] gain, double[] gainGradient, double[] biasGradient)
    {
        int n = dy.Length;
        double[] dhat = new double[n];
        double meanDhat = 0;
        double meanBoth = 0;
        for (int i = 0; i < n; i++)
        {
            gainGradient[i] += dy[i] * hat[i];
            biasGradient[i] += dy[i];
            dhat[i] = dy[i] * gain[i];
            meanDhat += dhat[i];
            meanBoth += dhat[i] * hat[i];
        }
        meanDhat /= n;
        meanBoth /= n;
        double[] dx = new double[n];
        for (int i = 0; i < n; i++) dx[i] = (dhat[i] - meanDhat - hat[i] * meanBoth) / sigma;
        return dx;
    }

    // y = W x, W stored row after row
    public static double[] Apply(double[] matrix, int rows, int columns, double[] x)
    {
        double[] y = new double[rows];
        for (int r = 0; r < rows; r++)
        {
            double total = 0;
            int offset = r * columns;
            for (int c = 0; c < columns; c++) total += matrix[offset + c] * x[c];
            y[r] = total;
        }
        return y;
    }

    // Backward of y = W x: dW += dy x', and dx = W' dy
    private static double[] ApplyBackward(double[] matrix, int rows, int columns, double[] x, double[] dy, double[] matrixGradient)
    {
        double[] dx = new double[columns];
        for (int r = 0; r < rows; r++)
        {
            int offset = r * columns;
            double d = dy[r];
            for (int c = 0; c < columns; c++)
            {
                matrixGradient[offset + c] += d * x[c];
                dx[c] += matrix[offset + c] * d;
            }
        }
        return dx;
    }

    // Self-attention (Vaswani et al. 2017), for each head on its own slice: softmax(Q K' / sqrt(d_k)) V
    public static double[][] Attend(double[][] query, double[][] key, double[][] value, int heads, out double[][][] attention)
    {
        int count = query.Length;
        int dim = query[0].Length;
        int slice = dim / heads;
        double[][] mixed = new double[count][];
        for (int i = 0; i < count; i++) mixed[i] = new double[dim];
        attention = new double[heads][][];
        for (int h = 0; h < heads; h++)
        {
            int from = h * slice;
            attention[h] = new double[count][];
            for (int i = 0; i < count; i++)
            {
                double[] scores = new double[count];
                for (int j = 0; j < count; j++)
                {
                    double dot = 0;
                    for (int c = 0; c < slice; c++) dot += query[i][from + c] * key[j][from + c];
                    scores[j] = dot / Math.Sqrt(slice);
                }
                double[] weights = Softmax(scores);
                attention[h][i] = weights;
                for (int j = 0; j < count; j++)
                {
                    for (int c = 0; c < slice; c++) mixed[i][from + c] += weights[j] * value[j][from + c];
                }
            }
        }
        return mixed;
    }

    // The same without the weights, for a caller that only wants the result
    public static double[][] Attend(double[][] query, double[][] key, double[][] value, int heads)
    {
        double[][][] attention;
        return Attend(query, key, value, heads, out attention);
    }

    // Backward of the attention: from the gradient of the mix to the gradients of query, key and value
    private static void AttendBackward(double[][] dMixed, LambekBlockTrace trace, int heads, double[][] dQuery, double[][] dKey, double[][] dValue)
    {
        int count = dMixed.Length;
        int dim = dMixed[0].Length;
        int slice = dim / heads;
        double root = Math.Sqrt(slice);
        for (int h = 0; h < heads; h++)
        {
            int from = h * slice;
            for (int i = 0; i < count; i++)
            {
                double[] weights = trace.Attention[h][i];
                // dP_ij = dMixed_i . V_j, and dV_j += P_ij dMixed_i
                double[] dWeights = new double[count];
                double expected = 0;
                for (int j = 0; j < count; j++)
                {
                    double dot = 0;
                    for (int c = 0; c < slice; c++)
                    {
                        dot += dMixed[i][from + c] * trace.Value[j][from + c];
                        dValue[j][from + c] += weights[j] * dMixed[i][from + c];
                    }
                    dWeights[j] = dot;
                    expected += weights[j] * dot;
                }
                // Softmax: dS_ij = P_ij (dP_ij - sum_k P_ik dP_ik); then S_ij = Q_i . K_j / sqrt(d_k)
                for (int j = 0; j < count; j++)
                {
                    double dScore = weights[j] * (dWeights[j] - expected) / root;
                    for (int c = 0; c < slice; c++)
                    {
                        dQuery[i][from + c] += dScore * trace.Key[j][from + c];
                        dKey[j][from + c] += dScore * trace.Query[i][from + c];
                    }
                }
            }
        }
    }

    // Cross-entropy of one answer: -ln p[label]
    public static double CrossEntropy(double[] probabilities, int label)
    {
        return -Math.Log(Math.Max(probabilities[label], 1e-300));
    }

    // LoRA: W' = W + (alpha / r) * B * A, with B rows x rank and A rank x columns
    public static double[] Adapt(double[] matrix, int rows, int columns, double[] a, double[] b, int rank, double alpha)
    {
        double scale = alpha / rank;
        double[] result = (double[])matrix.Clone();
        for (int r = 0; r < rows; r++)
        {
            for (int c = 0; c < columns; c++)
            {
                double total = 0;
                for (int k = 0; k < rank; k++) total += b[r * rank + k] * a[k * columns + c];
                result[r * columns + c] += scale * total;
            }
        }
        return result;
    }

    // The lowest threshold at which the proposals kept are right at least 'target' of the time (2 when there is none)
    public static double Calibrate(double[] confidence, bool[] right, double target)
    {
        int[] order = new int[confidence.Length];
        for (int i = 0; i < order.Length; i++) order[i] = i;
        Array.Sort(order, (a, b) => confidence[a] != confidence[b] ? confidence[b].CompareTo(confidence[a]) : a.CompareTo(b));
        double threshold = 2.0;
        int good = 0;
        for (int n = 0; n < order.Length; n++)
        {
            if (right[order[n]]) good++;
            // A threshold cuts between two different confidences only
            bool last = n == order.Length - 1 || confidence[order[n + 1]] != confidence[order[n]];
            if (last && good >= target * (n + 1)) threshold = confidence[order[n]];
        }
        return threshold;
    }

    // ---- The model ----

    public static LambekTransformer Create(int rows, int dim, int heads, int layers, int hidden, int maxWords, string[] classes, ulong seed, double embeddingScale)
    {
        if (dim % heads != 0) throw new ArgumentException("The dimension must be a multiple of the number of heads.");
        LambekTransformer model = new LambekTransformer();
        model.Rows = rows;
        model.Dim = dim;
        model.Heads = heads;
        model.Layers = layers;
        model.Hidden = hidden;
        model.MaxWords = maxWords;
        model.Seed = seed;
        model.Classes = (string[])classes.Clone();
        LambekXorShift random = new LambekXorShift(seed);

        // The table starts at zero when the scale is zero: a word never seen then adds nothing
        model.AddWeight("embedding", rows, dim, random, embeddingScale);
        for (int layer = 0; layer < layers; layer++)
        {
            string block = "block" + layer.ToString(CultureInfo.InvariantCulture) + ".";
            model.AddConstant(block + "norm1.gain", dim, 1.0);
            model.AddConstant(block + "norm1.bias", dim, 0.0);
            model.AddWeight(block + "query", dim, dim, random, 1.0 / Math.Sqrt(dim));
            model.AddWeight(block + "key", dim, dim, random, 1.0 / Math.Sqrt(dim));
            model.AddWeight(block + "value", dim, dim, random, 1.0 / Math.Sqrt(dim));
            model.AddWeight(block + "output", dim, dim, random, 1.0 / Math.Sqrt(dim));
            model.AddConstant(block + "norm2.gain", dim, 1.0);
            model.AddConstant(block + "norm2.bias", dim, 0.0);
            model.AddWeight(block + "up", hidden, dim, random, Math.Sqrt(2.0 / dim));
            model.AddConstant(block + "up.bias", hidden, 0.0);
            model.AddWeight(block + "down", dim, hidden, random, 1.0 / Math.Sqrt(hidden));
            model.AddConstant(block + "down.bias", dim, 0.0);
        }
        model.AddConstant("norm.gain", dim, 1.0);
        model.AddConstant("norm.bias", dim, 0.0);
        model.AddWeight("head", classes.Length, dim, random, 1.0 / Math.Sqrt(dim));
        model.AddConstant("head.bias", classes.Length, 0.0);
        model.Prepare();
        return model;
    }

    private void AddWeight(string name, int rows, int columns, LambekXorShift random, double scale)
    {
        double[] values = new double[rows * columns];
        if (scale != 0)
        {
            for (int i = 0; i < values.Length; i++) values[i] = random.NextGaussian() * scale;
        }
        Names.Add(name);
        Weights[name] = values;
        Shapes[name] = new int[] { rows, columns };
    }

    private void AddConstant(string name, int length, double value)
    {
        double[] values = new double[length];
        for (int i = 0; i < length; i++) values[i] = value;
        Names.Add(name);
        Weights[name] = values;
        Shapes[name] = new int[] { length, 1 };
    }

    // The positions, and the matrices as they are used
    private void Prepare()
    {
        positions = new double[MaxWords][];
        for (int p = 0; p < MaxWords; p++) positions[p] = Position(p, Dim);
        Refresh();
    }

    // Each matrix with the adapters attached added to it; a matrix no adapter touches is the base itself
    public void Refresh()
    {
        effective.Clear();
        foreach (string name in Names)
        {
            double[] values = Weights[name];
            foreach (LambekAdapter adapter in Adapters)
            {
                if (!adapter.A.ContainsKey(name)) continue;
                values = Adapt(values, Shapes[name][0], Shapes[name][1], adapter.A[name], adapter.B[name], adapter.Rank, adapter.Alpha);
            }
            effective[name] = values;
        }
    }

    // The matrices an adapter can adapt: query and value of each block, and the head
    public string[] AdapterTargets(bool withHead)
    {
        List<string> targets = new List<string>();
        for (int layer = 0; layer < Layers; layer++)
        {
            string block = "block" + layer.ToString(CultureInfo.InvariantCulture) + ".";
            targets.Add(block + "query");
            targets.Add(block + "value");
        }
        if (withHead) targets.Add("head");
        return targets.ToArray();
    }

    // A new adapter for this base: A small random, B zero, so it changes nothing until it is trained
    public LambekAdapter NewAdapter(string name, int rank, double alpha, ulong seed, bool withHead)
    {
        LambekAdapter adapter = new LambekAdapter();
        adapter.Name = name;
        adapter.Base = Fingerprint();
        adapter.Rank = rank;
        adapter.Alpha = alpha;
        adapter.Seed = seed;
        LambekXorShift random = new LambekXorShift(seed);
        foreach (string target in AdapterTargets(withHead))
        {
            int rows = Shapes[target][0];
            int columns = Shapes[target][1];
            double[] a = new double[rank * columns];
            for (int i = 0; i < a.Length; i++) a[i] = random.NextGaussian() / Math.Sqrt(columns);
            adapter.Targets.Add(target);
            adapter.A[target] = a;
            adapter.B[target] = new double[rows * rank];
        }
        return adapter;
    }

    public void Attach(LambekAdapter adapter)
    {
        foreach (string target in adapter.Targets)
        {
            if (!Shapes.ContainsKey(target)) throw new ArgumentException("The adapter adapts a matrix this model does not have: " + target);
            int rows = Shapes[target][0];
            int columns = Shapes[target][1];
            if (adapter.A[target].Length != adapter.Rank * columns || adapter.B[target].Length != rows * adapter.Rank)
            {
                throw new ArgumentException("The adapter does not have the shape of this model: " + target);
            }
        }
        foreach (LambekAdapter other in Adapters)
        {
            if (other.Name == adapter.Name) throw new ArgumentException("An adapter with this name is already attached: " + adapter.Name);
        }
        Adapters.Add(adapter);
        Refresh();
    }

    // Exact unlearning: without the adapter the model is the base again
    public bool Detach(string name)
    {
        for (int i = 0; i < Adapters.Count; i++)
        {
            if (Adapters[i].Name != name) continue;
            Adapters.RemoveAt(i);
            Refresh();
            return true;
        }
        return false;
    }

    // The adapter written into the base for good: W = W + (alpha / r) * B * A
    public void Merge(LambekAdapter adapter)
    {
        Detach(adapter.Name);
        foreach (string target in adapter.Targets)
        {
            Weights[target] = Adapt(Weights[target], Shapes[target][0], Shapes[target][1], adapter.A[target], adapter.B[target], adapter.Rank, adapter.Alpha);
        }
        Refresh();
    }

    // The rows of each word of a request (at most MaxWords words)
    public int[][] Encode(string text)
    {
        return EncodeWords(LambekTransformerText.Words(text));
    }

    public int[][] EncodeWords(string[] words)
    {
        int count = Math.Min(words.Length, MaxWords);
        int[][] rows = new int[count][];
        for (int i = 0; i < count; i++) rows[i] = LambekTransformerText.RowsOf(words[i], Rows);
        return rows;
    }

    // From the rows of the words to the probability of each class
    public double[] Forward(int[][] rows, LambekTransformerTrace trace)
    {
        int count = rows.Length;
        double[] table = effective["embedding"];

        // Each word: the sum of its rows, plus its position
        double[][] x = new double[count][];
        for (int t = 0; t < count; t++)
        {
            x[t] = (double[])positions[t].Clone();
            foreach (int row in rows[t])
            {
                int offset = row * Dim;
                for (int c = 0; c < Dim; c++) x[t][c] += table[offset + c];
            }
        }

        LambekBlockTrace[] blocks = new LambekBlockTrace[Layers];
        for (int layer = 0; layer < Layers; layer++)
        {
            blocks[layer] = new LambekBlockTrace();
            x = BlockForward(layer, x, blocks[layer]);
        }

        // Last norm, mean over the words, head, softmax
        double[] gain = effective["norm.gain"];
        double[] bias = effective["norm.bias"];
        double[][] hats = new double[count][];
        double[] sigmas = new double[count];
        double[] pooled = new double[Dim];
        for (int t = 0; t < count; t++)
        {
            double[] y = NormForward(x[t], gain, bias, out hats[t], out sigmas[t]);
            for (int c = 0; c < Dim; c++) pooled[c] += y[c] / count;
        }
        double[] logits = Apply(effective["head"], Classes.Length, Dim, pooled);
        double[] headBias = effective["head.bias"];
        for (int k = 0; k < logits.Length; k++) logits[k] += headBias[k];
        double[] probabilities = Softmax(logits);

        if (trace != null)
        {
            trace.Rows = rows;
            trace.Blocks = blocks;
            trace.Last = x;
            trace.NormHat = hats;
            trace.NormSigma = sigmas;
            trace.Pooled = pooled;
            trace.Probabilities = probabilities;
        }
        return probabilities;
    }

    // One pre-norm block: x + attention(norm(x)), then that + feed-forward(norm(that))
    private double[][] BlockForward(int layer, double[][] x, LambekBlockTrace trace)
    {
        string block = "block" + layer.ToString(CultureInfo.InvariantCulture) + ".";
        double[] gain1 = effective[block + "norm1.gain"];
        double[] bias1 = effective[block + "norm1.bias"];
        double[] queryMatrix = effective[block + "query"];
        double[] keyMatrix = effective[block + "key"];
        double[] valueMatrix = effective[block + "value"];
        double[] outputMatrix = effective[block + "output"];
        double[] gain2 = effective[block + "norm2.gain"];
        double[] bias2 = effective[block + "norm2.bias"];
        double[] upMatrix = effective[block + "up"];
        double[] downMatrix = effective[block + "down"];
        int count = x.Length;
        trace.Input = x;
        trace.Norm1Hat = new double[count][];
        trace.Norm1Sigma = new double[count];
        trace.Normed1 = new double[count][];
        trace.Query = new double[count][];
        trace.Key = new double[count][];
        trace.Value = new double[count][];
        for (int t = 0; t < count; t++)
        {
            trace.Normed1[t] = NormForward(x[t], gain1, bias1, out trace.Norm1Hat[t], out trace.Norm1Sigma[t]);
            trace.Query[t] = Apply(queryMatrix, Dim, Dim, trace.Normed1[t]);
            trace.Key[t] = Apply(keyMatrix, Dim, Dim, trace.Normed1[t]);
            trace.Value[t] = Apply(valueMatrix, Dim, Dim, trace.Normed1[t]);
        }
        trace.Mixed = Attend(trace.Query, trace.Key, trace.Value, Heads, out trace.Attention);

        // First residual
        trace.Middle = new double[count][];
        for (int t = 0; t < count; t++)
        {
            double[] projected = Apply(outputMatrix, Dim, Dim, trace.Mixed[t]);
            trace.Middle[t] = new double[Dim];
            for (int c = 0; c < Dim; c++) trace.Middle[t][c] = x[t][c] + projected[c];
        }

        // Feed-forward and second residual
        trace.Norm2Hat = new double[count][];
        trace.Norm2Sigma = new double[count];
        trace.Normed2 = new double[count][];
        trace.Before = new double[count][];
        trace.After = new double[count][];
        double[][] result = new double[count][];
        double[] upBias = effective[block + "up.bias"];
        double[] downBias = effective[block + "down.bias"];
        for (int t = 0; t < count; t++)
        {
            trace.Normed2[t] = NormForward(trace.Middle[t], gain2, bias2, out trace.Norm2Hat[t], out trace.Norm2Sigma[t]);
            trace.Before[t] = Apply(upMatrix, Hidden, Dim, trace.Normed2[t]);
            trace.After[t] = new double[Hidden];
            for (int k = 0; k < Hidden; k++)
            {
                trace.Before[t][k] += upBias[k];
                trace.After[t][k] = Gelu(trace.Before[t][k]);
            }
            double[] down = Apply(downMatrix, Dim, Hidden, trace.After[t]);
            result[t] = new double[Dim];
            for (int c = 0; c < Dim; c++) result[t][c] = trace.Middle[t][c] + down[c] + downBias[c];
        }
        return result;
    }

    // The gradient of weight * (-ln p[label]) for one request, added to 'gradients' (one array per matrix as it is used)
    private void Backward(LambekTransformerTrace trace, int label, double weight, Dictionary<string, double[]> gradients)
    {
        int count = trace.Rows.Length;

        // Softmax with cross-entropy: dlogits = p - onehot
        double[] dLogits = new double[Classes.Length];
        for (int k = 0; k < dLogits.Length; k++)
        {
            dLogits[k] = weight * (trace.Probabilities[k] - (k == label ? 1.0 : 0.0));
            gradients["head.bias"][k] += dLogits[k];
        }
        double[] dPooled = ApplyBackward(effective["head"], Classes.Length, Dim, trace.Pooled, dLogits, gradients["head"]);

        // Mean pooling gives each word 1 / count of it; then the last norm
        double[][] dx = new double[count][];
        double[] dy = new double[Dim];
        for (int c = 0; c < Dim; c++) dy[c] = dPooled[c] / count;
        for (int t = 0; t < count; t++)
        {
            dx[t] = NormBackward(dy, trace.NormHat[t], trace.NormSigma[t], effective["norm.gain"], gradients["norm.gain"], gradients["norm.bias"]);
        }

        for (int layer = Layers - 1; layer >= 0; layer--) dx = BlockBackward(layer, dx, trace.Blocks[layer], gradients);

        // Each row of the table a word added up gets the gradient of that word
        double[] table = gradients["embedding"];
        for (int t = 0; t < count; t++)
        {
            foreach (int row in trace.Rows[t])
            {
                int offset = row * Dim;
                for (int c = 0; c < Dim; c++) table[offset + c] += dx[t][c];
            }
        }
    }

    private double[][] BlockBackward(int layer, double[][] dOut, LambekBlockTrace trace, Dictionary<string, double[]> gradients)
    {
        string block = "block" + layer.ToString(CultureInfo.InvariantCulture) + ".";
        double[] norm1Gain = effective[block + "norm1.gain"];
        double[] norm1GainGradient = gradients[block + "norm1.gain"];
        double[] norm1BiasGradient = gradients[block + "norm1.bias"];
        double[] queryMatrix = effective[block + "query"];
        double[] queryGradient = gradients[block + "query"];
        double[] keyMatrix = effective[block + "key"];
        double[] keyGradient = gradients[block + "key"];
        double[] valueMatrix = effective[block + "value"];
        double[] valueGradient = gradients[block + "value"];
        double[] outputMatrix = effective[block + "output"];
        double[] outputGradient = gradients[block + "output"];
        double[] norm2Gain = effective[block + "norm2.gain"];
        double[] norm2GainGradient = gradients[block + "norm2.gain"];
        double[] norm2BiasGradient = gradients[block + "norm2.bias"];
        double[] upMatrix = effective[block + "up"];
        double[] upGradient = gradients[block + "up"];
        double[] upBiasGradient = gradients[block + "up.bias"];
        double[] downMatrix = effective[block + "down"];
        double[] downGradient = gradients[block + "down"];
        double[] downBiasGradient = gradients[block + "down.bias"];
        int count = dOut.Length;

        // Feed-forward: out = middle + down(gelu(up(norm2(middle))))
        double[][] dMiddle = new double[count][];
        for (int t = 0; t < count; t++)
        {
            for (int c = 0; c < Dim; c++) downBiasGradient[c] += dOut[t][c];
            double[] dAfter = ApplyBackward(downMatrix, Dim, Hidden, trace.After[t], dOut[t], downGradient);
            double[] dBefore = new double[Hidden];
            for (int k = 0; k < Hidden; k++)
            {
                dBefore[k] = dAfter[k] * GeluSlope(trace.Before[t][k]);
                upBiasGradient[k] += dBefore[k];
            }
            double[] dNormed = ApplyBackward(upMatrix, Hidden, Dim, trace.Normed2[t], dBefore, upGradient);
            double[] through = NormBackward(dNormed, trace.Norm2Hat[t], trace.Norm2Sigma[t], norm2Gain, norm2GainGradient, norm2BiasGradient);
            dMiddle[t] = new double[Dim];
            for (int c = 0; c < Dim; c++) dMiddle[t][c] = dOut[t][c] + through[c];
        }

        // Attention: middle = in + output(mix(query, key, value of norm1(in)))
        double[][] dMixed = new double[count][];
        double[][] dQuery = new double[count][];
        double[][] dKey = new double[count][];
        double[][] dValue = new double[count][];
        for (int t = 0; t < count; t++)
        {
            dMixed[t] = ApplyBackward(outputMatrix, Dim, Dim, trace.Mixed[t], dMiddle[t], outputGradient);
            dQuery[t] = new double[Dim];
            dKey[t] = new double[Dim];
            dValue[t] = new double[Dim];
        }
        AttendBackward(dMixed, trace, Heads, dQuery, dKey, dValue);

        double[][] dIn = new double[count][];
        for (int t = 0; t < count; t++)
        {
            double[] fromQuery = ApplyBackward(queryMatrix, Dim, Dim, trace.Normed1[t], dQuery[t], queryGradient);
            double[] fromKey = ApplyBackward(keyMatrix, Dim, Dim, trace.Normed1[t], dKey[t], keyGradient);
            double[] fromValue = ApplyBackward(valueMatrix, Dim, Dim, trace.Normed1[t], dValue[t], valueGradient);
            double[] dNormed = new double[Dim];
            for (int c = 0; c < Dim; c++) dNormed[c] = fromQuery[c] + fromKey[c] + fromValue[c];
            double[] through = NormBackward(dNormed, trace.Norm1Hat[t], trace.Norm1Sigma[t], norm1Gain, norm1GainGradient, norm1BiasGradient);
            dIn[t] = new double[Dim];
            for (int c = 0; c < Dim; c++) dIn[t][c] = dMiddle[t][c] + through[c];
        }
        return dIn;
    }

    // ---- Loss and gradients ----

    // The mean cross-entropy of some requests
    public double Loss(int[][][] inputs, int[] labels)
    {
        double total = 0;
        for (int i = 0; i < inputs.Length; i++) total += CrossEntropy(Forward(inputs[i], null), labels[i]);
        return total / inputs.Length;
    }

    private Dictionary<string, double[]> NewGradients()
    {
        Dictionary<string, double[]> gradients = new Dictionary<string, double[]>(StringComparer.Ordinal);
        foreach (string name in Names) gradients[name] = new double[Weights[name].Length];
        return gradients;
    }

    // The mean loss of requests from..from+count-1 and its gradient for each matrix as it is used
    private double BatchGradient(int[][][] inputs, int[] labels, int from, int count, Dictionary<string, double[]> gradients)
    {
        foreach (string name in Names) Array.Clear(gradients[name], 0, gradients[name].Length);
        double total = 0;
        for (int i = from; i < from + count; i++)
        {
            LambekTransformerTrace trace = new LambekTransformerTrace();
            double[] probabilities = Forward(inputs[i], trace);
            total += CrossEntropy(probabilities, labels[i]);
            Backward(trace, labels[i], 1.0 / count, gradients);
        }
        return total / count;
    }

    // The gradient of the mean loss for every matrix (with adapters attached: for the matrix as it is used)
    public Dictionary<string, double[]> Gradient(int[][][] inputs, int[] labels)
    {
        Dictionary<string, double[]> gradients = NewGradients();
        BatchGradient(inputs, labels, 0, inputs.Length, gradients);
        return gradients;
    }

    // LoRA: with G the gradient of the adapted matrix, dB = (alpha / r) G A' and dA = (alpha / r) B' G
    public Dictionary<string, double[]> AdapterGradient(LambekAdapter adapter, Dictionary<string, double[]> gradients)
    {
        Dictionary<string, double[]> result = new Dictionary<string, double[]>(StringComparer.Ordinal);
        int rank = adapter.Rank;
        foreach (string target in adapter.Targets)
        {
            int rows = Shapes[target][0];
            int columns = Shapes[target][1];
            double[] g = gradients[target];
            double[] a = adapter.A[target];
            double[] b = adapter.B[target];
            double[] dA = new double[rank * columns];
            double[] dB = new double[rows * rank];
            for (int r = 0; r < rows; r++)
            {
                for (int k = 0; k < rank; k++)
                {
                    double forB = 0;
                    for (int c = 0; c < columns; c++)
                    {
                        forB += g[r * columns + c] * a[k * columns + c];
                        dA[k * columns + c] += b[r * rank + k] * g[r * columns + c] * adapter.Scale;
                    }
                    dB[r * rank + k] = forB * adapter.Scale;
                }
            }
            result[target + ".A"] = dA;
            result[target + ".B"] = dB;
        }
        return result;
    }

    // ---- Checks by finite differences (used by the tests) ----

    // |a - n| / max(|a| + |n|, floor): the relative error between the gradient by hand and by differences
    public static double RelativeError(double analytic, double numeric)
    {
        return Math.Abs(analytic - numeric) / Math.Max(Math.Abs(analytic) + Math.Abs(numeric), 1e-8);
    }

    // For every base parameter, the worst relative error between the hand-written gradient and
    // (L(w + e) - L(w - e)) / 2e. Rows of the table no request uses have a zero gradient both ways
    public Dictionary<string, double> CheckGradient(int[][][] inputs, int[] labels, double step)
    {
        Dictionary<string, double[]> gradients = Gradient(inputs, labels);
        Dictionary<string, double> worst = new Dictionary<string, double>(StringComparer.Ordinal);
        foreach (string name in Names)
        {
            double[] values = Weights[name];
            double error = 0;
            for (int i = 0; i < values.Length; i++)
            {
                double kept = values[i];
                values[i] = kept + step;
                Refresh();
                double above = Loss(inputs, labels);
                values[i] = kept - step;
                Refresh();
                double below = Loss(inputs, labels);
                values[i] = kept;
                error = Math.Max(error, RelativeError(gradients[name][i], (above - below) / (2.0 * step)));
            }
            Refresh();
            worst[name] = error;
        }
        return worst;
    }

    // The same for A and B of an attached adapter (the base does not move)
    public Dictionary<string, double> CheckAdapterGradient(LambekAdapter adapter, int[][][] inputs, int[] labels, double step)
    {
        Dictionary<string, double[]> gradients = AdapterGradient(adapter, Gradient(inputs, labels));
        Dictionary<string, double> worst = new Dictionary<string, double>(StringComparer.Ordinal);
        foreach (string target in adapter.Targets)
        {
            foreach (string part in new string[] { "A", "B" })
            {
                double[] values = part == "A" ? adapter.A[target] : adapter.B[target];
                double[] gradient = gradients[target + "." + part];
                double error = 0;
                for (int i = 0; i < values.Length; i++)
                {
                    double kept = values[i];
                    values[i] = kept + step;
                    Refresh();
                    double above = Loss(inputs, labels);
                    values[i] = kept - step;
                    Refresh();
                    double below = Loss(inputs, labels);
                    values[i] = kept;
                    error = Math.Max(error, RelativeError(gradient[i], (above - below) / (2.0 * step)));
                }
                Refresh();
                worst[target + "." + part] = error;
            }
        }
        return worst;
    }

    // ---- Training ----

    // Mini-batches in the order given, Adam, a rate that goes down in a line to a tenth of itself.
    // Without an adapter the base learns (no adapter may be attached). With one, the base is frozen:
    // only A and B of that adapter move. Returns the mean loss of each pass
    public double[] Fit(int[][][] inputs, int[] labels, int epochs, int batch, double rate, LambekAdapter adapter)
    {
        if (adapter == null && Adapters.Count > 0) throw new InvalidOperationException("Detach the adapters before training the base.");
        if (adapter != null && !Adapters.Contains(adapter)) throw new InvalidOperationException("Attach the adapter before training it.");
        LambekAdam adam = new LambekAdam();
        Dictionary<string, double[]> gradients = NewGradients();
        double[] losses = new double[epochs];
        int batches = (inputs.Length + batch - 1) / batch;
        int total = Math.Max(1, epochs * batches);
        int done = 0;
        for (int epoch = 0; epoch < epochs; epoch++)
        {
            double sum = 0;
            for (int from = 0; from < inputs.Length; from += batch)
            {
                int count = Math.Min(batch, inputs.Length - from);
                sum += BatchGradient(inputs, labels, from, count, gradients) * count;
                adam.Rate = rate * (1.0 - 0.9 * done / total);
                adam.Begin();
                if (adapter == null)
                {
                    foreach (string name in Names) adam.Update(name, Weights[name], gradients[name]);
                }
                else
                {
                    Dictionary<string, double[]> own = AdapterGradient(adapter, gradients);
                    foreach (string target in adapter.Targets)
                    {
                        adam.Update(target + ".A", adapter.A[target], own[target + ".A"]);
                        adam.Update(target + ".B", adapter.B[target], own[target + ".B"]);
                    }
                    Refresh();
                }
                done++;
            }
            losses[epoch] = sum / inputs.Length;
        }
        Refresh();
        return losses;
    }

    // One more request the user confirmed, for an adapter: it is kept with the others (the oldest go after
    // MaxExamples), then a few steps on all of them, in one batch. The base does not move
    public double[] Learn(LambekAdapter adapter, string text, string label, int steps, double rate)
    {
        if (ClassIndex(label) < 0) throw new ArgumentException("The proposer does not know this action: " + label);
        adapter.Texts.Add(text);
        adapter.Labels.Add(label);
        while (adapter.Texts.Count > LambekAdapter.MaxExamples)
        {
            adapter.Texts.RemoveAt(0);
            adapter.Labels.RemoveAt(0);
        }
        int[][][] inputs = new int[adapter.Texts.Count][][];
        int[] labels = new int[adapter.Texts.Count];
        for (int i = 0; i < inputs.Length; i++)
        {
            inputs[i] = Encode(adapter.Texts[i]);
            labels[i] = ClassIndex(adapter.Labels[i]);
        }
        return Fit(inputs, labels, steps, inputs.Length, rate, adapter);
    }

    // ---- Use ----

    public double[] Predict(string text)
    {
        return Forward(Encode(text), null);
    }

    // The classes from the most to the least probable (the first in the list wins a tie)
    public static int[] Rank(double[] probabilities)
    {
        int[] order = new int[probabilities.Length];
        for (int i = 0; i < order.Length; i++) order[i] = i;
        Array.Sort(order, (a, b) => probabilities[a] != probabilities[b] ? probabilities[b].CompareTo(probabilities[a]) : a.CompareTo(b));
        return order;
    }

    public int ClassIndex(string name)
    {
        for (int i = 0; i < Classes.Length; i++)
        {
            if (string.Equals(Classes[i], name, StringComparison.Ordinal)) return i;
        }
        return -1;
    }

    // ---- File ----

    // Doubles as base64 of their 8 bytes, low byte first: exact, and the same on every machine
    public static string Pack(double[] values)
    {
        byte[] bytes = new byte[values.Length * 8];
        for (int i = 0; i < values.Length; i++)
        {
            long bits = BitConverter.DoubleToInt64Bits(values[i]);
            for (int b = 0; b < 8; b++) bytes[i * 8 + b] = (byte)((bits >> (8 * b)) & 0xFF);
        }
        return Convert.ToBase64String(bytes);
    }

    public static double[] Unpack(string text)
    {
        byte[] bytes = Convert.FromBase64String(text);
        double[] values = new double[bytes.Length / 8];
        for (int i = 0; i < values.Length; i++)
        {
            long bits = 0;
            for (int b = 0; b < 8; b++) bits |= ((long)bytes[i * 8 + b]) << (8 * b);
            values[i] = BitConverter.Int64BitsToDouble(bits);
        }
        return values;
    }

    // A short name of the base weights: an adapter only fits the base it was trained on
    public string Fingerprint()
    {
        using (SHA256 sha = SHA256.Create())
        {
            StringBuilder text = new StringBuilder();
            foreach (string name in Names) text.Append(name).Append('=').Append(Pack(Weights[name])).Append(';');
            byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes(text.ToString()));
            StringBuilder hex = new StringBuilder();
            for (int i = 0; i < 8; i++) hex.Append(hash[i].ToString("x2", CultureInfo.InvariantCulture));
            return hex.ToString();
        }
    }

    // The base only: adapters live in their own files
    public string Save()
    {
        using (MemoryStream stream = new MemoryStream())
        {
            JsonWriterOptions options = new JsonWriterOptions();
            options.Indented = true;
            using (Utf8JsonWriter writer = new Utf8JsonWriter(stream, options))
            {
                writer.WriteStartObject();
                writer.WriteString("Format", Format);
                writer.WriteNumber("Rows", Rows);
                writer.WriteNumber("Dim", Dim);
                writer.WriteNumber("Heads", Heads);
                writer.WriteNumber("Layers", Layers);
                writer.WriteNumber("Hidden", Hidden);
                writer.WriteNumber("MaxWords", MaxWords);
                writer.WriteNumber("Seed", Seed);
                writer.WriteString("Threshold", Threshold.ToString("R", CultureInfo.InvariantCulture));
                writer.WriteStartArray("Classes");
                foreach (string name in Classes) writer.WriteStringValue(name);
                writer.WriteEndArray();
                writer.WriteStartObject("Notes");
                foreach (KeyValuePair<string, string> note in Notes) writer.WriteString(note.Key, note.Value);
                writer.WriteEndObject();
                writer.WriteStartObject("Weights");
                foreach (string name in Names)
                {
                    writer.WriteStartObject(name);
                    writer.WriteNumber("Rows", Shapes[name][0]);
                    writer.WriteNumber("Columns", Shapes[name][1]);
                    writer.WriteString("Values", Pack(Weights[name]));
                    writer.WriteEndObject();
                }
                writer.WriteEndObject();
                writer.WriteEndObject();
            }
            return Encoding.UTF8.GetString(stream.ToArray()).Replace("\r\n", "\n") + "\n";
        }
    }

    public static LambekTransformer Load(string json)
    {
        using (JsonDocument document = JsonDocument.Parse(json))
        {
            JsonElement root = document.RootElement;
            if (root.GetProperty("Format").GetString() != Format) throw new InvalidDataException("This is not a Lambek proposer file.");
            LambekTransformer model = new LambekTransformer();
            model.Rows = root.GetProperty("Rows").GetInt32();
            model.Dim = root.GetProperty("Dim").GetInt32();
            model.Heads = root.GetProperty("Heads").GetInt32();
            model.Layers = root.GetProperty("Layers").GetInt32();
            model.Hidden = root.GetProperty("Hidden").GetInt32();
            model.MaxWords = root.GetProperty("MaxWords").GetInt32();
            model.Seed = root.GetProperty("Seed").GetUInt64();
            model.Threshold = double.Parse(root.GetProperty("Threshold").GetString(), CultureInfo.InvariantCulture);
            List<string> classes = new List<string>();
            foreach (JsonElement name in root.GetProperty("Classes").EnumerateArray()) classes.Add(name.GetString());
            model.Classes = classes.ToArray();
            foreach (JsonProperty note in root.GetProperty("Notes").EnumerateObject()) model.Notes[note.Name] = note.Value.GetString();
            foreach (JsonProperty weight in root.GetProperty("Weights").EnumerateObject())
            {
                model.Names.Add(weight.Name);
                model.Weights[weight.Name] = Unpack(weight.Value.GetProperty("Values").GetString());
                model.Shapes[weight.Name] = new int[] { weight.Value.GetProperty("Rows").GetInt32(), weight.Value.GetProperty("Columns").GetInt32() };
            }
            model.Prepare();
            return model;
        }
    }
}
