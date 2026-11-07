using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

// The small words a language talks with, learned, never written: from the tags of its forms model (the articles are
// the words most often tagged DET with PronType=Art; the speaker, the pronouns tagged Person=1...), from its treebanks
// (the word that says whose: the preposition most often the case of a noun that depends on a noun) and from sentences
// translated from English (Tatoeba: "Yes." is "Ja.", "I don't know." is "Ich weiss nicht.")
public static class LambekDialogueWords
{
    // A class of words: a part of speech and the features its words must have, read on the tag each word is most
    // often seen with ("ein": DET|...|Definite=Ind|...|PronType=Art)
    static readonly Dictionary<string, Tuple<string, string[]>> Classes = new Dictionary<string, Tuple<string, string[]>>(StringComparer.Ordinal)
    {
        { "Articles", Tuple.Create("DET", new[] { "PronType=Art" }) },
        { "Indefinite", Tuple.Create("DET", new[] { "PronType=Art", "Definite=Ind" }) },
        { "Definite", Tuple.Create("DET", new[] { "PronType=Art", "Definite=Def" }) },
        { "Demonstratives", Tuple.Create("DET", new[] { "PronType=Dem" }) },
        { "Owners", Tuple.Create("DET", new[] { "Poss=Yes" }) },
        { "Determiners", Tuple.Create("DET", new string[0]) },
        { "Speaker", Tuple.Create("PRON", new[] { "Person=1", "Number=Sing", "!Poss=Yes" }) },
        { "Speakers", Tuple.Create("PRON", new[] { "Person=1", "!Poss=Yes" }) },
        { "Addressee", Tuple.Create("PRON", new[] { "Person=2", "!Poss=Yes" }) },
        { "Pronouns", Tuple.Create("PRON", new[] { "Person=3", "PronType=Prs" }) },
        { "Interrogatives", Tuple.Create("PRON", new[] { "PronType=Int" }) },
        { "Prepositions", Tuple.Create("ADP", new string[0]) },
        { "Conjunctions", Tuple.Create("CCONJ", new string[0]) },
        { "Auxiliaries", Tuple.Create("AUX", new string[0]) },
        { "Negations", Tuple.Create("", new[] { "Polarity=Neg" }) },
    };

    // (how often each word is said in sentences of the language: the small words of a language are said often; a
    // word of another language quoted in its treebanks, "the" in German, is not)
    public static SortedDictionary<string, string[]> Lists(LambekForms model, string[] said, int least)
    {
        Dictionary<string, int> seenTimes = new Dictionary<string, int>(StringComparer.Ordinal);
        System.Text.RegularExpressions.Regex wordPattern = new System.Text.RegularExpressions.Regex(@"\p{L}+['\u2019]|\p{L}+(?:-\p{L}+)*");
        foreach (string sentence in said)
        {
            foreach (System.Text.RegularExpressions.Match match in wordPattern.Matches(sentence.ToLowerInvariant()))
            {
                int n; seenTimes.TryGetValue(match.Value, out n); seenTimes[match.Value] = n + 1;
            }
        }
        SortedDictionary<string, string[]> lists = new SortedDictionary<string, string[]>(StringComparer.Ordinal);
        foreach (KeyValuePair<string, Tuple<string, string[]>> pair in Classes)
        {
            SortedSet<string> words = new SortedSet<string>(StringComparer.Ordinal);
            foreach (KeyValuePair<string, string[]> word in model.Tags)
            {
                // (written in lower case, a word of the language and not a name; seen often enough to be sure of it)
                if (word.Value.Length == 0 || word.Key != word.Key.ToLowerInvariant() || !word.Key.Any(char.IsLetter)) continue;
                int seen;
                if (!seenTimes.TryGetValue(word.Key, out seen) || seen < least) continue;
                string first = word.Value[0];
                int bar = first.IndexOf('|');
                string upos = bar < 0 ? first : first.Substring(0, bar);
                string feats = "|" + (bar < 0 ? "" : first.Substring(bar + 1)) + "|";
                if (pair.Value.Item1.Length > 0 && upos != pair.Value.Item1) continue;
                // (a feature of several values holds each: "PronType=Int,Rel" is Int)
                if (pair.Value.Item2.All(feature => Has(feats, feature))) words.Add(word.Key);
            }
            lists[pair.Key] = words.ToArray();
        }
        return lists;
    }

    static bool Has(string feats, string feature)
    {
        // (a feature it must not have: "!Poss=Yes", "mijn" is not who speaks)
        if (feature.StartsWith("!", StringComparison.Ordinal)) return !Has(feats, feature.Substring(1));
        int equals = feature.IndexOf('=');
        string name = feature.Substring(0, equals + 1);
        string value = feature.Substring(equals + 1);
        foreach (string part in feats.Split('|'))
        {
            if (part.StartsWith(name, StringComparison.Ordinal) && part.Substring(name.Length).Split(',').Contains(value)) return true;
        }
        return false;
    }

