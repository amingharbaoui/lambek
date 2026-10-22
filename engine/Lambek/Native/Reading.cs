// Lambek learns words by reading plain text on its own (step 4.6 of the roadmap), as a pupil reads books with a
// notebook: every word it does not know is read in each sentence it meets it in, and only what is confirmed is
// written down. Bootstrapping (Yarowsky, 1995): start from what is sure (the forms learned from the treebanks), read,
// keep only the readings many sentences agree on, never what Lambek itself said.
//   - a word kept was met in several sentences, and read the same way (part of speech and lemma) in most of them;
//   - a word that is mostly written with a capital inside a sentence is a name: not kept here;
//   - its lemma is a lemma already known, or one that several of the forms read agree on, or the one found by saying
//     the word again (Analyze): a lemma made up from one form alone is not kept;
//   - every word kept says how often it was met, and in which sources.
// The same texts read in the same order give the same notebook, line for line, on every machine.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

// One word learned from plain text: its form, the part of speech, lemma and features it was read with, how often it
// was met, how many of those times it was read so, and where
public class LambekLearnedWord
{
    public string Form;
    public string Upos;
    public string Lemma;
    public string Feats;
    public int Count;
    public int Agreeing;
    public string Sources;
    public string Why;
}

// The sentences of a text, whatever its shape
public static class LambekCorpusText
{
    // "lines": one sentence a line; "last-field": a sentence after the last tab (Tatoeba, Leipzig); "book": a book of
    // Project Gutenberg, cut into sentences between its start and end marks
    public static IEnumerable<string> Sentences(string path, string shape)
    {
        if (shape == "book")
        {
            foreach (string sentence in Book(path)) yield return sentence;
            yield break;
        }
        using (StreamReader reader = new StreamReader(path, new UTF8Encoding(false)))
        {
            string line;
            while ((line = reader.ReadLine()) != null)
            {
                if (shape == "last-field")
                {
                    int tab = line.LastIndexOf('\t');
                    if (tab >= 0) line = line.Substring(tab + 1);
                }
                line = line.Trim();
                if (line.Length > 0) yield return line;
            }
        }
    }

    static readonly Regex End = new Regex(@"(?<=[.!?\u2026\u00BB])\s+(?=[\u00AB""\p{Lu}\u2014\u2013-])", RegexOptions.CultureInvariant);

    static IEnumerable<string> Book(string path)
    {
        string text = File.ReadAllText(path, new UTF8Encoding(false)).Replace("\r\n", "\n");
        int start = text.IndexOf("*** START OF", StringComparison.Ordinal);
        if (start >= 0) start = text.IndexOf('\n', start) + 1; else start = 0;
        int end = text.IndexOf("*** END OF", StringComparison.Ordinal);
        if (end < 0) end = text.Length;
        foreach (string paragraph in text.Substring(start, end - start).Split(new[] { "\n\n" }, StringSplitOptions.RemoveEmptyEntries))
        {
            string flat = Regex.Replace(paragraph, @"\s+", " ").Trim();
            if (flat.Length == 0) continue;
            foreach (string sentence in End.Split(flat))
            {
                string trimmed = sentence.Trim();
                if (trimmed.Length > 0) yield return trimmed;
            }
        }
    }
}

public class LambekSelfReader
{
    public readonly LambekForms Model;
    // How many sentences a word must be met in, and the share of them that must read it the same way
    public int Least = 3;
    public double Agreement = 0.6;
    // Sentences longer than this are not read (lists, tables, run-on text)
    public int LongestSentence = 60;

    // For each word met and not known: each reading and how often, and the shape it was written in
    readonly Dictionary<string, Dictionary<string, int>> readings = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
    readonly Dictionary<string, SortedDictionary<string, int>> sources = new Dictionary<string, SortedDictionary<string, int>>(StringComparer.Ordinal);
    readonly Dictionary<string, int> capitals = new Dictionary<string, int>(StringComparer.Ordinal);
    // The gender the words before a noun give it, as the model reads them ("une", "la": feminine), by noun
    readonly Dictionary<string, int[]> genders = new Dictionary<string, int[]>(StringComparer.Ordinal);
    // Every word met in the texts, in small letters: a lemma never seen in the treebanks must at least be a word of them
    readonly HashSet<string> met = new HashSet<string>(StringComparer.Ordinal);
    public bool Met(string word) { return met.Contains((word ?? "").ToLowerInvariant()); }
    public long Sentences;
    public long Words;

    public LambekSelfReader(LambekForms model) { Model = model; }

