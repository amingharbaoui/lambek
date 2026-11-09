using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

// A word of logic of a language, as written: one that says of how many things a sentence is ("all": every one,
// "some": at least one, "no": none), learned, never written by hand
public sealed class LambekLogicWord
{
    public string Kind;
    public string Word;
    // The sentences where the word was met with that kind on the other side, and all those where it was met
    public int Together;
    public int Seen;
}

// The words of logic of a language, learned from sentences translated from and to English. The English side says the
// kind: the treebank of English tags "all", "every", "each" PronType=Tot, "some" PronType=Ind, "no" PronType=Neg, and
// its model reads them so in context. A word of the other language is of that kind when its treebank saw it as a
// determiner or a pronoun, and it is met in at least `least` pairs with that kind on the English side, and with it in
// most of the pairs it is met in. Under a negation the English side says none for some: "I do not see anyone" is "no one".
// Counts only, in integers, every sentence in the order given: the same sentences give the same words on every machine
public static class LambekLogicWords
{
    public const string Format = "lambek-logic-1";

    public static string KindOf(string upos, string feats)
    {
        if (upos != "DET" && upos != "PRON") return null;
        foreach (string feature in (feats ?? "").Split('|'))
        {
            if (feature == "PronType=Tot") return "all";
            if (feature == "PronType=Ind") return "some";
            if (feature == "PronType=Neg") return "no";
        }
        return null;
    }

    public static List<LambekLogicWord> Learn(LambekForms english, LambekForms other, IList<string> englishSide, IList<string> otherSide, int least, int longest)
    {
        Dictionary<string, int> kinds = new Dictionary<string, int>(StringComparer.Ordinal);
        Dictionary<string, int> seen = new Dictionary<string, int>(StringComparer.Ordinal);
        Dictionary<string, int> together = new Dictionary<string, int>(StringComparer.Ordinal);
        int count = Math.Min(englishSide.Count, otherSide.Count);
        for (int i = 0; i < count; i++)
        {
            LambekFormReading[] first = english.ReadText(englishSide[i] ?? "");
            if (first.Length == 0 || first.Length > longest) continue;
            LambekFormReading[] second = other.ReadText(otherSide[i] ?? "");
            if (second.Length == 0 || second.Length > longest) continue;
            HashSet<string> found = new HashSet<string>(StringComparer.Ordinal);
            bool denied = first.Any(word => ("|" + (word.Feats ?? "") + "|").Contains("|Polarity=Neg|"));
            foreach (LambekFormReading word in first)
            {
                string kind = KindOf(word.Upos, word.Feats);
                // (and the pronoun that asks who: English, the side every pair is read by, tags it PronType=Int, as it
                // tags "what", and says it "who"; the word of the other side met with it asks who too)
                if (kind == null && word.Upos == "PRON" && ("|" + (word.Feats ?? "") + "|").Contains("|PronType=Int|") && string.Equals(word.Lemma, "who", StringComparison.OrdinalIgnoreCase)) kind = "who";
                // Not at least one is none: "I don't have anything" says what "non ho niente" says, and "not a",
                // what "kein" says ("a bee is not a bird": "eine Biene ist kein Vogel")
                if (denied && (kind == "some" || (word.Upos == "DET" && ("|" + (word.Feats ?? "") + "|").Contains("|Definite=Ind|")))) kind = "no";
                if (kind != null) found.Add(kind);
            }
            // (a word once a sentence, as written; one the treebank saw as a determiner or a pronoun, and anything else)
            HashSet<string> lemmas = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> determiners = new HashSet<string>(StringComparer.Ordinal);
            foreach (LambekFormReading word in second)
            {
                string form = (word.Form ?? "").ToLowerInvariant();
                if (form.Length == 0 || !form.Any(char.IsLetter)) continue;
                lemmas.Add(form);
                string[] tags;
                if (other.Tags.TryGetValue(form, out tags) && tags.Any(tag => tag.StartsWith("DET|", StringComparison.Ordinal) || tag.StartsWith("PRON|", StringComparison.Ordinal))) determiners.Add(form);
            }
            foreach (string kind in found) { int n; kinds.TryGetValue(kind, out n); kinds[kind] = n + 1; }
            foreach (string lemma in lemmas)
            {
                int n; seen.TryGetValue(lemma, out n); seen[lemma] = n + 1;
                if (!determiners.Contains(lemma)) continue;
                foreach (string kind in found)
                {
                    string key = kind + "\t" + lemma;
                    together.TryGetValue(key, out n); together[key] = n + 1;
                }
            }
        }
        List<LambekLogicWord> words = new List<LambekLogicWord>();
        foreach (KeyValuePair<string, int> pair in together.OrderBy(p => p.Key, StringComparer.Ordinal))
        {
            string[] parts = pair.Key.Split('\t');
            int met = seen[parts[1]];
            // Met often enough with that kind, and with it in most of the pairs it is met in
            if (pair.Value < least || 2 * pair.Value <= met) continue;
            words.Add(new LambekLogicWord { Kind = parts[0], Word = parts[1], Together = pair.Value, Seen = met });
        }
        return words;
    }

