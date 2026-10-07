// The memory of Lambek: what the user confirmed, found again by four views fused by rank,
// and the words it learns from what it sees (Pursuit).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

// One thing remembered: a request the user confirmed, or an example of a pack
public class LambekMemoryItem
{
    public string Id;
    public string Kind;
    public string Text;
    public string Language;
    public string[] Terms;
    public string[] Grams;
    public string[] Structure;
    public string Payload;
    public double Time;
    public List<double> Uses = new List<double>();
    public byte[] Leaf;
}

// One item found again, with the score of each view
public class LambekRecall
{
    public LambekMemoryItem Item;
    public double Score;
    public double Lexical;
    public double Shape;
    public double Meaning;
    public double Activation;
    public double Probability;
}

public class LambekMemory
{
    // BM25 (Robertson), rank fusion (Cormack 2009), base-level activation (ACT-R)
    public static double K1 = 1.2;
    public static double B = 0.75;
    public static double FusionK = 60;
    public static double Decay = 0.5;
    public static double Threshold = -7;
    public static double Noise = 0.4;

    public List<LambekMemoryItem> Items = new List<LambekMemoryItem>();
    Dictionary<string, LambekMemoryItem> byId = new Dictionary<string, LambekMemoryItem>(StringComparer.Ordinal);
    Dictionary<string, List<LambekMemoryItem>> terms = new Dictionary<string, List<LambekMemoryItem>>(StringComparer.Ordinal);
    Dictionary<string, List<LambekMemoryItem>> grams = new Dictionary<string, List<LambekMemoryItem>>(StringComparer.Ordinal);
    Dictionary<string, List<LambekMemoryItem>> shapes = new Dictionary<string, List<LambekMemoryItem>>(StringComparer.Ordinal);
    double length;

    public int Count { get { return Items.Count; } }

    public LambekMemoryItem Get(string id)
    {
        LambekMemoryItem item;
        return byId.TryGetValue(id, out item) ? item : null;
    }

    // Same kind, language, text and payload: the same memory, used once more
    public static string MakeId(string kind, string language, string text, string payload)
    {
        return Hex(Sha(Encoding.UTF8.GetBytes(kind + "\n" + language + "\n" + text + "\n" + payload))).Substring(0, 16);
    }

    public LambekMemoryItem Add(string kind, string text, string language, string[] words, string[] structure, string payload, double time)
    {
        string id = MakeId(kind, language, text, payload);
        LambekMemoryItem found = Get(id);
        if (found != null)
        {
            found.Uses.Add(time);
            return found;
        }

        var item = new LambekMemoryItem();
        item.Id = id;
        item.Kind = kind;
        item.Text = text;
        item.Language = language;
        item.Terms = words ?? new string[0];
        item.Grams = Trigrams(text);
        item.Structure = (structure ?? new string[0]).Distinct(StringComparer.Ordinal).ToArray();
        item.Payload = payload ?? "";
        item.Time = time;
        item.Uses.Add(time);
        item.Leaf = Sha(Prefix(0, Encoding.UTF8.GetBytes(Line(item))));
        Items.Add(item);
        byId[id] = item;
        length += item.Terms.Length;
        Index(terms, item.Terms.Distinct(StringComparer.Ordinal), item);
        Index(grams, item.Grams, item);
        Index(shapes, item.Structure, item);
        return item;
    }

    public void Use(string id, double time)
    {
        LambekMemoryItem item = Get(id);
        if (item != null) item.Uses.Add(time);
    }

    static void Index(Dictionary<string, List<LambekMemoryItem>> index, IEnumerable<string> keys, LambekMemoryItem item)
    {
        foreach (string key in keys)
        {
            List<LambekMemoryItem> list;
            if (!index.TryGetValue(key, out list)) { list = new List<LambekMemoryItem>(); index[key] = list; }
            list.Add(item);
        }
    }

