// The forms of words, learned: what Lambek reads in a word ("habitaient": habiter, a verb, imperfect, third person,
// plural) without a dictionary written by hand. It learns from treebanks, sentences where every word was annotated
// (Universal Dependencies), and keeps only what it learned:
//   a rule of form for each word: what to take off and put on its ends to find its lemma ("-aient" off, "-er" on),
//   read from the corpus itself, so that every lemma of the corpus is found again by its rule;
//   two perceptrons: one says the part of speech and the features of each word from the word, its ends and its
//   neighbours; the other says which rule of form to apply.
// Every weight is an integer and every pass goes in the same order, so the same corpus gives the same model, bit for
// bit, on every machine.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;

// One word of an annotated sentence
public class LambekTreebankWord
{
    public string Form;
    public string Lemma;
    public string Upos;
    public string Feats;
    public string Tag { get { return Upos + "|" + Feats; } }
}

public static class LambekTreebank
{
    // The words of every sentence of a CoNLL-U file: the syntactic words, not the written tokens they come from
    // ("du" is read as "de" and "le"); empty nodes are left out
    public static List<LambekTreebankWord[]> Read(string path)
    {
        List<LambekTreebankWord[]> sentences = new List<LambekTreebankWord[]>();
        List<LambekTreebankWord> words = new List<LambekTreebankWord>();
        foreach (string raw in File.ReadLines(path, Encoding.UTF8))
        {
            string line = raw.TrimEnd('\r');
            if (line.Length == 0)
            {
                if (words.Count > 0) { sentences.Add(words.ToArray()); words.Clear(); }
                continue;
            }
            if (line[0] == '#') continue;
            string[] columns = line.Split('\t');
            if (columns.Length < 6 || columns[0].IndexOf('-') >= 0 || columns[0].IndexOf('.') >= 0) continue;
            words.Add(new LambekTreebankWord { Form = columns[1], Lemma = columns[2], Upos = columns[3], Feats = columns[5] });
        }
        if (words.Count > 0) sentences.Add(words.ToArray());
        return sentences;
    }
}

// What to do to a form to find its lemma: its case first (all small letters, a capital first, all capitals, or kept),
// then how many letters to take off its start and its end, and what to put there instead. When the form and its lemma
// share nothing ("went", "go"), the rule is the lemma itself
public static class LambekFormRule
{
    public static string Of(string form, string lemma)
    {
        if (string.IsNullOrEmpty(form) || string.IsNullOrEmpty(lemma) || lemma == "_") return "=" + (lemma ?? "");
        string lower = form.ToLowerInvariant();
        string target = lemma.ToLowerInvariant();
        string casing = Casing(lemma, target);
        if (casing == null) return "=" + lemma;

        // The longest piece both share
        int bestLength = 0, bestForm = 0, bestLemma = 0;
        for (int i = 0; i < lower.Length; i++)
        {
            for (int j = 0; j < target.Length; j++)
            {
                int length = 0;
                while (i + length < lower.Length && j + length < target.Length && lower[i + length] == target[j + length]) length++;
                if (length > bestLength) { bestLength = length; bestForm = i; bestLemma = j; }
            }
        }
        if (bestLength == 0) return "=" + lemma;
        string front = target.Substring(0, bestLemma);
        int cut = lower.Length - bestForm - bestLength;
        string back = target.Substring(bestLemma + bestLength);
        return casing + "|" + bestForm.ToString(CultureInfo.InvariantCulture) + "|" + front + "|" + cut.ToString(CultureInfo.InvariantCulture) + "|" + back;
    }

    static string Casing(string lemma, string lower)
    {
        if (lemma == lower) return "l";
        if (lemma == lower.ToUpperInvariant()) return "u";
        if (lower.Length > 0 && lemma == char.ToUpperInvariant(lower[0]) + lower.Substring(1)) return "c";
        return null;
    }

