// The router of Lambek: what a message is (an order, something told, a question about the world, small talk...)
// before any reader reads it. A message is a vector Lambek builds itself, with nothing downloaded:
//   how it is written (a question mark, numbers, an operation, a path, a name, its length),
//   its first and last words, its small words (articles, pronouns, question words),
//   its other words, the pieces of four letters they are made of (a typing slip keeps most of them).
// (The meanings WordNet gives the words were tried too, as the same synset in every language: on the bench of acts they
// changed one answer in 140 and cost a dictionary loaded for every language, so they were left out.)
// Each part of the vector weighs less the more examples share it. Two ways read the act from the examples, as two
// satellites give a position: the nearest examples vote (cosine), and a vector learnt for each act weighs the message.
// The router says an act only when both say the same one; otherwise it abstains, and the readers decide alone, as
// before it. Everything is sorted ordinally and rounded, so the same message gives the same act on every machine.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

// What the router says of a message
public class LambekRoute
{
    public string Act;
    public double Score;
    public double Similarity;
    public double Margin;
    public string Second;
    public bool Abstained;
    public string[] Neighbours;
}

public class LambekRouter
{
    class Example
    {
        public string Act;
        public string Language;
        public string Text;
        public string[] Features;
        public Dictionary<string, double> Vector;
        public double Norm;
    }

    readonly List<Example> examples = new List<Example>();
    readonly Dictionary<string, int> shared = new Dictionary<string, int>(StringComparer.Ordinal);
    bool ready;

    // How much each kind of feature weighs, by its prefix: c (how it is written), q (a question mark), b (first words), e (last word),
    // f (small words), w (other words), g (pieces of words)
    public Dictionary<string, double> Weights = new Dictionary<string, double>(StringComparer.Ordinal)
    {
        { "c", 1.0 }, { "q", 2.0 }, { "b", 1.0 }, { "e", 0.5 }, { "f", 0.7 }, { "w", 1.0 }, { "g", 0.3 }
    };

    public int Count { get { return examples.Count; } }

    public void Add(string act, string language, string text, string[] features)
    {
        examples.Add(new Example { Act = act, Language = language, Text = text, Features = Distinct(features) });
        ready = false;
    }

    // ---- Features ----

    static readonly Regex PathPattern = new Regex(@"(?:[A-Za-z]:\\|\\\\)[^\s,;?!""]*", RegexOptions.CultureInvariant);
    static readonly Regex FilePattern = new Regex(@"(?<![\w.])[\w-]+\.[A-Za-z][A-Za-z0-9]{1,4}\b", RegexOptions.CultureInvariant);
    static readonly Regex ExtensionPattern = new Regex(@"(?<![\w.])\.[A-Za-z][A-Za-z0-9]{1,4}\b", RegexOptions.CultureInvariant);
    static readonly Regex NumberPattern = new Regex(@"\d+(?:[.,]\d+)?", RegexOptions.CultureInvariant);
    static readonly Regex OperationPattern = new Regex(@"\d\s*[-+*/×÷^=%]\s*[\dx(]|[a-z]\s*[-+]\s*\d+\s*=", RegexOptions.CultureInvariant);
    static readonly Regex SentencePattern = new Regex(@"[.!?]\s+\p{L}", RegexOptions.CultureInvariant);
    static readonly Regex SplitPattern = new Regex(@"[^\p{L}\p{N}]+", RegexOptions.CultureInvariant);

    // The words of a message, without accents and in small letters; a path, a file, an extension, a number are
    // each one word that says what it is
    public static string[] Tokens(string text)
    {
        string plain = PathPattern.Replace(text, " zpath ");
        plain = FilePattern.Replace(plain, " zfile ");
        plain = ExtensionPattern.Replace(plain, " zext ");
        plain = NumberPattern.Replace(plain, " znum ");
        plain = LambekDictionary.Normalize(plain);
        return SplitPattern.Split(plain).Where(token => token.Length > 0).ToArray();
    }

    static bool Marker(string token)
    {
        return token == "zpath" || token == "zfile" || token == "zext" || token == "znum";
    }