    // Letters in threes, without accents, with a space on each side: "tmp" gives " tm", "tmp", "mp "
    public static string[] Trigrams(string text)
    {
        string plain = Plain(text);
        var set = new HashSet<string>(StringComparer.Ordinal);
        foreach (string word in plain.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries))
        {
            string padded = " " + word + " ";
            for (int i = 0; i + 3 <= padded.Length; i++) set.Add(padded.Substring(i, 3));
        }
        return set.ToArray();
    }

    public static string Plain(string text)
    {
        var builder = new StringBuilder();
        foreach (char c in (text ?? "").Normalize(NormalizationForm.FormD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
            builder.Append(char.IsLetterOrDigit(c) || c == '.' ? char.ToLowerInvariant(c) : ' ');
        }
        return builder.ToString();
    }

    // Activation: B = ln(sum of age^-d), ages in seconds, at least one
    public static double Activation(LambekMemoryItem item, double now)
    {
        double sum = 0;
        foreach (double time in item.Uses) sum += Math.Pow(Math.Max(now - time, 1), -Decay);
        return sum > 0 ? Math.Log(sum) : double.NegativeInfinity;
    }

    // Chance to be found again: 1 / (1 + e^(-(A - tau) / s))
    public static double Probability(double activation)
    {
        return 1 / (1 + Math.Exp(-(activation - Threshold) / Noise));
    }

    // BM25 of every item sharing a term with the query
    Dictionary<LambekMemoryItem, double> Lexical(string[] query, string kind)
    {
        var scores = new Dictionary<LambekMemoryItem, double>();
        if (Items.Count == 0) return scores;
        double average = Math.Max(length / Items.Count, 1);
        foreach (string term in query.Distinct(StringComparer.Ordinal))
        {
            List<LambekMemoryItem> list;
            if (!terms.TryGetValue(term, out list)) continue;
            double idf = Math.Log(1 + (Items.Count - list.Count + 0.5) / (list.Count + 0.5));
            foreach (LambekMemoryItem item in list)
            {
                if (kind != null && item.Kind != kind) continue;
                int tf = 0;
                foreach (string t in item.Terms) if (t == term) tf++;
                double part = idf * tf * (K1 + 1) / (tf + K1 * (1 - B + B * item.Terms.Length / average));
                double old;
                scores.TryGetValue(item, out old);
                scores[item] = old + part;
            }
        }
        return scores;
    }

    // Jaccard of two sets, found through the index
    static Dictionary<LambekMemoryItem, double> Overlap(Dictionary<string, List<LambekMemoryItem>> index, string[] query, Func<LambekMemoryItem, string[]> keys, string kind)
    {
        var shared = new Dictionary<LambekMemoryItem, int>();
        var distinct = new HashSet<string>(query, StringComparer.Ordinal);
        foreach (string key in distinct)
        {
            List<LambekMemoryItem> list;
            if (!index.TryGetValue(key, out list)) continue;
            foreach (LambekMemoryItem item in list)
            {
                if (kind != null && item.Kind != kind) continue;
                int old;
                shared.TryGetValue(item, out old);
                shared[item] = old + 1;
            }
        }
        var scores = new Dictionary<LambekMemoryItem, double>();
        foreach (var pair in shared)
        {
            int union = distinct.Count + keys(pair.Key).Length - pair.Value;
            scores[pair.Key] = union > 0 ? (double)pair.Value / union : 0;
        }
        return scores;
    }

    // The ranks of one view: best first, ties by id so the same memory always gives the same order
    static Dictionary<LambekMemoryItem, int> Ranks(Dictionary<LambekMemoryItem, double> scores)
    {
        var ranks = new Dictionary<LambekMemoryItem, int>();
        int rank = 0;
        foreach (var pair in scores.Where(p => p.Value > 0).OrderByDescending(p => p.Value).ThenBy(p => p.Key.Id, StringComparer.Ordinal))
        {
            ranks[pair.Key] = ++rank;
        }
        return ranks;
    }

    // Four views fused by rank: sum of 1 / (60 + rank). Only items one of the first three views found take part,
    // unless the query is empty: then the most active items come back
    public List<LambekRecall> Recall(string[] query, string text, string[] structure, double now, int first, string kind)
    {
        // PowerShell passes an empty string for no kind
        if (string.IsNullOrEmpty(kind)) kind = null;
        query = query ?? new string[0];
        structure = structure ?? new string[0];
        var lexical = Lexical(query, kind);
        var shape = Overlap(grams, Trigrams(text ?? ""), i => i.Grams, kind);
        var meaning = Overlap(shapes, structure, i => i.Structure, kind);

        var candidates = new HashSet<LambekMemoryItem>(lexical.Keys);
        candidates.UnionWith(shape.Keys);
        candidates.UnionWith(meaning.Keys);
        if (query.Length == 0 && string.IsNullOrWhiteSpace(text) && structure.Length == 0)
        {
            foreach (LambekMemoryItem item in Items) if (kind == null || item.Kind == kind) candidates.Add(item);
        }

        var activation = new Dictionary<LambekMemoryItem, double>();
        foreach (LambekMemoryItem item in candidates) activation[item] = Activation(item, now);
        // Ranks need positive scores: shift the activations above zero, the order stays the same
        double lowest = activation.Count > 0 ? activation.Values.Min() : 0;
        var shifted = activation.ToDictionary(p => p.Key, p => p.Value - lowest + 1);

        var views = new List<Dictionary<LambekMemoryItem, int>> { Ranks(lexical), Ranks(shape), Ranks(meaning), Ranks(shifted) };
        var found = new List<LambekRecall>();
        foreach (LambekMemoryItem item in candidates)
        {
            var recall = new LambekRecall();
            recall.Item = item;
            foreach (var view in views)
            {
                int rank;
                if (view.TryGetValue(item, out rank)) recall.Score += 1 / (FusionK + rank);
            }
            double value;
            recall.Lexical = lexical.TryGetValue(item, out value) ? value : 0;
            recall.Shape = shape.TryGetValue(item, out value) ? value : 0;
            recall.Meaning = meaning.TryGetValue(item, out value) ? value : 0;
            recall.Activation = activation[item];
            recall.Probability = Probability(recall.Activation);
            found.Add(recall);
        }
        return found.OrderByDescending(r => r.Score).ThenBy(r => r.Item.Id, StringComparer.Ordinal).Take(Math.Max(first, 1)).ToList();
    }

    // Merkle root of the items in the order they came (RFC 6962): leaf SHA256(0 | line), node SHA256(1 | left | right)
    public string Root()
    {
        if (Items.Count == 0) return Hex(Sha(new byte[0]));
        return Hex(Node(0, Items.Count));
    }

    byte[] Node(int start, int count)
    {
        if (count == 1) return Items[start].Leaf;
        int split = 1;
        while (split * 2 < count) split *= 2;
        byte[] left = Node(start, split);
        byte[] right = Node(start + split, count - split);
        var both = new byte[1 + left.Length + right.Length];
        both[0] = 1;
        Buffer.BlockCopy(left, 0, both, 1, left.Length);
        Buffer.BlockCopy(right, 0, both, 1 + left.Length, right.Length);
        return Sha(both);
    }

    static byte[] Prefix(byte first, byte[] data)
    {
        var result = new byte[data.Length + 1];
        result[0] = first;
        Buffer.BlockCopy(data, 0, result, 1, data.Length);
        return result;
    }

    static byte[] Sha(byte[] data)
    {
        using (var sha = SHA256.Create()) return sha.ComputeHash(data);
    }

    static string Hex(byte[] data)
    {
        var builder = new StringBuilder(data.Length * 2);
        foreach (byte b in data) builder.Append(b.ToString("x2"));
        return builder.ToString();
    }

    // One JSON line per new item, one per use
    public static string Line(LambekMemoryItem item)
    {
        using (var stream = new MemoryStream())
        {
            using (var writer = new Utf8JsonWriter(stream))
            {
                writer.WriteStartObject();
                writer.WriteString("Event", "add");
                writer.WriteString("Id", item.Id);
                writer.WriteString("Kind", item.Kind);
                writer.WriteString("Text", item.Text);
                writer.WriteString("Language", item.Language);
                WriteArray(writer, "Terms", item.Terms);
                WriteArray(writer, "Structure", item.Structure);
                writer.WriteString("Payload", item.Payload);
                writer.WriteNumber("Time", item.Time);
                writer.WriteEndObject();
            }
            return Encoding.UTF8.GetString(stream.ToArray());
        }
    }

    public static string UseLine(string id, double time)
    {
        using (var stream = new MemoryStream())
        {
            using (var writer = new Utf8JsonWriter(stream))
            {
                writer.WriteStartObject();
                writer.WriteString("Event", "use");
                writer.WriteString("Id", id);
                writer.WriteNumber("Time", time);
                writer.WriteEndObject();
            }
            return Encoding.UTF8.GetString(stream.ToArray());
        }
    }

    static void WriteArray(Utf8JsonWriter writer, string name, string[] values)
    {
        writer.WriteStartArray(name);
        foreach (string value in values) writer.WriteStringValue(value);
        writer.WriteEndArray();
    }

    static string[] ReadArray(JsonElement root, string name)
    {
        JsonElement element;
        if (!root.TryGetProperty(name, out element) || element.ValueKind != JsonValueKind.Array) return new string[0];
        return element.EnumerateArray().Select(e => e.GetString()).ToArray();
    }

    static string ReadString(JsonElement root, string name)
    {
        JsonElement element;
        return root.TryGetProperty(name, out element) && element.ValueKind == JsonValueKind.String ? element.GetString() : "";
    }

    // Read back from the file; a broken line is skipped, the rest still counts
    public static LambekMemory Load(string path)
    {
        var memory = new LambekMemory();
        if (!File.Exists(path)) return memory;
        foreach (string line in File.ReadLines(path))
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            try
            {
                using (JsonDocument document = JsonDocument.Parse(line))
                {
                    JsonElement root = document.RootElement;
                    double time = root.GetProperty("Time").GetDouble();
                    if (ReadString(root, "Event") == "use")
                    {
                        memory.Use(ReadString(root, "Id"), time);
                        continue;
                    }
                    memory.Add(ReadString(root, "Kind"), ReadString(root, "Text"), ReadString(root, "Language"),
                        ReadArray(root, "Terms"), ReadArray(root, "Structure"), ReadString(root, "Payload"), time);
                }
            }
            catch (Exception)
            {
                memory.Broken++;
            }
        }
        return memory;
    }

    public int Broken;

    public static void Append(string path, string line)
    {
        string folder = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(folder)) Directory.CreateDirectory(folder);
        File.AppendAllText(path, line + "\n", new UTF8Encoding(false));
    }
}