    // The lemma a rule gives for a form, or null when the rule does not fit it (the form is too short)
    public static string Apply(string rule, string form)
    {
        if (rule == null || form == null) return null;
        if (rule.StartsWith("=", StringComparison.Ordinal)) return rule.Substring(1);
        string[] parts = rule.Split('|');
        if (parts.Length != 5) return null;
        int start = int.Parse(parts[1], CultureInfo.InvariantCulture);
        int end = int.Parse(parts[3], CultureInfo.InvariantCulture);
        string lower = form.ToLowerInvariant();
        if (start + end >= lower.Length) return null;
        string lemma = parts[2] + lower.Substring(start, lower.Length - start - end) + parts[4];
        switch (parts[0])
        {
            case "u": return lemma.ToUpperInvariant();
            case "c": return lemma.Length > 0 ? char.ToUpperInvariant(lemma[0]) + lemma.Substring(1) : lemma;
            default: return lemma;
        }
    }
}

// A perceptron over many classes with sparse features, in integers: each weight is the sum of the +1 and -1 it
// received, averaged over every step it lived (kept as step x weight - sum of the steps of its changes, which orders
// the classes exactly as the average does, without a single division)
public class LambekPerceptron
{
    public readonly List<string> Classes = new List<string>();
    readonly Dictionary<string, int> classIds = new Dictionary<string, int>(StringComparer.Ordinal);
    readonly Dictionary<string, int> featureIds = new Dictionary<string, int>(StringComparer.Ordinal);
    readonly List<string> features = new List<string>();
    readonly List<Dictionary<int, int>> slots = new List<Dictionary<int, int>>();
    readonly List<int> weights = new List<int>();
    readonly List<long> stamps = new List<long>();
    long step = 1;
    bool averaged;
    long[] final;
    long[] scores = new long[0];

    public int ClassOf(string name, bool add)
    {
        int id;
        if (classIds.TryGetValue(name, out id)) return id;
        if (!add) return -1;
        id = Classes.Count;
        Classes.Add(name);
        classIds[name] = id;
        return id;
    }

    int FeatureOf(string name, bool add)
    {
        int id;
        if (featureIds.TryGetValue(name, out id)) return id;
        if (!add) return -1;
        id = features.Count;
        features.Add(name);
        featureIds[name] = id;
        slots.Add(new Dictionary<int, int>());
        return id;
    }

    public int FeatureCount { get { return features.Count; } }
    public bool Has(string feature) { return featureIds.ContainsKey(feature); }
    public int WeightCount { get { return weights.Count; } }

    // The score of every class for these features
    public long[] Score(IList<string> active)
    {
        if (scores.Length != Classes.Count) scores = new long[Classes.Count];
        Array.Clear(scores, 0, scores.Length);
        foreach (string name in active)
        {
            int feature = FeatureOf(name, false);
            if (feature < 0) continue;
            foreach (KeyValuePair<int, int> slot in slots[feature])
            {
                scores[slot.Key] += averaged ? final[slot.Value] : weights[slot.Value];
            }
        }
        return scores;
    }

    // The best class, the first one on a tie; allowed says which classes may be chosen (null: all). The classes are
    // tried from the best down, so that allowed is asked of a few of them only
    public int Best(IList<string> active, Func<int, bool> allowed)
    {
        long[] score = Score(active);
        HashSet<int> refused = null;
        while (true)
        {
            int best = -1;
            for (int i = 0; i < score.Length; i++)
            {
                if (refused != null && refused.Contains(i)) continue;
                if (best < 0 || score[i] > score[best]) best = i;
            }
            if (best < 0 || allowed == null || allowed(best)) return best;
            if (refused == null) refused = new HashSet<int>();
            refused.Add(best);
        }
    }

    void Change(int feature, int @class, int delta)
    {
        int slot;
        if (!slots[feature].TryGetValue(@class, out slot))
        {
            slot = weights.Count;
            weights.Add(0);
            stamps.Add(0);
            slots[feature][@class] = slot;
        }
        weights[slot] += delta;
        stamps[slot] += step * delta;
    }