    // How the message is written, its words and the pieces of its words: what needs no dictionary
    public static string[] Surface(string text, ICollection<string> small)
    {
        List<string> features = new List<string>();
        string trimmed = text.Trim();
        string[] tokens = Tokens(text);

        if (trimmed.EndsWith("?") || trimmed.StartsWith("¿")) features.Add("q:question");
        if (trimmed.EndsWith("!") || trimmed.StartsWith("¡")) features.Add("c:exclamation");
        if (SentencePattern.IsMatch(trimmed)) features.Add("c:sentences");
        int numbers = tokens.Count(token => token == "znum");
        if (numbers >= 1) features.Add("c:number");
        if (numbers >= 2) features.Add("c:numbers");
        if (numbers >= 3) features.Add("c:many-numbers");
        if (OperationPattern.IsMatch(trimmed)) features.Add("c:operation");
        if (tokens.Contains("zpath")) features.Add("c:path");
        if (tokens.Contains("zfile")) features.Add("c:file");
        if (tokens.Contains("zext")) features.Add("c:extension");

        // A word with a capital that does not open a sentence: a name
        string[] raw = trimmed.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
        for (int i = 1; i < raw.Length; i++)
        {
            string word = raw[i].TrimStart('"', '«', '(', '¿', '¡');
            if (word.Length > 1 && char.IsUpper(word[0]) && char.IsLower(word[1]) && !Regex.IsMatch(raw[i - 1], @"[.!?:]$")) { features.Add("c:name"); break; }
        }

        int count = tokens.Length;
        features.Add(count <= 1 ? "c:length1" : count <= 3 ? "c:length2" : count <= 8 ? "c:length4" : "c:length9");

        if (count > 0)
        {
            features.Add("b:0:" + tokens[0]);
            features.Add("e:" + tokens[count - 1]);
        }
        if (count > 1)
        {
            features.Add("b:1:" + tokens[1]);
            features.Add("b:01:" + tokens[0] + "_" + tokens[1]);
        }
        foreach (string token in tokens)
        {
            if (Marker(token)) continue;
            if (small != null && small.Contains(token)) { features.Add("f:" + token); continue; }
            if (token.Length < 2) continue;
            features.Add("w:" + token);
            string padded = "<" + token + ">";
            if (padded.Length <= 4) { features.Add("g:" + padded); continue; }
            for (int i = 0; i + 4 <= padded.Length; i++) features.Add("g:" + padded.Substring(i, 4));
        }
        return Distinct(features.ToArray());
    }

    static string[] Distinct(string[] features)
    {
        string[] result = features.Distinct(StringComparer.Ordinal).ToArray();
        Array.Sort(result, StringComparer.Ordinal);
        return result;
    }

    // ---- Vectors ----

    double Weight(string feature)
    {
        int colon = feature.IndexOf(':');
        double weight;
        if (colon < 0 || !Weights.TryGetValue(feature.Substring(0, colon), out weight)) weight = 1.0;
        // A feature many examples share tells little; one no example has tells the most, but matches none
        int count;
        if (!shared.TryGetValue(feature, out count) || count < 1) count = 1;
        return weight / Math.Sqrt(count);
    }

    void Prepare()
    {
        if (ready) return;
        shared.Clear();
        foreach (Example example in examples)
        {
            foreach (string feature in example.Features)
            {
                int count;
                shared.TryGetValue(feature, out count);
                shared[feature] = count + 1;
            }
        }
        foreach (Example example in examples)
        {
            example.Vector = new Dictionary<string, double>(StringComparer.Ordinal);
            double sum = 0;
            foreach (string feature in example.Features)
            {
                double weight = Weight(feature);
                if (weight <= 0) continue;
                example.Vector[feature] = weight;
                sum += weight * weight;
            }
            example.Norm = Math.Sqrt(sum);
        }
        Train();
        ready = true;
    }

    // ---- What each act weighs ----
    // Besides the examples themselves, one vector for each act, learnt from them: an averaged perceptron, which
    // learns which features tell an act from another ("est-ce que" and a question mark tell a question from a fact,
    // which no word of the sentence does). Its passes are in a fixed order, so it learns the same on every machine
    public int Passes = 12;
    readonly Dictionary<string, Dictionary<string, double>> learnt = new Dictionary<string, Dictionary<string, double>>(StringComparer.Ordinal);
    string[] acts = new string[0];

    static double Get(Dictionary<string, double> table, string key)
    {
        double value;
        return table.TryGetValue(key, out value) ? value : 0;
    }