    // The word that says whose ("le chat de ma soeur", "the cat of my sister", "die Katze von"): the preposition most
    // often the case of a noun that depends on a noun (nmod), and its written forms
    public static string[] Of(IEnumerable<string> paths)
    {
        Dictionary<string, int> counts = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (string path in paths)
        {
            List<string[]> words = new List<string[]>();
            foreach (string line in File.ReadLines(path).Concat(new[] { "" }))
            {
                if (line.Length == 0)
                {
                    Dictionary<string, string[]> byId = words.ToDictionary(w => w[0], w => w, StringComparer.Ordinal);
                    foreach (string[] w in words)
                    {
                        string[] head;
                        if (w[3] != "ADP" || w[7] != "case" || !byId.TryGetValue(w[6], out head) || head[7] != "nmod") continue;
                        string lemma = w[2].ToLowerInvariant();
                        int n; counts.TryGetValue(lemma, out n); counts[lemma] = n + 1;
                    }
                    words = new List<string[]>();
                    continue;
                }
                if (line[0] == '#') continue;
                string[] fields = line.Split('\t');
                if (fields.Length < 10 || fields[0].Contains("-") || fields[0].Contains(".")) continue;
                words.Add(fields);
            }
        }
        if (counts.Count == 0) return new string[0];
        return new[] { counts.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal).First().Key };
    }

    static readonly System.Text.RegularExpressions.Regex Word = new System.Text.RegularExpressions.Regex(@"\p{L}+['\u2019]|\p{L}+(?:-\p{L}+)*");

    static Dictionary<string, int> Counts(string[] said)
    {
        Dictionary<string, int> counts = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (string sentence in said)
        {
            foreach (System.Text.RegularExpressions.Match match in Word.Matches(sentence.ToLowerInvariant()))
            {
                int n; counts.TryGetValue(match.Value, out n); counts[match.Value] = n + 1;
            }
        }
        return counts;
    }

    // What the other language says for an English sentence: the translation Tatoeba gives it; when it gives more than
    // one, the one whose rarest word the language says the most ("Nein." before "Noe."), then the one said most often
    public static string Phrase(string[] english, string[] other, string asked)
    {
        Dictionary<string, int> words = Counts(other);
        Dictionary<string, int> said = new Dictionary<string, int>(StringComparer.Ordinal);
        List<string> found = new List<string>();
        for (int i = 0; i < english.Length && i < other.Length; i++)
        {
            string theirs = other[i].Trim();
            int n; said.TryGetValue(theirs, out n); said[theirs] = n + 1;
            if (english[i].Trim() == asked) found.Add(theirs);
        }
        if (found.Count == 0) return null;
        Func<string, int> rarest = s =>
        {
            int least = int.MaxValue;
            foreach (System.Text.RegularExpressions.Match match in Word.Matches(s.ToLowerInvariant())) { int n; words.TryGetValue(match.Value, out n); least = Math.Min(least, n); }
            return least == int.MaxValue ? 0 : least;
        };
        return found.Distinct(StringComparer.Ordinal).OrderByDescending(rarest).ThenByDescending(s => said[s]).ThenBy(s => s.Length).ThenBy(s => s, StringComparer.Ordinal).First();
    }

    // How many short pairs a word of the other language is met in, and in how many of them the English side has one of
    // the English words given ("ik" with "I" or "me")
    public static int[] With(string[] english, string[] other, string[] asked, string word, int longest)
    {
        HashSet<string> wanted = new HashSet<string>(asked, StringComparer.Ordinal);
        int together = 0, seen = 0;
        for (int i = 0; i < english.Length && i < other.Length; i++)
        {
            List<string> theirs = Word.Matches(other[i].ToLowerInvariant()).Cast<System.Text.RegularExpressions.Match>().Select(m => m.Value).ToList();
            if (theirs.Count > longest || !theirs.Contains(word)) continue;
            seen++;
            if (Word.Matches(english[i].ToLowerInvariant()).Cast<System.Text.RegularExpressions.Match>().Any(m => wanted.Contains(m.Value))) together++;
        }
        return new[] { together, seen };
    }

    // The word of the other language met where an English word is ("of": "von"): among the words given, the one in
    // the most short pairs with it, weighed by how often it is with it (with it in many pairs, and in most of its own)
    public static string Aligned(string[] english, string[] other, string asked, IEnumerable<string> words, int least, int longest)
    {
        HashSet<string> candidates = new HashSet<string>(words, StringComparer.Ordinal);
        Dictionary<string, int> together = new Dictionary<string, int>(StringComparer.Ordinal);
        Dictionary<string, int> seen = new Dictionary<string, int>(StringComparer.Ordinal);
        for (int i = 0; i < english.Length && i < other.Length; i++)
        {
            List<string> theirs = Word.Matches(other[i].ToLowerInvariant()).Cast<System.Text.RegularExpressions.Match>().Select(m => m.Value).ToList();
            if (theirs.Count > longest) continue;
            bool has = Word.Matches(english[i].ToLowerInvariant()).Cast<System.Text.RegularExpressions.Match>().Any(m => m.Value == asked);
            foreach (string word in theirs.Distinct(StringComparer.Ordinal))
            {
                if (!candidates.Contains(word)) continue;
                int n; seen.TryGetValue(word, out n); seen[word] = n + 1;
                if (has) { together.TryGetValue(word, out n); together[word] = n + 1; }
            }
        }
        KeyValuePair<string, int> best = together.Where(p => p.Value >= least)
            .OrderByDescending(p => (double) p.Value * p.Value / seen[p.Key]).ThenBy(p => p.Key, StringComparer.Ordinal).FirstOrDefault();
        return best.Key;
    }
}
