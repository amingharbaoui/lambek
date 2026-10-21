// The dictionaries of Lambek: WordNet for the meanings, WOLF for the French words, Lefff for the French forms.
// Everything is read in a fixed order and compared ordinally, so the same word always gives the same answer.
// Synsets and words are numbers once loaded, and the French forms one sorted text, so the whole stays small.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

// One reading of a form: the lemma, its part of speech (n, v, a, r, or another word class) and its features
public class LambekLemma
{
    public string Lemma;
    public string Shown;
    public string Pos;
    public string Tag;
}

// A known word a dictionary word leads to, and how
public class LambekRelated
{
    public string Word;
    public string From;
    public string Synset;
    public string Relation;
    public int Hops;
    public int Rank;
}

public class LambekDictionary : ILambekWords
{
    public List<string> Sources = new List<string>();
    public HashSet<string> Languages = new HashSet<string>(StringComparer.Ordinal);
    public bool HasGlosses;
    public HashSet<string> Files = new HashSet<string>(StringComparer.Ordinal);

    // One dictionary for the whole process: it is only read once loaded, and loading takes a second
    public static LambekDictionary Shared = new LambekDictionary();
    object gate = new object();

    public bool Ensure(string path)
    {
        lock (gate)
        {
            if (Files.Contains(path)) return false;
            Load(path);
            Files.Add(path);
            return true;
        }
    }

    public static Task Begin(string[] paths)
    {
        // Loaded in the background: a request that needs it waits in Ensure for the file it needs
        return Task.Run(() => { foreach (string path in paths) { try { Shared.Ensure(path); } catch (Exception) { } } });
    }

    static string[] kinds = new string[] { "hyper", "hypo", "also", "group", "similar", "anti" };

    // Synsets: a number each, their links as (kind << 24 | target)
    Dictionary<string, int> synsetIds = new Dictionary<string, int>(StringComparer.Ordinal);
    List<string> synsetNames = new List<string>();
    List<List<int>> links = new List<List<int>>();
    Dictionary<int, string> glosses = new Dictionary<int, string>();

    // Words, by language: "lemma\tpos" -> synsets, most frequent first; synset -> lemmas
    Dictionary<string, Dictionary<string, int[]>> senses = new Dictionary<string, Dictionary<string, int[]>>(StringComparer.Ordinal);
    Dictionary<string, Dictionary<int, List<string>>> members = new Dictionary<string, Dictionary<int, List<string>>>(StringComparer.Ordinal);
    Dictionary<string, string> words = new Dictionary<string, string>(StringComparer.Ordinal);
    // The lemmas as the dictionary writes them, with their accents, to show
    Dictionary<string, Dictionary<int, List<string>>> written = new Dictionary<string, Dictionary<int, List<string>>>(StringComparer.Ordinal);

    // The forms of each language (Lefff for French, UniMorph for the others): the lemmas and their forms,
    // and every form without accents in one sorted text
    class FormIndex
    {
        public List<string> LemmaKeys = new List<string>();
        public List<string> LemmaForms = new List<string>();
        public Dictionary<string, int> LemmaIds = new Dictionary<string, int>(StringComparer.Ordinal);
        public StringBuilder Text = new StringBuilder();
        public List<int> Starts = new List<int>();
        public List<int> PostingStarts = new List<int>();
        public List<int> Postings = new List<int>();
        public string Buffer;
    }
    Dictionary<string, FormIndex> formIndexes = new Dictionary<string, FormIndex>(StringComparer.Ordinal);

    // English irregular forms: form -> "lemma\tpos"
    Dictionary<string, List<string>> exceptions = new Dictionary<string, List<string>>(StringComparer.Ordinal);

