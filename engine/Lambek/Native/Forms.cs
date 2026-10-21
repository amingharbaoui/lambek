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

    // Why a class was chosen: the features that weigh most for it, with their weight (averaged over the steps, said
    // with two decimals, only to be read)
    public string[] Explain(IList<string> active, int @class, int top)
    {
        List<KeyValuePair<string, long>> parts = new List<KeyValuePair<string, long>>();
        foreach (string name in active.Distinct(StringComparer.Ordinal))
        {
            int feature = FeatureOf(name, false);
            int slot;
            if (feature < 0 || @class < 0 || !slots[feature].TryGetValue(@class, out slot)) continue;
            long value = averaged ? final[slot] : weights[slot];
            if (value > 0) parts.Add(new KeyValuePair<string, long>(name, value));
        }
        double scale = averaged && step > 0 ? step : 1;
        return parts.OrderByDescending(part => part.Value).ThenBy(part => part.Key, StringComparer.Ordinal).Take(top)
            .Select(part => part.Key + " (+" + (part.Value / scale).ToString("0.00", CultureInfo.InvariantCulture) + ")").ToArray();
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
        writer.Write(step);
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
        model.step = reader.ReadInt64();
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
    // For a word never seen: the part of speech its nearest rare words give, and whether it differs from the tagger's
    public string Second;
    public bool Doubt;
    // For a word never seen: the best tag of the tagger with another part of speech, for the grammar to weigh too
    public string Alternative;
    // A verb never seen whose lemma was found by analogy with the verbs seen, not by its rule
    public bool Analogous;
}

// The model of forms of one language: a tagger (part of speech and features) and a lemmatiser (the rule of form)
public class LambekForms
{
    public string Language;
    public LambekPerceptron Tagger = new LambekPerceptron();
    public LambekPerceptron Lemmatiser = new LambekPerceptron();
    public int Passes = 10;
    public const string Format = "lambek-forms-7";

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

    // The second reader of the words never seen: the rare words of the treebanks (seen at most twice), each with the
    // words around it and its part of speech, and the most common words, the only neighbours it looks at
    public readonly SortedSet<string> Common = new SortedSet<string>(StringComparer.Ordinal);

    // The tags each word was seen with, the most frequent first: a word may be read otherwise than the tagger read it
    // ("lives": a verb or the plural of "life"), and the grammar of the sentence then chooses
    public readonly SortedDictionary<string, string[]> Tags = new SortedDictionary<string, string[]>(StringComparer.Ordinal);

    // The lemma of a form read with a tag
    public string LemmaFor(string form, string tag)
    {
        int rule = Rule(form, tag);
        return VerbLemma(form, tag, rule >= 0 ? LambekFormRule.Apply(Lemmatiser.Classes[rule], form) : form.ToLowerInvariant());
    }

    // The lemma of a verb: as its rule gives it, unless the verb was never seen and its rule leads to a lemma never seen
    string VerbLemma(string form, string tag, string lemma)
    {
        if (Lemmas.Count == 0 || !(tag == "VERB" || tag.StartsWith("VERB|", StringComparison.Ordinal))) return lemma;
        if (Knows(form) || Lemmas.Contains(lemma.ToLowerInvariant())) return lemma;
        return Analogy(form) ?? lemma;
    }

    // The lemmas seen when learning, in small letters, and the verbs seen with their lemma. A verb never seen whose
    // rule leads to a lemma never seen ("dors": "dortir", the rule of "sors") takes the lemma of the verb seen that
    // begins as it does ("dort", "dorment": dormir), as a child conjugates by analogy
    public readonly SortedSet<string> Lemmas = new SortedSet<string>(StringComparer.Ordinal);
    public readonly SortedDictionary<string, string> Verbs = new SortedDictionary<string, string>(StringComparer.Ordinal);
    string[] verbForms;

    // The paradigms: the forms each lemma was seen with, for its part of speech and its features, and how often
    // ("VERB\tprendre\tMood=Ind|Number=Plur|Person=1|Tense=Pres|VerbForm=Fin": "prenons"). With them Lambek says a
    // word as well as it reads it: the form of a verb for the one spoken to, an adjective that agrees. The verbs that
    // help the others (AUX) are verbs here, as "etre" is one verb whether it helps or not
    public readonly SortedDictionary<string, SortedDictionary<string, int>> Paradigms = new SortedDictionary<string, SortedDictionary<string, int>>(StringComparer.Ordinal);

    public int Rule(string form, string tag)
    {
        return Lemmatiser.Best(LemmaFeatures(form, tag), c => LambekFormRule.Apply(Lemmatiser.Classes[c], form) != null);
    }

    // The lemma of a verb never seen, by analogy with the verbs seen; null when none begins as it does
    public string Analogy(string form)
    {
        string lower = form.ToLowerInvariant();
        if (verbForms == null) verbForms = Verbs.Keys.ToArray();
        int need = Math.Max(3, lower.Length - 3);
        if (lower.Length < need) return null;
        // The verbs seen that share the first letters, found by binary search in their sorted forms
        string stem = lower.Substring(0, need);
        int at = Array.BinarySearch(verbForms, stem, StringComparer.Ordinal);
        if (at < 0) at = ~at;
        string best = null;
        int bestLength = -1;
        for (int i = at; i < verbForms.Length && verbForms[i].StartsWith(stem, StringComparison.Ordinal); i++)
        {
            int length = 0;
            while (length < lower.Length && length < verbForms[i].Length && lower[length] == verbForms[i][length]) length++;
            if (length > bestLength) { bestLength = length; best = verbForms[i]; }
        }
        return best == null ? null : Verbs[best];
    }