    static bool Plain(string form)
    {
        if (form.Length < 2) return false;
        foreach (char c in form) if (!char.IsLetter(c) && c != '-') return false;
        return char.IsLetter(form[0]) && char.IsLetter(form[form.Length - 1]);
    }

    // A word joined to a small word after it ("prends-tu", "appelle-moi", "est-ce") is two words badly cut, not one
    // (the small word: one of the commonest, or one the treebanks read as a pronoun, as "toi", "moi")
    readonly Dictionary<string, bool> tails = new Dictionary<string, bool>(StringComparer.Ordinal);
    bool Joined(string lower)
    {
        int dash = lower.LastIndexOf('-');
        if (dash < 0) return false;
        string tail = lower.Substring(dash + 1);
        if (Model.Common.Contains(tail) || Model.Common.Contains("-" + tail) || tail.Length <= 2) return true;
        bool pronoun;
        if (!tails.TryGetValue(tail, out pronoun))
        {
            pronoun = Model.Knows(tail) && Model.ReadText(tail).Any(reading => reading.Upos == "PRON");
            tails[tail] = pronoun;
        }
        return pronoun;
    }

    // Reads one source: every sentence, every word it does not know
    public void Read(string source, IEnumerable<string> sentences)
    {
        bool second = Model.SecondReader;
        Model.SecondReader = false;
        try { ReadAll(source, sentences); }
        finally { Model.SecondReader = second; }
    }

    void ReadAll(string source, IEnumerable<string> sentences)
    {
        foreach (string sentence in sentences)
        {
            string[] forms = Model.Tokenize(sentence);
            if (forms.Length == 0 || forms.Length > LongestSentence) continue;
            Sentences++;
            Words += forms.Length;
            LambekFormReading[] read = Model.Read(forms);
            for (int i = 0; i < forms.Length; i++)
            {
                string form = forms[i];
                if (!Plain(form)) continue;
                string lower = form.ToLowerInvariant();
                met.Add(lower);
                if (Model.Knows(form) || Joined(lower)) continue;
                // (the gender a determiner before it gives the word: its own reading says nothing of a noun never seen)
                // ("l'", "son" before a vowel say nothing: "l'etagere", "son etagere")
                if (i > 0 && read[i - 1].Upos == "DET" && read[i].Upos == "NOUN" && !read[i - 1].Feats.Contains("Poss=Yes") &&
                    !read[i - 1].Form.EndsWith("'", StringComparison.Ordinal) && !read[i - 1].Form.EndsWith("\u2019", StringComparison.Ordinal))
                {
                    int[] votes;
                    if (!genders.TryGetValue(lower, out votes)) genders[lower] = votes = new int[2];
                    if (read[i - 1].Feats.Contains("Gender=Masc")) votes[0]++;
                    else if (read[i - 1].Feats.Contains("Gender=Fem")) votes[1]++;
                }
                string key = read[i].Upos + "|" + read[i].Lemma.ToLowerInvariant() + "|" + read[i].Feats;
                Dictionary<string, int> seen;
                if (!readings.TryGetValue(lower, out seen)) readings[lower] = seen = new Dictionary<string, int>(StringComparer.Ordinal);
                int count;
                seen.TryGetValue(key, out count);
                seen[key] = count + 1;
                SortedDictionary<string, int> where;
                if (!sources.TryGetValue(lower, out where)) sources[lower] = where = new SortedDictionary<string, int>(StringComparer.Ordinal);
                where.TryGetValue(source, out count);
                where[source] = count + 1;
                // (a capital inside the sentence: a name, or a word of a title)
                if (i > 0 && char.IsUpper(form[0]))
                {
                    capitals.TryGetValue(lower, out count);
                    capitals[lower] = count + 1;
                }
            }
        }
    }