    void Train()
    {
        learnt.Clear();
        acts = examples.Select(example => example.Act).Distinct(StringComparer.Ordinal).OrderBy(act => act, StringComparer.Ordinal).ToArray();
        Dictionary<string, Dictionary<string, double>> current = new Dictionary<string, Dictionary<string, double>>(StringComparer.Ordinal);
        Dictionary<string, Dictionary<string, double>> summed = new Dictionary<string, Dictionary<string, double>>(StringComparer.Ordinal);
        foreach (string act in acts)
        {
            current[act] = new Dictionary<string, double>(StringComparer.Ordinal);
            summed[act] = new Dictionary<string, double>(StringComparer.Ordinal);
        }
        int[] order = Enumerable.Range(0, examples.Count).ToArray();
        long seed = 20261020;
        double step = 1;
        for (int pass = 0; pass < Passes; pass++)
        {
            // The same shuffle everywhere: a linear congruential generator, not the random numbers of the machine
            for (int i = order.Length - 1; i > 0; i--)
            {
                seed = (seed * 6364136223846793005L + 1442695040888963407L) & long.MaxValue;
                int j = (int)(seed % (i + 1));
                int swap = order[i]; order[i] = order[j]; order[j] = swap;
            }
            foreach (int index in order)
            {
                Example example = examples[index];
                if (example.Norm <= 0) { step++; continue; }
                string guessed = Best(current, example.Vector, example.Norm);
                if (guessed != example.Act)
                {
                    foreach (KeyValuePair<string, double> pair in example.Vector)
                    {
                        double value = pair.Value / example.Norm;
                        current[example.Act][pair.Key] = Get(current[example.Act], pair.Key) + value;
                        summed[example.Act][pair.Key] = Get(summed[example.Act], pair.Key) + step * value;
                        current[guessed][pair.Key] = Get(current[guessed], pair.Key) - value;
                        summed[guessed][pair.Key] = Get(summed[guessed], pair.Key) - step * value;
                    }
                }
                step++;
            }
        }
        // Averaged over every step: steadier than the last vector alone
        foreach (string act in acts)
        {
            Dictionary<string, double> averaged = new Dictionary<string, double>(StringComparer.Ordinal);
            foreach (KeyValuePair<string, double> pair in current[act])
            {
                double value = pair.Value - Get(summed[act], pair.Key) / step;
                if (value != 0) averaged[pair.Key] = value;
            }
            learnt[act] = averaged;
        }
    }

    string Best(Dictionary<string, Dictionary<string, double>> table, Dictionary<string, double> vector, double norm)
    {
        string best = null;
        double top = double.NegativeInfinity;
        foreach (string act in acts)
        {
            double score = 0;
            foreach (KeyValuePair<string, double> pair in vector) score += Get(table[act], pair.Key) * pair.Value / norm;
            score = Math.Round(score, 9);
            if (score > top) { top = score; best = act; }
        }
        return best;
    }

    // The act whose learnt vector the message is closest to; the router abstains when the second act is closer than minMargin
    public LambekRoute Weigh(string[] features, double minMargin)
    {
        Prepare();
        Dictionary<string, double> vector = new Dictionary<string, double>(StringComparer.Ordinal);
        double sum = 0;
        foreach (string feature in Distinct(features ?? new string[0]))
        {
            double weight = Weight(feature);
            if (weight <= 0) continue;
            vector[feature] = weight;
            sum += weight * weight;
        }
        double norm = Math.Sqrt(sum);
        if (norm <= 0 || acts.Length == 0) return new LambekRoute { Abstained = true, Neighbours = new string[0] };
        List<KeyValuePair<string, double>> scores = new List<KeyValuePair<string, double>>();
        foreach (string act in acts)
        {
            double score = 0;
            foreach (KeyValuePair<string, double> pair in vector) score += Get(learnt[act], pair.Key) * pair.Value / norm;
            scores.Add(new KeyValuePair<string, double>(act, Math.Round(score, 9)));
        }
        scores.Sort((a, b) => a.Value != b.Value ? b.Value.CompareTo(a.Value) : string.CompareOrdinal(a.Key, b.Key));
        LambekRoute route = new LambekRoute
        {
            Act = scores[0].Key,
            Score = Math.Round(scores[0].Value, 6),
            Margin = Math.Round(scores[0].Value - (scores.Count > 1 ? scores[1].Value : 0), 6),
            Second = scores.Count > 1 ? scores[1].Key : null,
            Neighbours = new string[0]
        };
        route.Abstained = route.Margin < minMargin;
        return route;
    }

    // ---- Routing ----

    // The act of a message: its k nearest examples vote with their similarity. The router abstains when the nearest
    // example of the act chosen is less similar than minSimilarity, or when that act has less than minScore of the vote
    public LambekRoute Route(string[] features, int k, double minSimilarity, double minScore)
    {
        return Route(features, k, minSimilarity, minScore, null);
    }