    public static string Normalize(string text)
    {
        // Same as the engine: no accents, lower case (plain ASCII only needs the lower case)
        bool ascii = true;
        foreach (char c in text) { if (c > 127) { ascii = false; break; } }
        if (ascii) return text.ToLowerInvariant();
        string decomposed = text.Normalize(NormalizationForm.FormD);
        StringBuilder builder = new StringBuilder(decomposed.Length);
        foreach (char c in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) builder.Append(c);
        }
        return builder.ToString().Normalize(NormalizationForm.FormC).ToLowerInvariant();
    }

    static string PosOf(string category)
    {
        // Lefff categories to WordNet parts of speech
        switch (category)
        {
            case "v": return "v";
            case "nc": return "n";
            case "adj": return "a";
            case "adv": return "r";
            default: return category;
        }
    }

    string Word(string text)
    {
        // One string for each word, shared by every table
        string found;
        if (words.TryGetValue(text, out found)) return found;
        words[text] = text;
        return text;
    }

    int Synset(string name)
    {
        int id;
        if (synsetIds.TryGetValue(name, out id)) return id;
        id = synsetNames.Count;
        synsetIds[name] = id;
        synsetNames.Add(name);
        links.Add(null);
        return id;
    }

    // Load
    public void Load(string path)
    {
        using (FileStream file = File.OpenRead(path))
        using (GZipStream zip = new GZipStream(file, CompressionMode.Decompress))
        using (StreamReader reader = new StreamReader(zip, new UTF8Encoding(false)))
        {
            string header = reader.ReadLine();
            if (header == null || !header.StartsWith("#lambek-dictionary 1 ", StringComparison.Ordinal))
            {
                throw new InvalidDataException(path + " is not a Lambek dictionary.");
            }
            string kind = header.Substring(21);
            if (kind == "glosses") HasGlosses = true;
            else if (kind != "graph") Languages.Add(kind);
            FormIndex index = null;
            if (kind != "glosses" && kind != "graph")
            {
                if (!formIndexes.TryGetValue(kind, out index)) { index = new FormIndex(); formIndexes[kind] = index; }
            }

            string line;
            while ((line = reader.ReadLine()) != null)
            {
                if (line.Length < 2) continue;
                if (line[0] == '#')
                {
                    if (line.StartsWith("#source ", StringComparison.Ordinal) && !Sources.Contains(line.Substring(8))) Sources.Add(line.Substring(8));
                    continue;
                }
                int first = line.IndexOf('\t');
                int second = line.IndexOf('\t', first + 1);
                switch (line[0])
                {
                    case 'S': AddLinks(line.Substring(2, second - 2), line.Substring(second + 1)); break;
                    case 'G': glosses[Synset(line.Substring(2, second - 2))] = line.Substring(second + 1); break;
                    case 'W':
                        {
                            string[] fields = line.Split('\t');
                            AddWord(kind, fields[1], fields[2], fields[3]);
                            break;
                        }
                    case 'X':
                        {
                            string[] fields = line.Split('\t');
                            if (!exceptions.ContainsKey(fields[1])) exceptions[fields[1]] = new List<string>();
                            exceptions[fields[1]].Add(fields[2] + "\t" + fields[3]);
                            break;
                        }
                    case 'L':
                        {
                            int third = line.IndexOf('\t', second + 1);
                            string lemma = line.Substring(2, second - 2);
                            string key = Normalize(lemma) + "\t" + PosOf(line.Substring(second + 1, third - second - 1));
                            if (!index.LemmaIds.ContainsKey(key)) index.LemmaIds[key] = index.LemmaKeys.Count;
                            index.LemmaKeys.Add(lemma + "\t" + PosOf(line.Substring(second + 1, third - second - 1)));
                            index.LemmaForms.Add(line.Substring(third + 1));
                            break;
                        }
                    case 'F':
                        {
                            // Sorted by the builder: appended as they come
                            if (index.Buffer != null && index.Text.Length == 0) index.Text.Append(index.Buffer);
                            index.Starts.Add(index.Text.Length);
                            index.Text.Append(line, 2, second - 2);
                            index.PostingStarts.Add(index.Postings.Count);
                            foreach (string number in line.Substring(second + 1).Split(',')) index.Postings.Add(int.Parse(number, CultureInfo.InvariantCulture));
                            break;
                        }
                }
            }
        }
        foreach (FormIndex index in formIndexes.Values)
        {
            if (index.Text.Length == 0) continue;
            index.Buffer = index.Text.ToString();
            index.Text = new StringBuilder();
            index.Starts.TrimExcess();
            index.PostingStarts.TrimExcess();
            index.Postings.TrimExcess();
        }
        foreach (List<int> list in links) { if (list != null) list.TrimExcess(); }
    }

    void AddLinks(string name, string list)
    {
        int id = Synset(name);
        if (links[id] == null) links[id] = new List<int>();
        if (list.Length == 0) return;
        foreach (string item in list.Split(','))
        {
            int colon = item.IndexOf(':');
            int kind = Array.IndexOf(kinds, item.Substring(0, colon));
            int target = Synset(item.Substring(colon + 1));
            links[id].Add((kind << 24) | target);
            // A hypernym read backwards is a hyponym
            if (kind == 0)
            {
                if (links[target] == null) links[target] = new List<int>();
                links[target].Add((1 << 24) | id);
            }
        }
    }

    void AddWord(string language, string lemma, string pos, string ids)
    {
        string word = Word(Normalize(lemma));
        if (!senses.ContainsKey(language)) senses[language] = new Dictionary<string, int[]>(StringComparer.Ordinal);
        if (!members.ContainsKey(language)) members[language] = new Dictionary<int, List<string>>();
        if (!written.ContainsKey(language)) written[language] = new Dictionary<int, List<string>>();
        string key = word + "\t" + pos;
        int[] list = ids.Split(',').Select(Synset).ToArray();
        // Two lemmas that only differ by their accents share their senses
        int[] had;
        if (senses[language].TryGetValue(key, out had)) list = had.Concat(list.Where(id => !had.Contains(id))).ToArray();
        senses[language][key] = list;
        foreach (int id in list)
        {
            List<string> group;
            if (!members[language].TryGetValue(id, out group))
            {
                group = new List<string>(2);
                members[language][id] = group;
            }
            if (!group.Contains(word))
            {
                group.Add(word);
                List<string> shown;
                if (!written[language].TryGetValue(id, out shown))
                {
                    shown = new List<string>(2);
                    written[language][id] = shown;
                }
                shown.Add(word == lemma ? word : Word(lemma));
            }
        }
    }

    // The lemmas of a synset as they are written ("éliminer", not "eliminer")
    public string[] Written(string synset, string language)
    {
        int id;
        Dictionary<int, List<string>> table;
        List<string> list;
        if (synsetIds.TryGetValue(synset, out id) && written.TryGetValue(language, out table) && table.TryGetValue(id, out list)) return list.ToArray();
        return new string[0];
    }

    // Reading
    int[] SenseIds(string lemma, string language, string pos)
    {
        Dictionary<string, int[]> table;
        int[] list;
        if (senses.TryGetValue(language, out table) && table.TryGetValue(lemma + "\t" + pos, out list)) return list;
        return new int[0];
    }

    public string[] Senses(string lemma, string language, string pos)
    {
        return SenseIds(Normalize(lemma), language, pos).Select(id => synsetNames[id]).ToArray();
    }

    public string Gloss(string synset)
    {
        int id;
        string gloss;
        if (synsetIds.TryGetValue(synset, out id) && glosses.TryGetValue(id, out gloss)) return gloss;
        return null;
    }

    public string[] Members(string synset, string language)
    {
        int id;
        if (!synsetIds.TryGetValue(synset, out id)) return new string[0];
        return MemberList(id, language).ToArray();
    }

    List<string> MemberList(int id, string language)
    {
        Dictionary<int, List<string>> table;
        List<string> list;
        if (members.TryGetValue(language, out table) && table.TryGetValue(id, out list)) return list;
        return new List<string>();
    }

    public string[] Links(string synset)
    {
        int id;
        if (!synsetIds.TryGetValue(synset, out id) || links[id] == null) return new string[0];
        return links[id].Select(link => kinds[link >> 24] + ":" + synsetNames[link & 0xFFFFFF]).ToArray();
    }

    static int FindForm(FormIndex index, string form)
    {
        // Binary search in the sorted forms
        int low = 0;
        int high = index.Starts.Count - 1;
        while (low <= high)
        {
            int middle = (low + high) / 2;
            int start = index.Starts[middle];
            int length = (middle + 1 < index.Starts.Count ? index.Starts[middle + 1] : index.Buffer.Length) - start;
            int compare = string.CompareOrdinal(index.Buffer, start, form, 0, Math.Min(length, form.Length));
            if (compare == 0) compare = length.CompareTo(form.Length);
            if (compare == 0) return middle;
            if (compare < 0) low = middle + 1;
            else high = middle - 1;
        }
        return -1;
    }

    public LambekLemma[] Lemmas(string word, string language)
    {
        return Lemmas(word, language, false);
    }

    // Typing slips: the forms of a language one edit away from a word that is none of them (a letter missing, one too
    // many, one changed, or two side by side swapped), compared without accents. At most max + 1 are returned, so one
    // more than max says there are too many to choose from
    public string[] Near(string word, string language, int max)
    {
        List<string> found = new List<string>();
        FormIndex index;
        string form = Normalize(word);
        if (!formIndexes.TryGetValue(language, out index) || index.Buffer == null)
        {
            // A language without its forms (English): the lemmas of WordNet, one word each
            Dictionary<string, int[]> lemmas;
            if (!senses.TryGetValue(language, out lemmas)) return found.ToArray();
            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (string key in lemmas.Keys)
            {
                int tab = key.IndexOf('\t');
                string lemma = tab < 0 ? key : key.Substring(0, tab);
                if (lemma == form) return new string[0];
                if (Math.Abs(lemma.Length - form.Length) > 1 || lemma.IndexOf('_') >= 0 || !seen.Add(lemma)) continue;
                if (OneEdit(lemma, 0, lemma.Length, form)) found.Add(lemma);
            }
            found.Sort(StringComparer.Ordinal);
            if (found.Count > max + 1) found.RemoveRange(max + 1, found.Count - max - 1);
            return found.ToArray();
        }
        if (FindForm(index, form) >= 0) return found.ToArray();
        for (int i = 0; i < index.Starts.Count; i++)
        {
            int start = index.Starts[i];
            int length = (i + 1 < index.Starts.Count ? index.Starts[i + 1] : index.Buffer.Length) - start;
            if (Math.Abs(length - form.Length) > 1) continue;
            if (!OneEdit(index.Buffer, start, length, form)) continue;
            found.Add(index.Buffer.Substring(start, length));
            if (found.Count > max) break;
        }
        return found.ToArray();
    }

    internal static bool OneEdit(string buffer, int start, int length, string word)
    {
        // Exactly one edit between buffer[start, start + length) and word (never zero: the same form is no slip)
        int n = word.Length;
        int i = 0;
        while (i < length && i < n && buffer[start + i] == word[i]) i++;
        if (length == n)
        {
            if (i == n) return false;
            // One letter changed: the rest is the same
            bool changed = true;
            for (int k = i + 1; k < n; k++) { if (buffer[start + k] != word[k]) { changed = false; break; } }
            if (changed) return true;
            // Two letters swapped
            if (i + 1 < n && buffer[start + i] == word[i + 1] && buffer[start + i + 1] == word[i])
            {
                for (int k = i + 2; k < n; k++) { if (buffer[start + k] != word[k]) return false; }
                return true;
            }
            return false;
        }
        if (length == n + 1)
        {
            // One letter more in the form: skip it
            for (int k = i; k < n; k++) { if (buffer[start + k + 1] != word[k]) return false; }
            return true;
        }
        if (length + 1 == n)
        {
            // One letter fewer in the form: skip the word's
            for (int k = i; k < length; k++) { if (buffer[start + k] != word[k + 1]) return false; }
            return true;
        }
        return false;
    }

    // Exact: only the forms written with the same accents ("classe" is not "classé"), for speaking
    public LambekLemma[] Lemmas(string word, string language, bool exact)
    {
        string form = Normalize(word);
        string written = word.ToLowerInvariant();
        List<LambekLemma> found = new List<LambekLemma>();
        HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);

        // The forms of the language (Lefff, UniMorph), with their features
        FormIndex index;
        if (formIndexes.TryGetValue(language, out index) && index.Buffer != null)
        {
            int at = FindForm(index, form);
            if (at >= 0)
            {
                int end = at + 1 < index.PostingStarts.Count ? index.PostingStarts[at + 1] : index.Postings.Count;
                for (int k = index.PostingStarts[at]; k < end; k++)
                {
                    int number = index.Postings[k];
                    string[] key = index.LemmaKeys[number].Split('\t');
                    foreach (string item in index.LemmaForms[number].Split('|'))
                    {
                        int colon = item.LastIndexOf(':');
                        if (Normalize(item.Substring(0, colon)) != form) continue;
                        if (exact && item.Substring(0, colon).ToLowerInvariant() != written) continue;
                        LambekLemma reading = new LambekLemma { Lemma = Normalize(key[0]), Shown = key[0], Pos = key[1], Tag = item.Substring(colon + 1) };
                        if (seen.Add(reading.Lemma + "\t" + reading.Pos + "\t" + reading.Tag)) found.Add(reading);
                    }
                }
            }
        }

        // English: the irregular forms and the suffix rules of WordNet's morphy
        if (language == "en")
        {
            foreach (string pos in new string[] { "v", "n", "a", "r" })
            {
                foreach (string lemma in Morphy(form, pos))
                {
                    if (seen.Add(lemma + "\t" + pos + "\t")) found.Add(new LambekLemma { Lemma = lemma, Shown = lemma, Pos = pos, Tag = "" });
                }
            }
        }

        // A word of WordNet or WOLF itself (with "_" for a space)
        foreach (string pos in new string[] { "v", "n", "a", "r" })
        {
            if (SenseIds(form, language, pos).Length > 0 && seen.Add(form + "\t" + pos + "\t")) found.Add(new LambekLemma { Lemma = form, Shown = form, Pos = pos, Tag = "" });
        }
        return found.ToArray();
    }

    List<string> Morphy(string form, string pos)
    {
        // Irregular forms first, then the suffix rules; a lemma counts only if WordNet knows it
        List<string> list = new List<string>();
        List<string> irregular;
        if (exceptions.TryGetValue(form, out irregular))
        {
            foreach (string item in irregular)
            {
                string[] parts = item.Split('\t');
                if (parts[1] == pos && SenseIds(parts[0], "en", pos).Length > 0 && !list.Contains(parts[0])) list.Add(parts[0]);
            }
        }
        string[][] rules;
        switch (pos)
        {
            case "n": rules = new string[][] { new[] { "s", "" }, new[] { "ses", "s" }, new[] { "xes", "x" }, new[] { "zes", "z" }, new[] { "ches", "ch" }, new[] { "shes", "sh" }, new[] { "men", "man" }, new[] { "ies", "y" } }; break;
            case "v": rules = new string[][] { new[] { "s", "" }, new[] { "ies", "y" }, new[] { "es", "e" }, new[] { "es", "" }, new[] { "ed", "e" }, new[] { "ed", "" }, new[] { "ing", "e" }, new[] { "ing", "" } }; break;
            case "a": rules = new string[][] { new[] { "er", "" }, new[] { "est", "" }, new[] { "er", "e" }, new[] { "est", "e" } }; break;
            default: rules = new string[0][]; break;
        }
        foreach (string[] rule in rules)
        {
            if (!form.EndsWith(rule[0], StringComparison.Ordinal) || form.Length <= rule[0].Length) continue;
            string lemma = form.Substring(0, form.Length - rule[0].Length) + rule[1];
            if (SenseIds(lemma, "en", pos).Length > 0 && !list.Contains(lemma)) list.Add(lemma);
        }
        // Doubled consonant: "stopped", "stopping"
        foreach (string suffix in new string[] { "ed", "ing" })
        {
            if (pos != "v" || !form.EndsWith(suffix, StringComparison.Ordinal)) continue;
            string stem = form.Substring(0, form.Length - suffix.Length);
            if (stem.Length > 2 && stem[stem.Length - 1] == stem[stem.Length - 2])
            {
                string lemma = stem.Substring(0, stem.Length - 1);
                if (SenseIds(lemma, "en", pos).Length > 0 && !list.Contains(lemma)) list.Add(lemma);
            }
        }
        return list;
    }

    // Speaking: the forms of a lemma whose tag is the one asked, or starts with it (Lefff tags: P3s, Kmp, W...)
    public string[] Forms(string lemma, string language, string pos, string tag)
    {
        List<string> found = new List<string>();
        int number;
        FormIndex index;
        if (!formIndexes.TryGetValue(language, out index) || !index.LemmaIds.TryGetValue(Normalize(lemma) + "\t" + pos, out number)) return found.ToArray();
        foreach (string item in index.LemmaForms[number].Split('|'))
        {
            int colon = item.LastIndexOf(':');
            if (tag == null || Fits(item.Substring(colon + 1), tag)) found.Add(item.Substring(0, colon));
        }
        return found.ToArray();
    }

    // The past participle of a verb, to say what was done: Lefff for French, the irregular forms or the rules for English
    public string Participle(string lemma, string language)
    {
        string plain = Normalize(lemma);
        if (language == "fr")
        {
            string[] forms = Forms(lemma, "fr", "v", "Kms");
            return forms.Length > 0 ? forms[0] : null;
        }
        // Irregular: the forms WordNet reads back to this verb; the one in -n or -en is the participle ("written", not "wrote")
        List<string> irregular = new List<string>();
        foreach (KeyValuePair<string, List<string>> entry in exceptions)
        {
            foreach (string item in entry.Value)
            {
                if (item == plain + "\tv" && !entry.Key.EndsWith("ing", StringComparison.Ordinal) && !entry.Key.EndsWith("s", StringComparison.Ordinal)) irregular.Add(entry.Key);
            }
        }
        irregular.Sort(StringComparer.Ordinal);
        string participle = irregular.FirstOrDefault(f => f.EndsWith("n", StringComparison.Ordinal)) ?? irregular.FirstOrDefault(f => !f.EndsWith("ed", StringComparison.Ordinal)) ?? irregular.FirstOrDefault();
        if (participle != null) return participle;
        if (plain.EndsWith("e", StringComparison.Ordinal)) return plain + "d";
        if (plain.Length > 2 && plain.EndsWith("y", StringComparison.Ordinal) && "aeiou".IndexOf(plain[plain.Length - 2]) < 0) return plain.Substring(0, plain.Length - 1) + "ied";
        return plain + "ed";
    }

    // Lefff packs its features: moods (P present, I imperfect, J simple past, F future, C conditional, S subjunctive,
    // T imperfect subjunctive, Y imperative, W infinitive, G present participle, K past participle), then persons (1 2 3),
    // then gender (m f) and number (s p). "PS13s" is the present indicative or subjunctive, first or third person, singular.
    // A wanted tag fits when each feature it names is one the form has
    public static bool Fits(string tag, string wanted)
    {
        if (tag == wanted) return true;
        HashSet<char> have = new HashSet<char>(tag);
        string moods = "PIJFCSTYWGK";
        foreach (char c in wanted)
        {
            if (!have.Contains(c)) return false;
        }
        // A wanted mood must not be missing a person or a number the form sets apart
        bool wantsMood = wanted.Any(c => moods.IndexOf(c) >= 0);
        bool hasMood = tag.Any(c => moods.IndexOf(c) >= 0);
        return wantsMood == hasMood;
    }

    // Meaning: the known words a word leads to through WordNet.
    // Breadth first from each sense, most frequent sense first; the relations kept are the ones that keep the meaning close
    // (synonym, hypernym, hyponym, also see, verb group, similar to). Ranked by hops, then by how frequent both senses are.
    public LambekRelated[] Related(string word, string language, string pos, ICollection<string> known, int hops)
    {
        return Related(word, language, pos, known, null, hops);
    }

    // The senses an action means: the synsets two of its own verbs share, in two languages ("delete" and "supprimer")
    // or in one ("list" and "enumerate"), and the synsets right next to them
    public string[] Core(string[] verbs, string[] languages, string pos)
    {
        Dictionary<int, HashSet<string>> byLanguage = new Dictionary<int, HashSet<string>>();
        Dictionary<int, HashSet<string>> byWord = new Dictionary<int, HashSet<string>>();
        for (int k = 0; k < verbs.Length; k++)
        {
            foreach (int id in SenseIds(Normalize(verbs[k]), languages[k], pos))
            {
                if (!byLanguage.ContainsKey(id)) { byLanguage[id] = new HashSet<string>(StringComparer.Ordinal); byWord[id] = new HashSet<string>(StringComparer.Ordinal); }
                byLanguage[id].Add(languages[k]);
                byWord[id].Add(languages[k] + ":" + Normalize(verbs[k]));
            }
        }
        // A sense is meant when half of the languages that have verbs for the action agree on it (one more language is
        // one more chance of a stray sense: "eliminar" also means to kill), or when two verbs of one language agree on it
        // (a wordnet linked apart from the others, like the German one, only agrees with itself)
        int spoken = byWord.Values.SelectMany(w => w).Select(w => w.Substring(0, w.IndexOf(':'))).Distinct().Count();
        int need = Math.Max(2, (spoken + 1) / 2);
        HashSet<int> meant = new HashSet<int>();
        foreach (int id in byLanguage.Keys)
        {
            if (byLanguage[id].Count >= need || (spoken <= 2 && byWord[id].Count >= 2)) meant.Add(id);
        }
        foreach (int id in byLanguage.Keys)
        {
            foreach (string language in byLanguage[id])
            {
                if (byWord[id].Count(w => w.StartsWith(language + ":", StringComparison.Ordinal)) >= 2) meant.Add(id);
            }
        }
        SortedSet<string> near = new SortedSet<string>(StringComparer.Ordinal);
        foreach (int id in meant)
        {
            near.Add(synsetNames[id]);
            if (links[id] == null) continue;
            foreach (int link in links[id])
            {
                if ((link >> 24) != 5) near.Add(synsetNames[link & 0xFFFFFF]);
            }
        }
        return near.ToArray();
    }

    // The senses of a word that are in a domain
    public string[] Within(string word, string language, string pos, string[] domain)
    {
        HashSet<string> set = new HashSet<string>(domain, StringComparer.Ordinal);
        return SenseIds(Normalize(word), language, pos).Select(id => synsetNames[id]).Where(set.Contains).ToArray();
    }

    // Only the senses a known word has in the domain count, when they are given (word -> synsets)
    public LambekRelated[] Related(string word, string language, string pos, ICollection<string> known, IDictionary<string, string[]> domain, int hops)
    {
        Dictionary<string, LambekRelated> best = new Dictionary<string, LambekRelated>(StringComparer.Ordinal);
        string plain = Normalize(word);
        foreach (LambekLemma lemma in Lemmas(word, language))
        {
            if (pos != null && pos.Length > 0 && lemma.Pos != pos) continue;

            // A form of a word it knows ("copied": copy) is that word
            if (lemma.Lemma != plain && known.Contains(lemma.Lemma))
            {
                Keep(best, new LambekRelated { Word = lemma.Lemma, From = lemma.Lemma, Synset = null, Relation = "form", Hops = 0, Rank = -1 });
            }

            int[] start = SenseIds(lemma.Lemma, language, lemma.Pos);
            for (int rank = 0; rank < start.Length; rank++)
            {
                Dictionary<int, int> distance = new Dictionary<int, int>();
                Dictionary<int, string> via = new Dictionary<int, string>();
                Queue<int> queue = new Queue<int>();
                distance[start[rank]] = 0;
                via[start[rank]] = "synonym";
                queue.Enqueue(start[rank]);
                while (queue.Count > 0)
                {
                    int synset = queue.Dequeue();
                    int d = distance[synset];
                    string synsetPos = synsetNames[synset].Substring(synsetNames[synset].Length - 1);
                    foreach (string member in MemberList(synset, language))
                    {
                        if (member == lemma.Lemma || !known.Contains(member)) continue;
                        string[] allowed;
                        if (domain != null && (!domain.TryGetValue(member, out allowed) || Array.IndexOf(allowed, synsetNames[synset]) < 0)) continue;
                        int place = Array.IndexOf(SenseIds(member, language, synsetPos), synset);
                        if (place < 0) place = 99;
                        Keep(best, new LambekRelated { Word = member, From = lemma.Lemma, Synset = synsetNames[synset], Relation = via[synset], Hops = d, Rank = rank + place });
                    }
                    if (d >= hops || links[synset] == null) continue;
                    foreach (int link in links[synset].OrderBy(l => l >> 24).ThenBy(l => synsetNames[l & 0xFFFFFF], StringComparer.Ordinal))
                    {
                        int kind = link >> 24;
                        int target = link & 0xFFFFFF;
                        if (kinds[kind] == "anti" || distance.ContainsKey(target)) continue;
                        distance[target] = d + 1;
                        via[target] = d == 0 ? kinds[kind] : via[synset] + "+" + kinds[kind];
                        queue.Enqueue(target);
                    }
                }
            }
        }
        return best.Values.OrderBy(r => r.Hops).ThenBy(r => r.Rank).ThenBy(r => r.Word, StringComparer.Ordinal).ToArray();
    }

    static void Keep(Dictionary<string, LambekRelated> best, LambekRelated candidate)
    {
        LambekRelated current;
        if (!best.TryGetValue(candidate.Word, out current) || Better(candidate, current)) best[candidate.Word] = candidate;
    }

    static bool Better(LambekRelated a, LambekRelated b)
    {
        if (a.Hops != b.Hops) return a.Hops < b.Hops;
        if (a.Rank != b.Rank) return a.Rank < b.Rank;
        return string.CompareOrdinal(a.Synset ?? "", b.Synset ?? "") < 0;
    }

    // Wu-Palmer similarity of two synsets: 2 depth(common ancestor) / (depth a + depth b), depths counted from a shared root
    public double WuPalmer(string a, string b)
    {
        int first, second;
        if (!synsetIds.TryGetValue(a, out first) || !synsetIds.TryGetValue(b, out second)) return 0;
        Dictionary<int, int> up = Ancestors(first);
        Dictionary<int, int> other = Ancestors(second);
        double best = 0;
        foreach (KeyValuePair<int, int> item in up)
        {
            int there;
            if (!other.TryGetValue(item.Key, out there)) continue;
            int depth = Depth(item.Key) + 1;
            double score = 2.0 * depth / (depth + item.Value + depth + there);
            if (score > best) best = score;
        }
        // Two roots of the verb forest meet only at the shared root
        if (best == 0) best = 2.0 / (Depth(first) + 2 + Depth(second) + 2);
        return best;
    }

    Dictionary<int, int> Ancestors(int synset)
    {
        // Every hypernym above the synset and its shortest distance
        Dictionary<int, int> found = new Dictionary<int, int>();
        Queue<int> queue = new Queue<int>();
        found[synset] = 0;
        queue.Enqueue(synset);
        while (queue.Count > 0)
        {
            int current = queue.Dequeue();
            if (links[current] == null) continue;
            foreach (int link in links[current])
            {
                int target = link & 0xFFFFFF;
                if ((link >> 24) != 0 || found.ContainsKey(target)) continue;
                found[target] = found[current] + 1;
                queue.Enqueue(target);
            }
        }
        return found;
    }

    int Depth(int synset)
    {
        // The longest way up to a root
        int best = 0;
        if (links[synset] == null) return 0;
        foreach (int link in links[synset])
        {
            if ((link >> 24) == 0) best = Math.Max(best, 1 + Depth(link & 0xFFFFFF));
        }
        return best;
    }
}