    // The lemmas of the verbs seen whose forms share the longest beginning with a word (four letters at least, or the
    // whole word but its last three): "courons": courir, courber...
    public string[] Beginning(string form)
    {
        string lower = form.ToLowerInvariant();
        if (verbForms == null) verbForms = Verbs.Keys.ToArray();
        int need = Math.Max(3, lower.Length - 3);
        if (lower.Length < need) return new string[0];
        string stem = lower.Substring(0, need);
        int at = Array.BinarySearch(verbForms, stem, StringComparer.Ordinal);
        if (at < 0) at = ~at;
        int best = -1;
        SortedSet<string> lemmas = new SortedSet<string>(StringComparer.Ordinal);
        for (int i = at; i < verbForms.Length && verbForms[i].StartsWith(stem, StringComparison.Ordinal); i++)
        {
            int length = 0;
            while (length < lower.Length && length < verbForms[i].Length && lower[length] == verbForms[i][length]) length++;
            if (length > best) { best = length; lemmas.Clear(); }
            if (length == best) lemmas.Add(Verbs[verbForms[i]].ToLowerInvariant());
        }
        return lemmas.ToArray();
    }

    public readonly List<string[]> Rare = new List<string[]>();
    public int Neighbours = 10;
    public double Width = 0.5;
    LambekNearest second;

    // What the second reader sees of a word: its ends, its shape, its length, and its neighbours when they are common
    public List<string> RareFeatures(string form, string left, string right, bool first)
    {
        string lower = form.ToLowerInvariant();
        List<string> features = new List<string>(16);
        for (int n = 1; n <= 4; n++) if (lower.Length >= n) features.Add("s" + n + "=" + lower.Substring(lower.Length - n));
        for (int n = 1; n <= 3; n++) if (lower.Length >= n) features.Add("p" + n + "=" + lower.Substring(0, n));
        if (form.Length > 0 && char.IsUpper(form[0])) features.Add("cap");
        if (form.Length > 1 && form.All(char.IsUpper)) features.Add("allcap");
        if (form.Any(char.IsDigit)) features.Add("digit");
        if (form.IndexOf('-') >= 0) features.Add("hyphen");
        if (first) features.Add("first");
        features.Add("len=" + Math.Min(lower.Length, 12).ToString(CultureInfo.InvariantCulture));
        string l = left.ToLowerInvariant();
        string r = right.ToLowerInvariant();
        features.Add("w-1=" + (l == "<s>" || Common.Contains(l) ? l : "*"));
        features.Add("w+1=" + (r == "</s>" || Common.Contains(r) ? r : "*"));
        return features;
    }

    LambekNearest Second
    {
        get
        {
            if (second != null) return second;
            LambekNearest memory = new LambekNearest { Supervised = true };
            foreach (string[] rare in Rare) memory.Add(RareFeatures(rare[0], rare[1], rare[2], rare[1] == "<s>").ToArray(), rare[3], rare[0]);
            second = memory;
            return second;
        }
    }