// Pursuit (Stevens, Gleitman, Trueswell and Yang 2017): each word tests one meaning at a time.
// Confirmed: A += gamma (1 - A). Not in the situation: A *= 1 - gamma, and the most novel meaning is tried.
// A word is learned when (A + lambda) / (sum A + N lambda) > theta
public class LambekPursuit
{
    public double Gamma = 0.25;
    public double Lambda = 0.01;
    public double Theta = 0.7;
    public int Least = 10;

    public Dictionary<string, Dictionary<string, double>> Words = new Dictionary<string, Dictionary<string, double>>(StringComparer.Ordinal);
    HashSet<string> meanings = new HashSet<string>(StringComparer.Ordinal);

    public int Meanings { get { return meanings.Count; } }

    // The meaning a word is tested with now: the strongest, ties by name
    public string Hypothesis(string word)
    {
        Dictionary<string, double> known;
        if (!Words.TryGetValue(word, out known) || known.Count == 0) return null;
        return known.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal).First().Key;
    }

    // The most novel meaning of the situation: the one no word is strongly tied to yet
    string Novel(string[] situation)
    {
        return situation.Distinct(StringComparer.Ordinal)
            .OrderBy(m => Words.Values.Select(a => a.ContainsKey(m) ? a[m] : 0).DefaultIfEmpty(0).Max())
            .ThenBy(m => m, StringComparer.Ordinal)
            .First();
    }

    public void Observe(string word, string[] situation)
    {
        if (situation == null || situation.Length == 0) return;
        foreach (string meaning in situation) meanings.Add(meaning);
        Dictionary<string, double> known;
        if (!Words.TryGetValue(word, out known)) { known = new Dictionary<string, double>(StringComparer.Ordinal); Words[word] = known; }

        string tested = Hypothesis(word);
        if (tested != null && situation.Contains(tested, StringComparer.Ordinal))
        {
            known[tested] += Gamma * (1 - known[tested]);
            return;
        }
        if (tested != null) known[tested] *= 1 - Gamma;
        string next = Novel(situation);
        double old;
        known.TryGetValue(next, out old);
        known[next] = old + Gamma * (1 - old);
    }

    public double Chance(string word, string meaning)
    {
        Dictionary<string, double> known;
        if (!Words.TryGetValue(word, out known)) return 0;
        double value;
        known.TryGetValue(meaning, out value);
        int n = Math.Max(meanings.Count, Least);
        return (value + Lambda) / (known.Values.Sum() + n * Lambda);
    }

    // The meaning the word has taken, or nothing yet
    public string Learned(string word)
    {
        string tested = Hypothesis(word);
        return tested != null && Chance(word, tested) > Theta ? tested : null;
    }

    public string Save()
    {
        using (var stream = new MemoryStream())
        {
            using (var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true }))
            {
                writer.WriteStartObject();
                foreach (string word in Words.Keys.OrderBy(w => w, StringComparer.Ordinal))
                {
                    writer.WriteStartObject(word);
                    foreach (var pair in Words[word].OrderBy(p => p.Key, StringComparer.Ordinal)) writer.WriteNumber(pair.Key, Math.Round(pair.Value, 6));
                    writer.WriteEndObject();
                }
                writer.WriteEndObject();
            }
            return Encoding.UTF8.GetString(stream.ToArray());
        }
    }

    public static LambekPursuit Load(string text)
    {
        var pursuit = new LambekPursuit();
        if (string.IsNullOrWhiteSpace(text)) return pursuit;
        using (JsonDocument document = JsonDocument.Parse(text))
        {
            foreach (JsonProperty word in document.RootElement.EnumerateObject())
            {
                var known = new Dictionary<string, double>(StringComparer.Ordinal);
                foreach (JsonProperty meaning in word.Value.EnumerateObject())
                {
                    known[meaning.Name] = meaning.Value.GetDouble();
                    pursuit.meanings.Add(meaning.Name);
                }
                pursuit.Words[word.Name] = known;
            }
        }
        return pursuit;
    }
}