    // One example: when the guess is wrong, the right class gains one on each feature and the guess loses one
    public int Learn(IList<string> active, int truth, Func<int, bool> allowed)
    {
        averaged = false;
        int guess = Best(active, allowed);
        if (guess != truth)
        {
            foreach (string name in active)
            {
                int feature = FeatureOf(name, true);
                Change(feature, truth, 1);
                if (guess >= 0) Change(feature, guess, -1);
            }
        }
        step++;
        return guess;
    }

    public void Average()
    {
        final = new long[weights.Count];
        for (int i = 0; i < weights.Count; i++) final[i] = step * (long)weights[i] - stamps[i];
        averaged = true;
    }

    // Written in a fixed order, so the same model gives the same bytes
    public void Write(BinaryWriter writer)
    {
        if (!averaged) Average();
        writer.Write(Classes.Count);
        foreach (string name in Classes) writer.Write(name);
        int kept = 0;
        for (int f = 0; f < features.Count; f++) if (slots[f].Values.Any(slot => final[slot] != 0)) kept++;
        writer.Write(kept);
        for (int f = 0; f < features.Count; f++)
        {
            List<KeyValuePair<int, int>> live = slots[f].Where(slot => final[slot.Value] != 0).OrderBy(slot => slot.Key).ToList();
            if (live.Count == 0) continue;
            writer.Write(features[f]);
            writer.Write(live.Count);
            foreach (KeyValuePair<int, int> slot in live) { writer.Write(slot.Key); writer.Write(final[slot.Value]); }
        }
    }

    public static LambekPerceptron ReadFrom(BinaryReader reader)
    {
        LambekPerceptron model = new LambekPerceptron();
        int classes = reader.ReadInt32();
        for (int i = 0; i < classes; i++) model.ClassOf(reader.ReadString(), true);
        int count = reader.ReadInt32();
        List<long> values = new List<long>();
        for (int i = 0; i < count; i++)
        {
            int feature = model.FeatureOf(reader.ReadString(), true);
            int live = reader.ReadInt32();
            for (int j = 0; j < live; j++)
            {
                int @class = reader.ReadInt32();
                long value = reader.ReadInt64();
                model.slots[feature][@class] = values.Count;
                values.Add(value);
                model.weights.Add(0);
                model.stamps.Add(0);
            }
        }
        model.final = values.ToArray();
        model.averaged = true;
        return model;
    }
}

// What the forms model says of one word
public class LambekFormReading
{
    public string Form;
    public string Lemma;
    public string Upos;
    public string Feats;
    public string Rule;
}

// The model of forms of one language: a tagger (part of speech and features) and a lemmatiser (the rule of form)
public class LambekForms
{
    public string Language;
    public LambekPerceptron Tagger = new LambekPerceptron();
    public LambekPerceptron Lemmatiser = new LambekPerceptron();
    public int Passes = 10;
    public const string Format = "lambek-forms-1";

    // How the written text is cut into the words the model reads, learned from the same treebanks: the written tokens
    // that stand for several words ("du": de le, "au": à le), the pieces cut before an apostrophe ("l'", "qu'") and
    // after one ("'s", "n't")
    public readonly SortedDictionary<string, string> Contractions = new SortedDictionary<string, string>(StringComparer.Ordinal);
    public readonly SortedSet<string> Before = new SortedSet<string>(StringComparer.Ordinal);
    public readonly SortedSet<string> After = new SortedSet<string>(StringComparer.Ordinal);

    // The words seen when learning, in small letters
    public readonly SortedSet<string> Vocabulary = new SortedSet<string>(StringComparer.Ordinal);

    // Whether a word was seen when learning
    public bool Knows(string word) { return Vocabulary.Contains(word.ToLowerInvariant()); }