    void Remember(List<LambekTreebankWord[]> sentences)
    {
        Dictionary<string, int> counts = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (LambekTreebankWord[] sentence in sentences)
        {
            foreach (LambekTreebankWord word in sentence)
            {
                string lower = word.Form.ToLowerInvariant();
                int count;
                counts.TryGetValue(lower, out count);
                counts[lower] = count + 1;
            }
        }
        foreach (KeyValuePair<string, int> pair in counts.OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key, StringComparer.Ordinal).Take(200)) Common.Add(pair.Key);
        Dictionary<string, Dictionary<string, int>> tags = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
        foreach (LambekTreebankWord[] sentence in sentences)
        {
            foreach (LambekTreebankWord word in sentence)
            {
                string lower = word.Form.ToLowerInvariant();
                Dictionary<string, int> seen;
                if (!tags.TryGetValue(lower, out seen)) tags[lower] = seen = new Dictionary<string, int>(StringComparer.Ordinal);
                int count;
                seen.TryGetValue(word.Tag, out count);
                seen[word.Tag] = count + 1;
            }
        }
        // Only the tags a word really has: seen twice at least, and at least one time in twenty (a slip of the
        // annotators, "it" read once as "if", is no reading of the word)
        // The verbs seen, each with its most frequent lemma
        Dictionary<string, Dictionary<string, int>> verbs = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
        foreach (LambekTreebankWord[] sentence in sentences)
        {
            foreach (LambekTreebankWord word in sentence)
            {
                if (word.Upos != "VERB" || string.IsNullOrEmpty(word.Lemma) || word.Lemma == "_") continue;
                string lower = word.Form.ToLowerInvariant();
                Dictionary<string, int> seen;
                if (!verbs.TryGetValue(lower, out seen)) verbs[lower] = seen = new Dictionary<string, int>(StringComparer.Ordinal);
                int count;
                seen.TryGetValue(word.Lemma, out count);
                seen[word.Lemma] = count + 1;
            }
        }
        foreach (KeyValuePair<string, Dictionary<string, int>> pair in verbs)
        {
            Verbs[pair.Key] = pair.Value.OrderByDescending(lemma => lemma.Value).ThenBy(lemma => lemma.Key, StringComparer.Ordinal).First().Key;
        }
        foreach (KeyValuePair<string, Dictionary<string, int>> pair in tags)
        {
            int total = pair.Value.Values.Sum();
            Tags[pair.Key] = pair.Value.Where(tag => tag.Value >= 2 && tag.Value * 20 >= total)
                .OrderByDescending(tag => tag.Value).ThenBy(tag => tag.Key, StringComparer.Ordinal).Select(tag => tag.Key).ToArray();
        }
        LearnParadigms(sentences);
        foreach (LambekTreebankWord[] sentence in sentences)
        {
            for (int i = 0; i < sentence.Length; i++)
            {
                if (counts[sentence[i].Form.ToLowerInvariant()] > 2) continue;
                Rare.Add(new[] { sentence[i].Form, i > 0 ? sentence[i - 1].Form : "<s>", i + 1 < sentence.Length ? sentence[i + 1].Form : "</s>", sentence[i].Upos });
            }
        }
    }

    // The forms each lemma was seen with
    public void LearnParadigms(List<LambekTreebankWord[]> sentences)
    {
        Paradigms.Clear();
        foreach (LambekTreebankWord[] sentence in sentences)
        {
            foreach (LambekTreebankWord word in sentence)
            {
                string key = ParadigmKey(word.Upos, word.Lemma, word.Feats);
                if (key == null) continue;
                SortedDictionary<string, int> forms;
                if (!Paradigms.TryGetValue(key, out forms)) Paradigms[key] = forms = new SortedDictionary<string, int>(StringComparer.Ordinal);
                string lower = word.Form.ToLowerInvariant();
                int count;
                forms.TryGetValue(lower, out count);
                forms[lower] = count + 1;
            }
        }
        speaking = null;
    }

    // The key of a paradigm; null for what has no forms to say (punctuation, symbols, words of no part of speech)
    public static string ParadigmKey(string upos, string lemma, string feats)
    {
        if (string.IsNullOrEmpty(lemma) || lemma == "_" || upos == "PUNCT" || upos == "SYM" || upos == "X") return null;
        // (a slip of the hand, "énérgie", or a shortened word, "cts", is no form to say)
        if (feats != null && (feats.Contains("Typo=Yes") || feats.Contains("Abbr=Yes"))) return null;
        return (upos == "AUX" ? "VERB" : upos) + "\t" + lemma.ToLowerInvariant() + "\t" + (string.IsNullOrEmpty(feats) ? "_" : feats);
    }

    static HashSet<string> FeatureSet(string feats)
    {
        HashSet<string> set = new HashSet<string>(StringComparer.Ordinal);
        if (string.IsNullOrEmpty(feats) || feats == "_") return set;
        foreach (string feature in feats.Split('|')) if (feature.Length > 0) set.Add(feature);
        return set;
    }

    // Built once, from the paradigms: the features each part of speech was seen with, the lemma written with its
    // accents for each lemma without them ("etre": être), and for each part of speech and features the lemmas seen,
    // written backwards and sorted, each with the rule that leads from it to its most frequent form
    class Speaking
    {
        public Dictionary<string, List<KeyValuePair<string, HashSet<string>>>> Features = new Dictionary<string, List<KeyValuePair<string, HashSet<string>>>>(StringComparer.Ordinal);
        public Dictionary<string, string> Accented = new Dictionary<string, string>(StringComparer.Ordinal);
        public Dictionary<string, string[]> Backwards = new Dictionary<string, string[]>(StringComparer.Ordinal);
        public Dictionary<string, string[]> Rules = new Dictionary<string, string[]>(StringComparer.Ordinal);
        public Dictionary<string, int[]> Counts = new Dictionary<string, int[]>(StringComparer.Ordinal);
        // Each lemma seen, with the change of ending of each of its forms seen, by features
        public Dictionary<string, Dictionary<string, string>> Cells = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
    }
    Speaking speaking;

    static string Backward(string text)
    {
        char[] letters = text.ToCharArray();
        Array.Reverse(letters);
        return new string(letters);
    }

    Speaking Speak()
    {
        if (speaking != null) return speaking;
        Speaking built = new Speaking();
        Dictionary<string, HashSet<string>> featuresSeen = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
        Dictionary<string, Dictionary<string, int>> accents = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
        Dictionary<string, List<string[]>> entries = new Dictionary<string, List<string[]>>(StringComparer.Ordinal);
        foreach (KeyValuePair<string, SortedDictionary<string, int>> paradigm in Paradigms)
        {
            string[] parts = paradigm.Key.Split('\t');
            HashSet<string> seen;
            if (!featuresSeen.TryGetValue(parts[0], out seen)) featuresSeen[parts[0]] = seen = new HashSet<string>(StringComparer.Ordinal);
            seen.Add(parts[2]);
            int total = paradigm.Value.Values.Sum();
            string plain = LambekDictionary.Normalize(parts[1]);
            Dictionary<string, int> written;
            if (!accents.TryGetValue(plain, out written)) accents[plain] = written = new Dictionary<string, int>(StringComparer.Ordinal);
            int count;
            written.TryGetValue(parts[1], out count);
            written[parts[1]] = count + total;
            string form = paradigm.Value.OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key, StringComparer.Ordinal).First().Key;
            string slot = parts[0] + "\t" + parts[2];
            List<string[]> list;
            if (!entries.TryGetValue(slot, out list)) entries[slot] = list = new List<string[]>();
            string ending = Ending(parts[1], form);
            list.Add(new[] { Backward(parts[1]), ending, total.ToString(CultureInfo.InvariantCulture) });
            Dictionary<string, string> cells;
            if (!built.Cells.TryGetValue(parts[0] + "\t" + parts[1], out cells)) built.Cells[parts[0] + "\t" + parts[1]] = cells = new Dictionary<string, string>(StringComparer.Ordinal);
            cells[parts[2]] = ending;
        }
        foreach (KeyValuePair<string, HashSet<string>> pair in featuresSeen)
        {
            built.Features[pair.Key] = pair.Value.OrderBy(feats => feats, StringComparer.Ordinal).Select(feats => new KeyValuePair<string, HashSet<string>>(feats, FeatureSet(feats))).ToList();
        }
        foreach (KeyValuePair<string, Dictionary<string, int>> pair in accents)
        {
            built.Accented[pair.Key] = pair.Value.OrderByDescending(item => item.Value).ThenBy(item => item.Key, StringComparer.Ordinal).First().Key;
        }
        foreach (KeyValuePair<string, List<string[]>> pair in entries)
        {
            string[][] sorted = pair.Value.OrderBy(entry => entry[0], StringComparer.Ordinal).ToArray();
            built.Backwards[pair.Key] = sorted.Select(entry => entry[0]).ToArray();
            built.Rules[pair.Key] = sorted.Select(entry => entry[1]).ToArray();
            built.Counts[pair.Key] = sorted.Select(entry => int.Parse(entry[2], CultureInfo.InvariantCulture)).ToArray();
        }
        speaking = built;
        return speaking;
    }

    // The lemma as the paradigms write it: "etre" is "être" when only "être" was seen
    public string Written(string lemma)
    {
        string lower = (lemma ?? "").ToLowerInvariant();
        string plain = LambekDictionary.Normalize(lower);
        // (written with its accents already: as it is)
        if (lower != plain) return lower;
        string accented;
        if (Speak().Accented.TryGetValue(plain, out accented)) return accented;
        return lower;
    }

    // The forms of a lemma with the features wanted (all of them; the form may have more), the most frequent first:
    // the forms seen with this very lemma when it was seen so, otherwise the form the lemmas that end most like it
    // take, by the rule most of them follow ("prendre", 2nd person plural, never seen: "comprendre" gives
    // "comprenez", so "prenez"), as a child conjugates a verb it never heard by the ones it knows. Nothing when no
    // lemma seen so ends as it does
    public string[] Inflect(string lemma, string upos, string wanted)
    {
        if (string.IsNullOrEmpty(lemma) || string.IsNullOrEmpty(upos)) return new string[0];
        if (upos == "AUX") upos = "VERB";
        Speaking table = Speak();
        List<KeyValuePair<string, HashSet<string>>> seen;
        if (!table.Features.TryGetValue(upos, out seen)) return new string[0];
        string written = Written(lemma);
        HashSet<string> want = FeatureSet(wanted);
        Dictionary<string, string> own;
        table.Cells.TryGetValue(upos + "\t" + written, out own);
        // The features that have every one wanted, the fewest others that change a form first (a voice, a slip of
        // the hand, change none): each group of them is tried in full before the next
        foreach (IGrouping<int, KeyValuePair<string, HashSet<string>>> group in seen.Where(feats => want.IsSubsetOf(feats.Value))
            .GroupBy(feats => feats.Value.Count(feature => !want.Contains(feature) && Inflectional(feature))).OrderBy(group => group.Key))
        {
            string[] said = Attested(upos, written, group);
            if (said.Length == 0 && own != null) said = Proportional(table, upos, written, own, group);
            if (said.Length == 0 && own != null) said = Bridged(table, upos, written, own, group);
            if (said.Length == 0) said = BySuffix(table, upos, written, group);
            if (said.Length > 0) return said;
        }
        // A noun or an adjective that nothing ends like ("CGI", "junior") is said as its lemma in the singular
        if ((upos == "NOUN" || upos == "ADJ" || upos == "PROPN") && !want.Contains("Number=Plur")) return new[] { written };
        return new string[0];
    }

    // The features that change how a word is written
    static bool Inflectional(string feature)
    {
        int equal = feature.IndexOf('=');
        string name = equal > 0 ? feature.Substring(0, equal) : feature;
        return name == "Gender" || name == "Number" || name == "Person" || name == "Mood" || name == "Tense" || name == "VerbForm";
    }

    static string[] Ranked(Dictionary<string, long> votes)
    {
        return votes.OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key, StringComparer.Ordinal).Select(pair => pair.Key).ToArray();
    }

    // The forms seen with this very lemma so
    string[] Attested(string upos, string written, IEnumerable<KeyValuePair<string, HashSet<string>>> group)
    {
        Dictionary<string, long> found = new Dictionary<string, long>(StringComparer.Ordinal);
        foreach (KeyValuePair<string, HashSet<string>> feats in group)
        {
            SortedDictionary<string, int> forms;
            if (!Paradigms.TryGetValue(upos + "\t" + written + "\t" + feats.Key, out forms)) continue;
            foreach (KeyValuePair<string, int> form in forms)
            {
                long count;
                found.TryGetValue(form.Key, out count);
                found[form.Key] = count + form.Value;
            }
        }
        return Ranked(found);
    }

    // The lemma was seen with other features: the lemmas that end like it, seen with the features wanted, and whose
    // forms seen with the same other features change as its own do ("dormir": "dort", "dorment", as "sortir": "sort",
    // "sortent"; never "finir": "finit", "finissent"), lend it their form: "sors", so "dors"
    string[] Proportional(Speaking table, string upos, string written, Dictionary<string, string> own, IEnumerable<KeyValuePair<string, HashSet<string>>> group)
    {
        string backward = Backward(written);
        for (int length = written.Length - 1; length >= 2; length--)
        {
            string end = backward.Substring(0, length);
            Dictionary<string, long> votes = new Dictionary<string, long>(StringComparer.Ordinal);
            foreach (KeyValuePair<string, HashSet<string>> feats in group)
            {
                string slot = upos + "\t" + feats.Key;
                string[] lemmas;
                if (!table.Backwards.TryGetValue(slot, out lemmas)) continue;
                for (int i = First(lemmas, end); i < lemmas.Length && lemmas[i].StartsWith(end, StringComparison.Ordinal); i++)
                {
                    Dictionary<string, string> other = table.Cells[upos + "\t" + Backward(lemmas[i])];
                    int agree = 0, disagree = 0;
                    foreach (KeyValuePair<string, string> cell in own)
                    {
                        // (a form that is the lemma itself, the infinitive, tells nothing of how a verb changes)
                        string change;
                        if (cell.Value == "\t" || !other.TryGetValue(cell.Key, out change)) continue;
                        if (Alike(change, cell.Value)) agree++; else disagree++;
                    }
                    if (agree == 0 || disagree > 0) continue;
                    string said = Shift(table.Rules[slot][i], written);
                    if (said == null) continue;
                    long vote;
                    votes.TryGetValue(said, out vote);
                    // (each lemma counts once, then how often it was seen: the many verbs, not the frequent one)
                    votes[said] = vote + 1000000L + table.Counts[slot][i];
                }
            }
            if (votes.Count > 0) return Ranked(votes);
        }
        return new string[0];
    }

    // A form of the lemma seen with other features is changed as the forms of the other lemmas, seen with both,
    // change from the one to the other ("reussissent" ends as "partent", and "partent" is "partez": "reussissez"),
    // by the way most trusted
    string[] Bridged(Speaking table, string upos, string written, Dictionary<string, string> own, IEnumerable<KeyValuePair<string, HashSet<string>>> group)
    {
        double trust = 0;
        Dictionary<string, long> best = null;
        foreach (KeyValuePair<string, string> cell in own.OrderBy(cell => cell.Key, StringComparer.Ordinal))
        {
            if (cell.Value == "\t") continue;
            string from = Change(cell.Value, written);
            if (from == null) continue;
            foreach (KeyValuePair<string, HashSet<string>> feats in group)
            {
                if (feats.Key == cell.Key) continue;
                Bridge bridge = Between(table, upos, cell.Key, feats.Key);
                if (bridge.Forms.Length < 3 || bridge.Trust < 0.5 || bridge.Trust <= trust) continue;
                Dictionary<string, long> votes = Vote(bridge, from, -1);
                if (votes.Count == 0) continue;
                trust = bridge.Trust;
                best = votes;
            }
        }
        return best == null ? new string[0] : Ranked(best);
    }

    // The lemmas seen with these features that share the longest ending with this one, and the endings they change:
    // the longest ending shared by a lemma whose change fits this one decides, the change of the most lemmas first
    string[] BySuffix(Speaking table, string upos, string written, IEnumerable<KeyValuePair<string, HashSet<string>>> group)
    {
        string backward = Backward(written);
        for (int length = written.Length; length >= 2; length--)
        {
            string end = backward.Substring(0, length);
            Dictionary<string, long> votes = new Dictionary<string, long>(StringComparer.Ordinal);
            foreach (KeyValuePair<string, HashSet<string>> feats in group)
            {
                string slot = upos + "\t" + feats.Key;
                string[] lemmas;
                if (!table.Backwards.TryGetValue(slot, out lemmas)) continue;
                for (int i = First(lemmas, end); i < lemmas.Length && lemmas[i].StartsWith(end, StringComparison.Ordinal); i++)
                {
                    string said = Change(table.Rules[slot][i], written);
                    if (said == null) continue;
                    long vote;
                    votes.TryGetValue(said, out vote);
                    votes[said] = vote + 1000000L + table.Counts[slot][i];
                }
            }
            if (votes.Count > 0) return Ranked(votes);
        }
        return new string[0];
    }

    // Every form of the paradigms, by its letters as written and without accents: the form, the part of speech, the
    // lemma and the features it had, the most frequent first
    Dictionary<string, List<string[]>> heard;
    string[][] heardBackward;
    string[] heardKeys;
    public Dictionary<string, List<string[]>> Heard()
    {
        if (heard != null) return heard;
        Dictionary<string, List<string[]>> built = new Dictionary<string, List<string[]>>(StringComparer.Ordinal);
        Dictionary<string[], int> counts = new Dictionary<string[], int>();
        List<string[]> backward = new List<string[]>();
        foreach (KeyValuePair<string, SortedDictionary<string, int>> paradigm in Paradigms)
        {
            string[] parts = paradigm.Key.Split('\t');
            foreach (KeyValuePair<string, int> form in paradigm.Value)
            {
                string[] reading = new[] { form.Key, parts[0], parts[1], parts[2] };
                counts[reading] = form.Value;
                foreach (string key in new[] { form.Key, LambekDictionary.Normalize(form.Key) }.Distinct())
                {
                    List<string[]> list;
                    if (!built.TryGetValue(key, out list)) built[key] = list = new List<string[]>();
                    list.Add(reading);
                }
                if (parts[0] == "VERB" || parts[0] == "NOUN" || parts[0] == "ADJ") backward.Add(new[] { Backward(form.Key), parts[0], parts[1], parts[2] });
            }
        }
        foreach (List<string[]> list in built.Values)
        {
            string[][] sorted = list.OrderByDescending(reading => counts[reading]).ThenBy(reading => string.Join("\t", reading), StringComparer.Ordinal).ToArray();
            list.Clear();
            list.AddRange(sorted);
        }
        heardBackward = backward.OrderBy(entry => entry[0], StringComparer.Ordinal).ThenBy(entry => string.Join("\t", entry), StringComparer.Ordinal).ToArray();
        heardKeys = heardBackward.Select(entry => entry[0]).ToArray();
        heard = built;
        return heard;
    }

    // What a word never seen may be, found by saying it: the forms seen that end as it does give each a lemma and its
    // features ("aboie" ends as "envoie": "aboyer", present, third person; as "voie": "aboir"), and only the readings
    // whose lemma, said again with these features, gives back the very word are kept ("aboir" would be "aboit").
    // A lemma already seen comes first ("dort": "dormir", known from "dorment", before "dortir" made from "sort"),
    // then the readings most of the forms lead to
    public LambekFormReading[] Analyze(string form)
    {
        string lower = (form ?? "").ToLowerInvariant();
        List<LambekFormReading> readings = new List<LambekFormReading>();
        if (lower.Length < 3 || Paradigms.Count == 0 || !lower.All(char.IsLetter)) return readings.ToArray();
        Heard();
        Dictionary<string, long> votes = new Dictionary<string, long>(StringComparer.Ordinal);
        List<string> verbFeatures = new List<string>();
        string backward = Backward(lower);
        // Each part of speech on its own: the many nouns in "-age" must not hide the verbs ("nage": "partage")
        foreach (string upos in new[] { "VERB", "NOUN", "ADJ" })
        {
            bool found = false;
            for (int length = lower.Length - 1; length >= 3 && !found; length--)
            {
                string end = backward.Substring(0, length);
                int tried = 0;
                for (int i = First(heardKeys, end); i < heardBackward.Length && heardBackward[i][0].StartsWith(end, StringComparison.Ordinal) && tried < 64; i++)
                {
                    string[] entry = heardBackward[i];
                    if (entry[1] != upos) continue;
                    string seen = Backward(entry[0]);
                    if (upos == "VERB" && !verbFeatures.Contains(entry[3])) verbFeatures.Add(entry[3]);
                    string lemma = Change(Ending(seen, entry[2]), lower);
                    if (lemma == null || lemma.Length < 2) continue;
                    tried++;
                    string[] said = Inflect(lemma, upos, entry[3]);
                    if (said.Length == 0 || said[0] != lower) continue;
                    string key = upos + "\t" + lemma + "\t" + entry[3];
                    long vote;
                    votes.TryGetValue(key, out vote);
                    votes[key] = vote + 1 + (Lemmas.Contains(lemma) ? 1000000L : 0);
                    found = true;
                }
            }
        }
        // The verbs seen that begin as this word does, when they say this word with features the endings suggest
        foreach (string known in Beginning(lower))
        {
            foreach (string feats in verbFeatures)
            {
                string[] said = Inflect(known, "VERB", feats);
                if (said.Length == 0 || said[0] != lower) continue;
                string key = "VERB\t" + known.ToLowerInvariant() + "\t" + feats;
                long vote;
                votes.TryGetValue(key, out vote);
                votes[key] = vote + 2000000L;
            }
        }
        foreach (KeyValuePair<string, long> vote in votes.OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key, StringComparer.Ordinal))
        {
            string[] parts = vote.Key.Split('\t');
            readings.Add(new LambekFormReading { Form = form, Lemma = parts[1], Upos = parts[0], Feats = parts[2], Rule = "analysis" });
        }
        return readings.ToArray();
    }

    // The change of ending from a lemma to its form, after the letters both begin with: "prendre", "prenez" is "dre"
    // off, "ez" on
    static string Ending(string lemma, string form)
    {
        int shared = Shared(lemma, form);
        return lemma.Substring(shared) + "\t" + form.Substring(shared);
    }

    // A change of ending made on another lemma; null when the lemma does not end as the change needs, or when
    // nothing of the lemma would be left
    static string Change(string rule, string lemma)
    {
        int tab = rule.IndexOf('\t');
        string off = rule.Substring(0, tab);
        if (off.Length >= lemma.Length || !lemma.EndsWith(off, StringComparison.Ordinal)) return null;
        return lemma.Substring(0, lemma.Length - off.Length) + rule.Substring(tab + 1);
    }

    // From the form of a lemma with some features to its form with others, as the lemmas seen with both change: the
    // forms of the others that share the longest ending with this one, each lemma counted once. How far this way can
    // be trusted is measured on the lemmas seen with both, each found again from all the others (the present plural
    // tells the second person plural well, "-ons": "-ez"; the third person plural less well, "viennent": "venez")
    class Bridge
    {
        public string[] Forms;
        public string[] Changes;
        public double Trust;
    }
    Dictionary<string, Bridge> bridges = new Dictionary<string, Bridge>(StringComparer.Ordinal);

    Bridge Between(Speaking table, string upos, string fromFeats, string toFeats)
    {
        string key = upos + "\t" + fromFeats + "\t" + toFeats;
        Bridge bridge;
        if (bridges.TryGetValue(key, out bridge)) return bridge;
        List<string[]> found = new List<string[]>();
        foreach (KeyValuePair<string, Dictionary<string, string>> lemma in table.Cells)
        {
            if (!lemma.Key.StartsWith(upos + "\t", StringComparison.Ordinal)) continue;
            string one, other;
            if (!lemma.Value.TryGetValue(fromFeats, out one) || !lemma.Value.TryGetValue(toFeats, out other)) continue;
            string name = lemma.Key.Substring(upos.Length + 1);
            string a = Change(one, name), b = Change(other, name);
            if (a == null || b == null) continue;
            found.Add(new[] { Backward(a), Ending(a, b) });
        }
        found.Sort((x, y) => string.CompareOrdinal(x[0], y[0]) != 0 ? string.CompareOrdinal(x[0], y[0]) : string.CompareOrdinal(x[1], y[1]));
        bridge = new Bridge { Forms = found.Select(item => item[0]).ToArray(), Changes = found.Select(item => item[1]).ToArray() };
        int right = 0;
        for (int i = 0; i < bridge.Forms.Length; i++)
        {
            string form = Backward(bridge.Forms[i]);
            Dictionary<string, long> votes = Vote(bridge, form, i);
            string said = votes.Count == 0 ? null : votes.OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key, StringComparer.Ordinal).First().Key;
            if (said != null && said == Change(bridge.Changes[i], form)) right++;
        }
        bridge.Trust = bridge.Forms.Length == 0 ? 0 : (double) right / bridge.Forms.Length;
        bridges[key] = bridge;
        return bridge;
    }

    static Dictionary<string, long> Vote(Bridge bridge, string form, int skip)
    {
        Dictionary<string, long> votes = new Dictionary<string, long>(StringComparer.Ordinal);
        string backward = Backward(form);
        for (int length = form.Length; length >= 2 && votes.Count == 0; length--)
        {
            string end = backward.Substring(0, length);
            for (int i = First(bridge.Forms, end); i < bridge.Forms.Length && bridge.Forms[i].StartsWith(end, StringComparison.Ordinal); i++)
            {
                if (i == skip) continue;
                string said = Change(bridge.Changes[i], form);
                if (said == null) continue;
                long vote;
                votes.TryGetValue(said, out vote);
                votes[said] = vote + 1;
            }
        }
        return votes;
    }

    // Two changes of ending that take off as many letters and put on the same ones
    static bool Alike(string a, string b)
    {
        int ta = a.IndexOf('\t'), tb = b.IndexOf('\t');
        return ta == tb && string.CompareOrdinal(a, ta + 1, b, tb + 1, Math.Max(a.Length - ta, b.Length - tb)) == 0;
    }

    // A change of ending made by its number of letters only: "sortir", "sors" (three off, "s" on) made on "dormir"
    static string Shift(string rule, string lemma)
    {
        int tab = rule.IndexOf('\t');
        if (tab >= lemma.Length) return null;
        return lemma.Substring(0, lemma.Length - tab) + rule.Substring(tab + 1);
    }

    // The first of the sorted words that comes at or after a beginning
    static int First(string[] sorted, string start)
    {
        int low = 0, high = sorted.Length;
        while (low < high)
        {
            int middle = (low + high) / 2;
            if (string.CompareOrdinal(sorted[middle], start) < 0) low = middle + 1;
            else high = middle;
        }
        return low;
    }

    static int Shared(string a, string b)
    {
        int length = 0;
        while (length < a.Length && length < b.Length && a[length] == b[length]) length++;
        return length;
    }

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

    // Why word i of the sentence was read as it was: what weighs most for its tag, then for its rule of form
    public string[] Why(string[] forms, int index, int top)
    {
        LambekFormReading[] readings = Read(forms);
        string previous = index > 0 ? readings[index - 1].Upos + "|" + readings[index - 1].Feats : "<s>";
        string beforePrevious = index > 1 ? readings[index - 2].Upos + "|" + readings[index - 2].Feats : "<s>";
        string tag = readings[index].Upos + "|" + readings[index].Feats;
        List<string> why = new List<string>();
        why.AddRange(Tagger.Explain(TagFeatures(forms, index, previous, beforePrevious), Tagger.ClassOf(tag, false), top).Select(part => "tag: " + part));
        why.AddRange(Lemmatiser.Explain(LemmaFeatures(forms[index], tag), Lemmatiser.ClassOf(readings[index].Rule, false), top).Select(part => "lemma: " + part));
        return why.ToArray();
    }

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
        foreach (LambekTreebankWord[] sentence in sentences)
        {
            foreach (LambekTreebankWord word in sentence)
            {
                Vocabulary.Add(word.Form.ToLowerInvariant());
                if (!string.IsNullOrEmpty(word.Lemma) && word.Lemma != "_") Lemmas.Add(word.Lemma.ToLowerInvariant());
            }
        }
        Remember(sentences);
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
            List<string> seen = TagFeatures(forms, i, previous, beforePrevious);
            int tagClass = Tagger.Best(seen, null);
            string tag = tagClass >= 0 ? Tagger.Classes[tagClass] : "X|_";
            string alternative = null;
            if (tagClass >= 0 && !Knows(forms[i]))
            {
                long[] scores = Tagger.Score(seen);
                string upos = tag.Substring(0, Math.Max(0, tag.IndexOf('|')));
                int other = -1;
                for (int c = 0; c < scores.Length; c++)
                {
                    string name = Tagger.Classes[c];
                    if (name.StartsWith(upos + "|", StringComparison.Ordinal)) continue;
                    if (other < 0 || scores[c] > scores[other]) other = c;
                }
                if (other >= 0) alternative = Tagger.Classes[other];
            }
            beforePrevious = previous;
            previous = tag;
            string form = forms[i];
            int ruleClass = Rule(form, tag);
            string rule = ruleClass >= 0 ? Lemmatiser.Classes[ruleClass] : "l|0||0|";
            int bar = tag.IndexOf('|');
            readings[i] = new LambekFormReading
            {
                Form = form,
                Rule = rule,
                Lemma = LambekFormRule.Apply(rule, form) ?? form.ToLowerInvariant(),
                Upos = bar >= 0 ? tag.Substring(0, bar) : tag,
                Feats = bar >= 0 ? tag.Substring(bar + 1) : "_",
                Alternative = alternative
            };
            string byRule = readings[i].Lemma;
            readings[i].Lemma = VerbLemma(form, tag, byRule);
            readings[i].Analogous = readings[i].Lemma != byRule;
            // A word never seen is read a second time, from the rare words it is nearest to: when the two readers
            // disagree, the word is in doubt, and both parts of speech are kept for the grammar to choose
            if (Rare.Count > 0 && !Knows(form))
            {
                double share;
                string[] near;
                string other = Second.Vote(RareFeatures(form, i > 0 ? forms[i - 1] : "<s>", i + 1 < forms.Length ? forms[i + 1] : "</s>", i == 0).ToArray(), Neighbours, Width, out share, out near);
                if (other != null)
                {
                    readings[i].Second = other;
                    readings[i].Doubt = other != readings[i].Upos;
                }
            }
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
            writer.Write(Lemmas.Count);
            foreach (string lemma in Lemmas) writer.Write(lemma);
            writer.Write(Verbs.Count);
            foreach (KeyValuePair<string, string> pair in Verbs) { writer.Write(pair.Key); writer.Write(pair.Value); }
            writer.Write(Common.Count);
            foreach (string word in Common) writer.Write(word);
            writer.Write(Tags.Count);
            foreach (KeyValuePair<string, string[]> pair in Tags)
            {
                writer.Write(pair.Key);
                writer.Write(pair.Value.Length);
                foreach (string tag in pair.Value) writer.Write(tag);
            }
            writer.Write(Rare.Count);
            foreach (string[] rare in Rare) foreach (string part in rare) writer.Write(part);
            writer.Write(Paradigms.Count);
            foreach (KeyValuePair<string, SortedDictionary<string, int>> paradigm in Paradigms)
            {
                writer.Write(paradigm.Key);
                writer.Write(paradigm.Value.Count);
                foreach (KeyValuePair<string, int> form in paradigm.Value) { writer.Write(form.Key); writer.Write(form.Value); }
            }
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
            int lemmas = reader.ReadInt32();
            for (int i = 0; i < lemmas; i++) forms.Lemmas.Add(reader.ReadString());
            int verbs = reader.ReadInt32();
            for (int i = 0; i < verbs; i++) forms.Verbs[reader.ReadString()] = reader.ReadString();
            int common = reader.ReadInt32();
            for (int i = 0; i < common; i++) forms.Common.Add(reader.ReadString());
            int tagged = reader.ReadInt32();
            for (int i = 0; i < tagged; i++)
            {
                string word = reader.ReadString();
                string[] list = new string[reader.ReadInt32()];
                for (int j = 0; j < list.Length; j++) list[j] = reader.ReadString();
                forms.Tags[word] = list;
            }
            int rare = reader.ReadInt32();
            for (int i = 0; i < rare; i++) forms.Rare.Add(new[] { reader.ReadString(), reader.ReadString(), reader.ReadString(), reader.ReadString() });
            int paradigms = reader.ReadInt32();
            for (int i = 0; i < paradigms; i++)
            {
                string key = reader.ReadString();
                SortedDictionary<string, int> list = new SortedDictionary<string, int>(StringComparer.Ordinal);
                int count = reader.ReadInt32();
                for (int j = 0; j < count; j++) list[reader.ReadString()] = reader.ReadInt32();
                forms.Paradigms[key] = list;
            }
            forms.Tagger = LambekPerceptron.ReadFrom(reader);
            forms.Lemmatiser = LambekPerceptron.ReadFrom(reader);
            return forms;
        }
    }
}