    // The words of logic of the language of a treebank itself, as its annotators tagged them
    public static List<LambekLogicWord> FromTags(LambekForms model)
    {
        Dictionary<string, LambekLogicWord> words = new Dictionary<string, LambekLogicWord>(StringComparer.Ordinal);
        foreach (KeyValuePair<string, string[]> pair in model.Tags)
        {
            foreach (string tag in pair.Value)
            {
                int bar = tag.IndexOf('|');
                if (bar < 0) continue;
                string kind = KindOf(tag.Substring(0, bar), tag.Substring(bar + 1));
                if (kind == null) continue;
                string lemma = pair.Key.ToLowerInvariant();
                string key = kind + "\t" + lemma;
                if (!words.ContainsKey(key)) words[key] = new LambekLogicWord { Kind = kind, Word = lemma, Together = 0, Seen = 0 };
            }
        }
        return words.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => p.Value).ToList();
    }

    // The copulas of a language, the verbs that only join what is said to the one it is said of ("est" of "Tom est un
    // chat"): the lemmas its treebanks tag with the relation cop, those of at least a tenth of them all
    public static List<LambekLogicWord> Copulas(IEnumerable<string> paths)
    {
        Dictionary<string, int> counts = new Dictionary<string, int>(StringComparer.Ordinal);
        int total = 0;
        foreach (string path in paths)
        {
            foreach (string line in File.ReadLines(path))
            {
                if (line.Length == 0 || line[0] == '#') continue;
                string[] fields = line.Split('\t');
                if (fields.Length < 8 || fields[7] != "cop") continue;
                string lemma = fields[2].ToLowerInvariant();
                int n; counts.TryGetValue(lemma, out n); counts[lemma] = n + 1;
                total++;
            }
        }
        return counts.Where(p => 10 * p.Value >= total).OrderBy(p => p.Key, StringComparer.Ordinal)
            .Select(p => new LambekLogicWord { Kind = "copula", Word = p.Key, Together = p.Value, Seen = total }).ToList();
    }

    // The article a negation puts before what is done to ("n'a pas de poils"): among the indefinite articles of objects
    // (DET, Definite=Ind, its word the obj of the clause), the one at least 4 times more often after a word tagged
    // Polarity=Neg than in sentences with none, seen there at least `least` times; and the first letters before which
    // it is written cut ("d'oiseaux"), those more often after its cut form than after it. Nothing for a language whose
    // negation keeps its articles ("does not have a tail")
    public static List<LambekLogicWord> Negated(IEnumerable<string> paths, int least)
    {
        Dictionary<string, int> denied = new Dictionary<string, int>(StringComparer.Ordinal);
        Dictionary<string, int> plain = new Dictionary<string, int>(StringComparer.Ordinal);
        int deniedTotal = 0, plainTotal = 0;
        List<string[][]> sentences = new List<string[][]>();
        foreach (string path in paths)
        {
            List<string[]> words = new List<string[]>();
            foreach (string line in File.ReadLines(path).Concat(new[] { "" }))
            {
                if (line.Length == 0)
                {
                    if (words.Count > 0) sentences.Add(words.ToArray());
                    words = new List<string[]>();
                    continue;
                }
                if (line[0] == '#') continue;
                string[] fields = line.Split('\t');
                if (fields.Length < 10 || fields[0].Contains("-") || fields[0].Contains(".")) continue;
                words.Add(fields);
            }
        }
        // (a cut form is said as the word it is cut from: "d'" is "de")
        Func<string[], string> full = w => w[1].EndsWith("'", StringComparison.Ordinal) || w[1].EndsWith("’", StringComparison.Ordinal) ? w[2].ToLowerInvariant() : w[1].ToLowerInvariant();
        foreach (string[][] sentence in sentences)
        {
            Dictionary<string, string> relation = sentence.ToDictionary(w => w[0], w => w[7], StringComparer.Ordinal);
            int negation = Array.FindIndex(sentence, w => ("|" + w[5] + "|").Contains("|Polarity=Neg|"));
            for (int i = 0; i < sentence.Length; i++)
            {
                string[] w = sentence[i];
                string head;
                if (w[3] != "DET" || !("|" + w[5] + "|").Contains("|Definite=Ind|") || !relation.TryGetValue(w[6], out head) || head != "obj") continue;
                if (negation < 0) { int n; plain.TryGetValue(full(w), out n); plain[full(w)] = n + 1; plainTotal++; }
                else if (i > negation) { int n; denied.TryGetValue(full(w), out n); denied[full(w)] = n + 1; deniedTotal++; }
            }
        }
        List<LambekLogicWord> found = new List<LambekLogicWord>();
        if (deniedTotal == 0 || plainTotal == 0) return found;
        KeyValuePair<string, int> best = denied.Where(p => p.Value >= least)
            .Where(p => { int n; plain.TryGetValue(p.Key, out n); return (long) p.Value * plainTotal >= 4L * n * deniedTotal; })
            .OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal).FirstOrDefault();
        if (best.Key == null) return found;
        found.Add(new LambekLogicWord { Kind = "negated", Word = best.Key, Together = best.Value, Seen = deniedTotal });
        Dictionary<string, int> cut = new Dictionary<string, int>(StringComparer.Ordinal);
        Dictionary<string, int> whole = new Dictionary<string, int>(StringComparer.Ordinal);
        Dictionary<string, string> cutForm = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (string[][] sentence in sentences)
        {
            for (int i = 0; i + 1 < sentence.Length; i++)
            {
                string form = sentence[i][1].ToLowerInvariant();
                string next = sentence[i + 1][1].ToLowerInvariant();
                if (next.Length == 0 || !char.IsLetter(next[0])) continue;
                string first = next.Substring(0, 1);
                bool isCut = (form.EndsWith("'", StringComparison.Ordinal) || form.EndsWith("’", StringComparison.Ordinal)) && sentence[i][2].ToLowerInvariant() == best.Key;
                if (isCut) { int n; cut.TryGetValue(first, out n); cut[first] = n + 1; cutForm[first] = form.Substring(0, form.Length - 1) + "'"; }
                else if (form == best.Key) { int n; whole.TryGetValue(first, out n); whole[first] = n + 1; }
            }
        }
        foreach (KeyValuePair<string, int> pair in cut.OrderBy(p => p.Key, StringComparer.Ordinal))
        {
            int n; whole.TryGetValue(pair.Key, out n);
            if (pair.Value >= 2 && pair.Value > n) found.Add(new LambekLogicWord { Kind = "elided", Word = cutForm[pair.Key] + " " + pair.Key, Together = pair.Value, Seen = pair.Value + n });
        }
        return found;
    }

    public static void Write(string path, string source, IEnumerable<LambekLogicWord> words)
    {
        using (StreamWriter writer = new StreamWriter(path, false, new System.Text.UTF8Encoding(false)))
        {
            writer.NewLine = "\n";
            writer.WriteLine("# " + Format + "\t" + source);
            foreach (LambekLogicWord word in words) writer.WriteLine(word.Kind + "\t" + word.Word + "\t" + word.Together + "\t" + word.Seen);
        }
    }

    public static List<LambekLogicWord> Read(string path)
    {
        List<LambekLogicWord> words = new List<LambekLogicWord>();
        foreach (string line in File.ReadAllLines(path))
        {
            if (line.Length == 0 || line.StartsWith("#", StringComparison.Ordinal)) continue;
            string[] parts = line.Split('\t');
            if (parts.Length < 4) continue;
            words.Add(new LambekLogicWord { Kind = parts[0], Word = parts[1], Together = int.Parse(parts[2]), Seen = int.Parse(parts[3]) });
        }
        return words;
    }
}