    public void LearnTokens(IEnumerable<string> paths)
    {
        Dictionary<string, Dictionary<string, int>> split = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
        Dictionary<string, int> whole = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (string path in paths)
        {
            string surface = null;
            int last = 0;
            List<string> parts = new List<string>();
            foreach (string raw in File.ReadLines(path, Encoding.UTF8))
            {
                string line = raw.TrimEnd('\r');
                if (line.Length == 0 || line[0] == '#') continue;
                string[] columns = line.Split('\t');
                if (columns.Length < 2) continue;
                int dash = columns[0].IndexOf('-');
                if (dash > 0)
                {
                    surface = columns[1].ToLowerInvariant().Replace('\u2019', '\'');
                    last = int.Parse(columns[0].Substring(dash + 1), CultureInfo.InvariantCulture);
                    parts.Clear();
                    continue;
                }
                if (columns[0].IndexOf('.') >= 0) continue;
                string form = columns[1].Replace('\u2019', '\'');
                string lower = form.ToLowerInvariant();
                if (surface != null)
                {
                    parts.Add(lower);
                    if (int.Parse(columns[0], CultureInfo.InvariantCulture) == last)
                    {
                        Dictionary<string, int> counts;
                        if (!split.TryGetValue(surface, out counts)) split[surface] = counts = new Dictionary<string, int>(StringComparer.Ordinal);
                        string words = string.Join(" ", parts);
                        int count;
                        counts.TryGetValue(words, out count);
                        counts[words] = count + 1;
                        surface = null;
                    }
                    continue;
                }
                int seen;
                whole.TryGetValue(lower, out seen);
                whole[lower] = seen + 1;
                int apostrophe = lower.IndexOf('\'');
                if (apostrophe > 0 && apostrophe == lower.Length - 1 && lower.Length <= 4) Before.Add(lower);
                if (lower.Length <= 4 && (apostrophe == 0 || lower == "n't")) After.Add(lower);
            }
        }
        // A written token is cut only when it stands for several words more often than for itself
        foreach (KeyValuePair<string, Dictionary<string, int>> entry in split)
        {
            KeyValuePair<string, int> best = entry.Value.OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key, StringComparer.Ordinal).First();
            int alone;
            whole.TryGetValue(entry.Key, out alone);
            if (best.Value > alone) Contractions[entry.Key] = best.Key;
        }
    }

    static readonly System.Text.RegularExpressions.Regex Pieces = new System.Text.RegularExpressions.Regex(
        @"(?:[A-Za-z]:\\|\\\\)[^\s,;?!""]*|[\p{L}\p{M}\p{N}](?:[\p{L}\p{M}\p{N}'\-_.]*[\p{L}\p{M}\p{N}'])?|[^\s]",
        System.Text.RegularExpressions.RegexOptions.CultureInvariant);

    // The words of a written sentence, cut as the treebanks cut them
    public string[] Tokenize(string text)
    {
        List<string> words = new List<string>();
        foreach (System.Text.RegularExpressions.Match match in Pieces.Matches((text ?? "").Replace('\u2019', '\'')))
        {
            string token = match.Value;
            List<string> tail = new List<string>();
            // Cut before: "l'avion", "qu'il"
            int apostrophe = token.IndexOf('\'');
            if (apostrophe > 0 && apostrophe < token.Length - 1 && Before.Contains(token.Substring(0, apostrophe + 1).ToLowerInvariant()))
            {
                words.Add(token.Substring(0, apostrophe + 1));
                token = token.Substring(apostrophe + 1);
            }
            // Cut after: "it's", "don't"
            foreach (string piece in After)
            {
                if (token.Length > piece.Length && token.EndsWith(piece, StringComparison.OrdinalIgnoreCase))
                {
                    tail.Add(token.Substring(token.Length - piece.Length));
                    token = token.Substring(0, token.Length - piece.Length);
                    break;
                }
            }
            string expansion;
            if (Contractions.TryGetValue(token.ToLowerInvariant(), out expansion)) words.AddRange(expansion.Split(' '));
            else if (token.Length > 0) words.Add(token);
            words.AddRange(tail);
        }
        return words.ToArray();
    }

    // Reads a written sentence
    public LambekFormReading[] ReadText(string text) { return Read(Tokenize(text)); }

    static string Lower(string word) { return word.ToLowerInvariant(); }

    static string Shape(string word)
    {
        StringBuilder shape = new StringBuilder();
        char last = '\0';
        foreach (char c in word)
        {
            char kind = char.IsUpper(c) ? 'X' : char.IsLower(c) ? 'x' : char.IsDigit(c) ? 'd' : c;
            if (kind != last) shape.Append(kind);
            last = kind;
            if (shape.Length >= 5) break;
        }
        return shape.ToString();
    }

    static string Suffix(string word, int length) { return word.Length > length ? word.Substring(word.Length - length) : word; }
    static string Prefix(string word, int length) { return word.Length > length ? word.Substring(0, length) : word; }

    // What the tagger sees of word i: the word, its ends, its shape, its neighbours, and the tags said before it
    public static List<string> TagFeatures(string[] forms, int i, string previous, string beforePrevious)
    {
        string word = Lower(forms[i]);
        List<string> features = new List<string>(24) { "b", "w=" + word, "sh=" + Shape(forms[i]) };
        for (int n = 1; n <= 4; n++) features.Add("s" + n + "=" + Suffix(word, n));
        for (int n = 1; n <= 3; n++) features.Add("p" + n + "=" + Prefix(word, n));
        if (i == 0) features.Add("first");
        if (forms[i].IndexOf('-') >= 0) features.Add("hyphen");
        string left = i > 0 ? Lower(forms[i - 1]) : "<s>";
        string right = i + 1 < forms.Length ? Lower(forms[i + 1]) : "</s>";
        string left2 = i > 1 ? Lower(forms[i - 2]) : "<s>";
        string right2 = i + 2 < forms.Length ? Lower(forms[i + 2]) : "</s>";
        features.Add("w-1=" + left);
        features.Add("w+1=" + right);
        features.Add("w-2=" + left2);
        features.Add("w+2=" + right2);
        features.Add("s3-1=" + Suffix(left, 3));
        features.Add("s3+1=" + Suffix(right, 3));
        features.Add("t-1=" + previous);
        features.Add("t-2t-1=" + beforePrevious + "^" + previous);
        features.Add("t-1w=" + previous + "^" + word);
        features.Add("w-1w=" + left + "^" + word);
        return features;
    }

    // What the lemmatiser sees: the word, its ends, and the tag the tagger gave it
    public static List<string> LemmaFeatures(string form, string tag)
    {
        string word = Lower(form);
        string upos = tag.Split('|')[0];
        List<string> features = new List<string>(16) { "b", "w=" + word, "t=" + tag, "u=" + upos, "sh=" + Shape(form) };
        for (int n = 1; n <= 5; n++)
        {
            string suffix = Suffix(word, n);
            features.Add("s" + n + "=" + suffix);
            features.Add("u^s" + n + "=" + upos + "^" + suffix);
        }
        for (int n = 1; n <= 3; n++) features.Add("p" + n + "=" + Prefix(word, n));
        features.Add("t^w=" + tag + "^" + word);
        return features;
    }

    // Learns from the sentences, in their order, Passes times: the tagger reads each sentence left to right with its
    // own guesses as the tags before (as it will when reading), the lemmatiser with the true tags
    public void Train(List<LambekTreebankWord[]> sentences, Action<int> progress)
    {
        foreach (LambekTreebankWord[] sentence in sentences) foreach (LambekTreebankWord word in sentence) Vocabulary.Add(word.Form.ToLowerInvariant());
        for (int pass = 0; pass < Passes; pass++)
        {
            foreach (LambekTreebankWord[] sentence in sentences)
            {
                string[] forms = sentence.Select(word => word.Form).ToArray();
                string previous = "<s>", beforePrevious = "<s>";
                for (int i = 0; i < sentence.Length; i++)
                {
                    int truth = Tagger.ClassOf(sentence[i].Tag, true);
                    int guess = Tagger.Learn(TagFeatures(forms, i, previous, beforePrevious), truth, null);
                    beforePrevious = previous;
                    previous = guess >= 0 ? Tagger.Classes[guess] : sentence[i].Tag;

                    string rule = LambekFormRule.Of(sentence[i].Form, sentence[i].Lemma);
                    int ruleClass = Lemmatiser.ClassOf(rule, true);
                    string form = sentence[i].Form;
                    Lemmatiser.Learn(LemmaFeatures(form, sentence[i].Tag), ruleClass, c => LambekFormRule.Apply(Lemmatiser.Classes[c], form) != null);
                }
            }
            if (progress != null) progress(pass + 1);
        }
        Tagger.Average();
        Lemmatiser.Average();
    }

    // Reads the words of one sentence
    public LambekFormReading[] Read(string[] forms)
    {
        LambekFormReading[] readings = new LambekFormReading[forms.Length];
        string previous = "<s>", beforePrevious = "<s>";
        for (int i = 0; i < forms.Length; i++)
        {
            int tagClass = Tagger.Best(TagFeatures(forms, i, previous, beforePrevious), null);
            string tag = tagClass >= 0 ? Tagger.Classes[tagClass] : "X|_";
            beforePrevious = previous;
            previous = tag;
            string form = forms[i];
            int ruleClass = Lemmatiser.Best(LemmaFeatures(form, tag), c => LambekFormRule.Apply(Lemmatiser.Classes[c], form) != null);
            string rule = ruleClass >= 0 ? Lemmatiser.Classes[ruleClass] : "l|0||0|";
            int bar = tag.IndexOf('|');
            readings[i] = new LambekFormReading
            {
                Form = form,
                Rule = rule,
                Lemma = LambekFormRule.Apply(rule, form) ?? form.ToLowerInvariant(),
                Upos = bar >= 0 ? tag.Substring(0, bar) : tag,
                Feats = bar >= 0 ? tag.Substring(bar + 1) : "_"
            };
        }
        return readings;
    }

    public void Save(string path)
    {
        using (FileStream file = File.Create(path))
        using (GZipStream zip = new GZipStream(file, CompressionLevel.Optimal))
        using (BinaryWriter writer = new BinaryWriter(zip, Encoding.UTF8))
        {
            writer.Write(Format);
            writer.Write(Language ?? "");
            writer.Write(Contractions.Count);
            foreach (KeyValuePair<string, string> pair in Contractions) { writer.Write(pair.Key); writer.Write(pair.Value); }
            writer.Write(Before.Count);
            foreach (string piece in Before) writer.Write(piece);
            writer.Write(After.Count);
            foreach (string piece in After) writer.Write(piece);
            writer.Write(Vocabulary.Count);
            foreach (string word in Vocabulary) writer.Write(word);
            Tagger.Write(writer);
            Lemmatiser.Write(writer);
        }
    }

    public static LambekForms Load(string path)
    {
        using (FileStream file = File.OpenRead(path))
        using (GZipStream zip = new GZipStream(file, CompressionMode.Decompress))
        using (BinaryReader reader = new BinaryReader(zip, Encoding.UTF8))
        {
            string format = reader.ReadString();
            if (format != Format) throw new InvalidDataException("Not a forms model of Lambek: " + format);
            LambekForms forms = new LambekForms { Language = reader.ReadString() };
            int contractions = reader.ReadInt32();
            for (int i = 0; i < contractions; i++) forms.Contractions[reader.ReadString()] = reader.ReadString();
            int before = reader.ReadInt32();
            for (int i = 0; i < before; i++) forms.Before.Add(reader.ReadString());
            int after = reader.ReadInt32();
            for (int i = 0; i < after; i++) forms.After.Add(reader.ReadString());
            int vocabulary = reader.ReadInt32();
            for (int i = 0; i < vocabulary; i++) forms.Vocabulary.Add(reader.ReadString());
            forms.Tagger = LambekPerceptron.ReadFrom(reader);
            forms.Lemmatiser = LambekPerceptron.ReadFrom(reader);
            return forms;
        }
    }
}