// The words of one sentence as the forms model read them, offered the way the dictionaries offer theirs (Lemmas): the
// readers of sentences ask a word what it may be, and get the lemma, the part of speech and the participle the model
// read in this very sentence, instead of every reading a dictionary lists for the word out of context. A word in
// doubt (never seen, and the two readers of the model disagree) gets both parts of speech, for the grammar to choose
public class LambekSentenceWords
{
    readonly Dictionary<string, List<LambekLemma>> words = new Dictionary<string, List<LambekLemma>>(StringComparer.Ordinal);
    public LambekFormReading[] Readings = new LambekFormReading[0];

    static string Pos(string upos)
    {
        switch (upos)
        {
            case "VERB": return "v";
            case "NOUN": return "n";
            case "PROPN": return "n";
            case "ADJ": return "a";
            case "ADV": return "r";
            case "DET": return "det";
            case "ADP": return "prep";
            default: return upos.ToLowerInvariant();
        }
    }

    void Add(string key, LambekLemma lemma)
    {
        List<LambekLemma> list;
        if (!words.TryGetValue(key, out list)) words[key] = list = new List<LambekLemma>();
        if (!list.Any(seen => seen.Lemma == lemma.Lemma && seen.Pos == lemma.Pos && seen.Tag == lemma.Tag)) list.Add(lemma);
    }