    // (leaving out the examples written exactly as a text: to measure the router on its own examples)
    public LambekRoute Route(string[] features, int k, double minSimilarity, double minScore, string leaveOut)
    {
        Prepare();
        string[] asked = Distinct(features ?? new string[0]);
        double sum = 0;
        List<KeyValuePair<string, double>> query = new List<KeyValuePair<string, double>>();
        foreach (string feature in asked)
        {
            double weight = Weight(feature);
            if (weight <= 0) continue;
            query.Add(new KeyValuePair<string, double>(feature, weight));
            sum += weight * weight;
        }
        double norm = Math.Sqrt(sum);
        LambekRoute none = new LambekRoute { Act = null, Abstained = true, Neighbours = new string[0] };
        if (norm <= 0 || examples.Count == 0) return none;

        List<Tuple<double, int>> scored = new List<Tuple<double, int>>();
        for (int i = 0; i < examples.Count; i++)
        {
            Example example = examples[i];
            if (example.Norm <= 0) continue;
            if (leaveOut != null && string.Equals(example.Text, leaveOut, StringComparison.Ordinal)) continue;
            double dot = 0;
            foreach (KeyValuePair<string, double> pair in query)
            {
                double weight;
                if (example.Vector.TryGetValue(pair.Key, out weight)) dot += pair.Value * weight;
            }
            if (dot <= 0) continue;
            // Rounded: the last digits of a sum may differ from one machine to another, the act may not
            scored.Add(Tuple.Create(Math.Round(dot / (norm * example.Norm), 9), i));
        }
        if (scored.Count == 0) return none;
        scored.Sort((a, b) => a.Item1 != b.Item1 ? b.Item1.CompareTo(a.Item1) : a.Item2.CompareTo(b.Item2));
        List<Tuple<double, int>> nearest = scored.Take(Math.Max(1, k)).ToList();

        Dictionary<string, double> votes = new Dictionary<string, double>(StringComparer.Ordinal);
        Dictionary<string, double> closest = new Dictionary<string, double>(StringComparer.Ordinal);
        double total = 0;
        foreach (Tuple<double, int> near in nearest)
        {
            string act = examples[near.Item2].Act;
            double vote;
            votes.TryGetValue(act, out vote);
            votes[act] = vote + near.Item1;
            if (!closest.ContainsKey(act)) closest[act] = near.Item1;
            total += near.Item1;
        }
        List<string> ranked = votes.Keys.ToList();
        ranked.Sort((a, b) =>
        {
            int byVote = Math.Round(votes[b], 9).CompareTo(Math.Round(votes[a], 9));
            if (byVote != 0) return byVote;
            int byClosest = closest[b].CompareTo(closest[a]);
            return byClosest != 0 ? byClosest : string.CompareOrdinal(a, b);
        });
        string best = ranked[0];
        double score = Math.Round(votes[best] / total, 6);
        double second = ranked.Count > 1 ? votes[ranked[1]] : 0;
        LambekRoute route = new LambekRoute
        {
            Act = best,
            Score = score,
            Similarity = Math.Round(closest[best], 6),
            Margin = Math.Round((votes[best] - second) / total, 6),
            Second = ranked.Count > 1 ? ranked[1] : null,
            Neighbours = nearest.Take(3).Select(near => examples[near.Item2].Act + " " + near.Item1.ToString("0.000", CultureInfo.InvariantCulture) + " " + examples[near.Item2].Text).ToArray()
        };
        route.Abstained = route.Similarity < minSimilarity || route.Score < minScore;
        return route;
    }

    // The act of a message as both ways read it: said only when the nearest examples and the learnt vectors agree,
    // and the second act is no closer than minMargin to the vectors
    public LambekRoute Decide(string[] features, int k, double minMargin)
    {
        LambekRoute weighed = Weigh(features, 0);
        LambekRoute near = Route(features, k, 0, 0);
        LambekRoute route = new LambekRoute
        {
            Act = weighed.Act,
            Score = near.Score,
            Similarity = near.Similarity,
            Margin = weighed.Margin,
            Second = near.Act == weighed.Act ? weighed.Second : near.Act,
            Neighbours = near.Neighbours
        };
        route.Abstained = weighed.Act == null || near.Act != weighed.Act || weighed.Margin < minMargin;
        return route;
    }
}