    // What is written down: the words read the same way often enough, whose lemma is sure
    public List<LambekLearnedWord> Decide()
    {
        List<LambekLearnedWord> candidates = new List<LambekLearnedWord>();
        foreach (KeyValuePair<string, Dictionary<string, int>> word in readings.OrderBy(pair => pair.Key, StringComparer.Ordinal))
        {
            int total = word.Value.Values.Sum();
            if (total < Least) continue;
            int capital;
            capitals.TryGetValue(word.Key, out capital);
            if (capital * 2 > total) continue;
            // The part of speech and lemma most of the sentences agree on, then the features most of those give
            Dictionary<string, int> byLemma = new Dictionary<string, int>(StringComparer.Ordinal);
            foreach (KeyValuePair<string, int> reading in word.Value)
            {
                string[] parts = reading.Key.Split('|');
                string head = parts[0] + "|" + parts[1];
                int count;
                byLemma.TryGetValue(head, out count);
                byLemma[head] = count + reading.Value;
            }
            KeyValuePair<string, int> best = byLemma.OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key, StringComparer.Ordinal).First();
            if (best.Value < Agreement * total) continue;
            string[] chosen = best.Key.Split('|');
            if (chosen[0] != "NOUN" && chosen[0] != "VERB" && chosen[0] != "ADJ" && chosen[0] != "ADV") continue;
            string feats = word.Value.Where(pair => pair.Key.StartsWith(best.Key + "|", StringComparison.Ordinal))
                .OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key, StringComparer.Ordinal).First().Key.Substring(best.Key.Length + 1);
            if (feats.Contains("Typo=Yes")) continue;
            candidates.Add(new LambekLearnedWord
            {
                Form = word.Key,
                Upos = chosen[0],
                Lemma = chosen[1],
                Feats = feats,
                Count = total,
                Agreeing = best.Value,
                Sources = string.Join(",", sources[word.Key].Select(pair => pair.Key + ":" + pair.Value.ToString(CultureInfo.InvariantCulture)))
            });
        }

        // A noun has one gender for all its forms ("joue", "joues"): the one the treebanks give its lemma, else the one
        // the determiners before all its forms give, when two in three of them at least agree ("une etagere")
        Dictionary<string, int[]> byNoun = new Dictionary<string, int[]>(StringComparer.Ordinal);
        foreach (LambekLearnedWord word in candidates)
        {
            int[] votes;
            if (word.Upos != "NOUN" || !genders.TryGetValue(word.Form, out votes)) continue;
            int[] pooled;
            if (!byNoun.TryGetValue(word.Lemma, out pooled)) byNoun[word.Lemma] = pooled = new int[2];
            pooled[0] += votes[0];
            pooled[1] += votes[1];
        }
        Dictionary<string, int[]> known = TreebankGenders();
        foreach (LambekLearnedWord word in candidates)
        {
            if (word.Upos != "NOUN") continue;
            int[] gender;
            string said = null;
            if (known.TryGetValue(word.Lemma, out gender)) said = Said(gender, 1);
            if (said == null && byNoun.TryGetValue(word.Lemma, out gender)) said = Said(gender, 2);
            if (said != null) word.Feats = SetFeature(word.Feats, "Gender", said);
        }

        // A lemma never seen in the treebanks is kept when two forms read lead to it, or when saying the word again
        // finds it; else the word is not written down
        Dictionary<string, int> support = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (LambekLearnedWord word in candidates)
        {
            string key = word.Upos + "|" + word.Lemma;
            int count;
            support.TryGetValue(key, out count);
            support[key] = count + 1;
        }
        List<LambekLearnedWord> kept = new List<LambekLearnedWord>();
        foreach (LambekLearnedWord word in candidates)
        {
            if (Model.Lemmas.Contains(word.Lemma)) word.Why = "lemma known";
            else if (!met.Contains(word.Lemma) && !Model.Knows(word.Lemma))
            {
                // A lemma that is no word of the texts ("eteigner") is made up: the word is said again, and a lemma
                // found so that is a word of the texts, or of the treebanks, takes its place ("eteindre")
                LambekFormReading other = Model.Analyze(word.Form).FirstOrDefault(reading => reading.Upos == word.Upos && reading.Lemma != word.Lemma &&
                    (Model.Lemmas.Contains(reading.Lemma) || met.Contains(reading.Lemma)));
                if (other == null) continue;
                word.Lemma = other.Lemma;
                word.Feats = other.Feats;
                word.Why = "said again";
            }
            else if (support[word.Upos + "|" + word.Lemma] >= 2) word.Why = "forms agree";
            else if (Model.Analyze(word.Form).Any(reading => reading.Upos == word.Upos && reading.Lemma == word.Lemma)) word.Why = "said again";
            else if (word.Upos != "VERB" && word.Form == word.Lemma) word.Why = "own lemma";
            else continue;
            kept.Add(word);
        }
        return Confirm(kept);
    }

    // The last check, the word said again: a word whose lemma the treebanks know must be what the forms model says for
    // that lemma with those features ("conserve" read as "consent", by the verbs that begin as it does, is not what
    // "consent" is said as). When it is not, the reading that says it back takes its place, if there is one whose
    // lemma is a word of the treebanks or of the texts; else the word is not written down
    public List<LambekLearnedWord> Confirm(IEnumerable<LambekLearnedWord> words)
    {
        List<LambekLearnedWord> confirmed = new List<LambekLearnedWord>();
        foreach (LambekLearnedWord word in words)
        {
            if (!Model.Lemmas.Contains(word.Lemma) || SaysBack(word.Lemma, word.Upos, word.Feats, word.Form)) { confirmed.Add(word); continue; }
            LambekFormReading other = Model.Analyze(word.Form).FirstOrDefault(reading => reading.Upos == word.Upos && reading.Lemma != word.Lemma &&
                (Model.Lemmas.Contains(reading.Lemma) ? SaysBack(reading.Lemma, reading.Upos, reading.Feats, word.Form) : met.Contains(reading.Lemma)));
            if (other == null) continue;
            word.Lemma = other.Lemma;
            word.Feats = other.Feats;
            word.Why = "said again";
            confirmed.Add(word);
        }
        return confirmed;
    }

    bool SaysBack(string lemma, string upos, string feats, string form)
    {
        return Model.Inflect(lemma, upos, feats).Any(said => string.Equals(said, form, StringComparison.OrdinalIgnoreCase));
    }

    // The gender most of the votes give, two in three of them at least, from "least" votes on
    static string Said(int[] gender, int least)
    {
        if (gender[0] + gender[1] < least) return null;
        return gender[0] > 2 * gender[1] ? "Masc" : gender[1] > 2 * gender[0] ? "Fem" : null;
    }

    // The gender of each noun lemma of the treebanks, by how often its forms were written with each
    Dictionary<string, int[]> TreebankGenders()
    {
        Dictionary<string, int[]> genderOf = new Dictionary<string, int[]>(StringComparer.Ordinal);
        foreach (KeyValuePair<string, SortedDictionary<string, int>> paradigm in Model.Paradigms)
        {
            if (!paradigm.Key.StartsWith("NOUN\t", StringComparison.Ordinal)) continue;
            string[] parts = paradigm.Key.Split('\t');
            if (parts.Length < 3) continue;
            int side = parts[2].Contains("Gender=Masc") ? 0 : parts[2].Contains("Gender=Fem") ? 1 : -1;
            if (side < 0) continue;
            int[] votes;
            if (!genderOf.TryGetValue(parts[1], out votes)) genderOf[parts[1]] = votes = new int[2];
            votes[side] += paradigm.Value.Values.Sum();
        }
        return genderOf;
    }

    static string SetFeature(string feats, string name, string value)
    {
        List<string> parts = (feats == "_" || string.IsNullOrEmpty(feats) ? new string[0] : feats.Split('|')).Where(part => !part.StartsWith(name + "=", StringComparison.Ordinal)).ToList();
        parts.Add(name + "=" + value);
        parts.Sort(StringComparer.Ordinal);
        return string.Join("|", parts);
    }

    public static void Write(string path, IEnumerable<LambekLearnedWord> words, string header)
    {
        using (FileStream file = File.Create(path))
        using (GZipStream zip = new GZipStream(file, CompressionLevel.Optimal))
        using (StreamWriter writer = new StreamWriter(zip, new UTF8Encoding(false)))
        {
            writer.NewLine = "\n";
            writer.WriteLine("# " + header);
            writer.WriteLine("# form\tupos\tlemma\tfeats\tcount\tagreeing\twhy\tsources");
            foreach (LambekLearnedWord word in words)
            {
                writer.WriteLine(string.Join("\t", word.Form, word.Upos, word.Lemma, word.Feats, word.Count.ToString(CultureInfo.InvariantCulture),
                    word.Agreeing.ToString(CultureInfo.InvariantCulture), word.Why, word.Sources));
            }
        }
    }

    public static List<LambekLearnedWord> Load(string path)
    {
        List<LambekLearnedWord> words = new List<LambekLearnedWord>();
        using (FileStream file = File.OpenRead(path))
        using (GZipStream zip = new GZipStream(file, CompressionMode.Decompress))
        using (StreamReader reader = new StreamReader(zip, new UTF8Encoding(false)))
        {
            string line;
            while ((line = reader.ReadLine()) != null)
            {
                if (line.Length == 0 || line[0] == '#') continue;
                string[] parts = line.Split('\t');
                if (parts.Length < 8) continue;
                words.Add(new LambekLearnedWord
                {
                    Form = parts[0], Upos = parts[1], Lemma = parts[2], Feats = parts[3],
                    Count = int.Parse(parts[4], CultureInfo.InvariantCulture), Agreeing = int.Parse(parts[5], CultureInfo.InvariantCulture),
                    Why = parts[6], Sources = parts[7]
                });
            }
        }
        return words;
    }
}