    void AddReading(string key, LambekFormReading reading, string upos)
    {
        AddReading(key, reading.Lemma, upos, reading.Feats);
    }

    void AddReading(string key, string shown, string upos, string feats)
    {
        string lemma = LambekDictionary.Normalize(shown);
        // A participle, as the dictionaries of Lambek mark it (K)
        string tag = feats != null && feats.Contains("VerbForm=Part") ? "K" : "";
        if (upos == "AUX")
        {
            // A verb that helps the others is also a verb ("est" in "mon frere est content")
            Add(key, new LambekLemma { Lemma = lemma, Shown = shown, Pos = "v", Tag = tag });
            Add(key, new LambekLemma { Lemma = lemma, Shown = shown, Pos = "aux", Tag = tag });
            return;
        }
        Add(key, new LambekLemma { Lemma = lemma, Shown = shown, Pos = Pos(upos), Tag = tag });
    }

    static string Key(string form)
    {
        return LambekDictionary.Normalize(form).Replace("'", "").Replace("’", "");
    }

    public static LambekSentenceWords Read(LambekForms model, string text)
    {
        return Read(model, text, null, null);
    }

    // With a dictionary, only as a last resort: a verb never seen, whose lemma the model could not find among the
    // lemmas it has seen ("dors"), takes the lemma the dictionary gives it
    public static LambekSentenceWords Read(LambekForms model, string text, ILambekWords dictionary, string language)
    {
        LambekSentenceWords sentence = new LambekSentenceWords();
        sentence.Readings = model.ReadText(text ?? "");
        foreach (LambekFormReading reading in sentence.Readings)
        {
            string key = Key(reading.Form);
            if (key.Length == 0) continue;
            if (dictionary != null && reading.Upos == "VERB" && !model.Knows(reading.Form) && (reading.Analogous || !model.Lemmas.Contains(reading.Lemma.ToLowerInvariant())))
            {
                LambekLemma verb = dictionary.Lemmas(reading.Form.ToLowerInvariant(), language).FirstOrDefault(found => found.Pos == "v");
                if (verb != null) reading.Lemma = string.IsNullOrEmpty(verb.Shown) ? verb.Lemma : verb.Shown;
            }
            sentence.AddReading(key, reading, reading.Upos);
            // (the second reading with its own lemma: "raining" read as a noun is "raining", as a verb "rain")
            // (a word never seen is never a verb that helps the others: those are few, and all seen)
            if (reading.Doubt && reading.Second != null && reading.Second != "AUX") sentence.AddReading(key, model.LemmaFor(reading.Form, reading.Second + "|_"), reading.Second, "_");
            // A word never seen may also be what the tagger read second
            if (reading.Alternative != null && !reading.Alternative.StartsWith("AUX|", StringComparison.Ordinal))
            {
                int cut = reading.Alternative.IndexOf('|');
                sentence.AddReading(key, model.LemmaFor(reading.Form, reading.Alternative), reading.Alternative.Substring(0, cut), reading.Alternative.Substring(cut + 1));
            }
            // Then the other parts of speech the word was seen with, after the one read here
            string[] seen;
            if (model.Tags.TryGetValue(reading.Form.ToLowerInvariant(), out seen))
            {
                HashSet<string> parts = new HashSet<string>(StringComparer.Ordinal) { reading.Upos };
                foreach (string other in seen)
                {
                    int bar = other.IndexOf('|');
                    string upos = bar >= 0 ? other.Substring(0, bar) : other;
                    if (upos == "X" || upos == "SYM" || upos == "PUNCT" || upos == "INTJ" || !parts.Add(upos)) continue;
                    sentence.AddReading(key, model.LemmaFor(reading.Form, other), upos, bar >= 0 ? other.Substring(bar + 1) : "_");
                }
            }
        }
        // A written token that stands for several words ("du": de le) may be any of them
        string plain = " " + string.Join(" ", System.Text.RegularExpressions.Regex.Split(LambekDictionary.Normalize(text ?? ""), @"[^\p{L}\p{N}']+")) + " ";
        foreach (KeyValuePair<string, string> contraction in model.Contractions)
        {
            string surface = Key(contraction.Key);
            if (surface.Length == 0 || plain.IndexOf(" " + LambekDictionary.Normalize(contraction.Key) + " ", StringComparison.Ordinal) < 0) continue;
            foreach (string part in contraction.Value.Split(' '))
            {
                List<LambekLemma> found;
                if (sentence.words.TryGetValue(Key(part), out found)) foreach (LambekLemma lemma in found.ToArray()) sentence.Add(surface, lemma);
            }
        }
        return sentence;
    }

    public LambekLemma[] Lemmas(string word, string language)
    {
        List<LambekLemma> found;
        if (word != null && words.TryGetValue(Key(word), out found)) return found.ToArray();
        return new LambekLemma[0];
    }
}
