using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.Json;

// One reading a word may have, as the lexicon says it: its part of speech, its lemma and its features, in the tags of
// Universal Dependencies
public class LambekLexiconEntry
{
    public string Upos;
    public string Lemma;
    public string Feats;
}

// The words of a language as a dictionary written by many people says them (Wiktionary, read by Wiktextract), turned
// into the tags of the treebanks by what the two were seen to say of the same words: "plural" is Number=Plur because
// the words Wiktionary calls plural are the ones the treebanks tag Number=Plur. Nothing in the turning is written by
// hand, and it is the same for every language
public class LambekLexicon
{
    public const string Format = "lambek-lexicon-1";

    // Form (in lower case) -> the readings it may have
    public readonly Dictionary<string, LambekLexiconEntry[]> Forms = new Dictionary<string, LambekLexiconEntry[]>(StringComparer.Ordinal);
    public string Source = "";

    public bool TryGet(string form, out LambekLexiconEntry[] entries)
    {
        return Forms.TryGetValue(form.ToLowerInvariant(), out entries);
    }

    // A word as Wiktextract gives it: what it was taken from (the headword, a "form of" sense, a table of forms), its
    // form, its lemma, its part of speech and its tags as Wiktionary names them
    public class Raw
    {
        public string Kind;
        public string Form;
        public string Lemma;
        public string Pos;
        public string[] Tags;
    }

    // Every word of a language in a file of Wiktextract (one entry a line, gzip or not)
    public static List<Raw> Extract(string path, string language)
    {
        List<Raw> raws = new List<Raw>();
        Stream stream = File.OpenRead(path);
        if (path.EndsWith(".gz", StringComparison.OrdinalIgnoreCase)) stream = new GZipStream(stream, CompressionMode.Decompress);
        using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
        {
            string line;
            while ((line = reader.ReadLine()) != null)
            {
                if (line.Length == 0) continue;
                using (JsonDocument document = JsonDocument.Parse(line))
                {
                    JsonElement entry = document.RootElement;
                    JsonElement value;
                    if (entry.TryGetProperty("lang_code", out value) && value.GetString() != language) continue;
                    if (!entry.TryGetProperty("word", out value)) continue;
                    string word = value.GetString();
                    string pos = entry.TryGetProperty("pos", out value) ? value.GetString() : "";
                    if (string.IsNullOrEmpty(word) || string.IsNullOrEmpty(pos) || word.Contains(" ")) continue;
                    bool formOnly = false;
                    if (entry.TryGetProperty("senses", out value) && value.ValueKind == JsonValueKind.Array)
                    {
                        foreach (JsonElement sense in value.EnumerateArray())
                        {
                            JsonElement of;
                            if (!sense.TryGetProperty("form_of", out of) || of.ValueKind != JsonValueKind.Array) continue;
                            string[] tags = Tags(sense);
                            foreach (JsonElement lemma in of.EnumerateArray())
                            {
                                JsonElement name;
                                if (!lemma.TryGetProperty("word", out name)) continue;
                                string lemmaWord = name.GetString();
                                if (string.IsNullOrEmpty(lemmaWord) || lemmaWord.Contains(" ")) continue;
                                raws.Add(new Raw { Kind = "of", Form = word, Lemma = lemmaWord, Pos = pos, Tags = tags });
                                formOnly = true;
                            }
                        }
                    }
                    if (!formOnly) raws.Add(new Raw { Kind = "head", Form = word, Lemma = word, Pos = pos, Tags = new string[0] });
                    if (entry.TryGetProperty("forms", out value) && value.ValueKind == JsonValueKind.Array)
                    {
                        foreach (JsonElement form in value.EnumerateArray())
                        {
                            JsonElement name;
                            if (!form.TryGetProperty("form", out name)) continue;
                            string written = name.GetString();
                            if (string.IsNullOrEmpty(written) || written.Contains(" ") || written == word) continue;
                            raws.Add(new Raw { Kind = "table", Form = written, Lemma = word, Pos = pos, Tags = Tags(form) });
                        }
                    }
                }
            }
        }
        return raws;
    }

    static string[] Tags(JsonElement element)
    {
        JsonElement tags;
        if (!element.TryGetProperty("tags", out tags) || tags.ValueKind != JsonValueKind.Array) return new string[0];
        return tags.EnumerateArray().Select(t => t.GetString()).Where(t => !string.IsNullOrEmpty(t)).Distinct(StringComparer.Ordinal).OrderBy(t => t, StringComparer.Ordinal).ToArray();
    }

    public static void WriteRaw(string path, IEnumerable<Raw> raws)
    {
        using (StreamWriter writer = new StreamWriter(new GZipStream(File.Create(path), CompressionLevel.Optimal), new UTF8Encoding(false)))
        {
            writer.NewLine = "\n";
            foreach (Raw raw in raws) writer.WriteLine(raw.Kind + "\t" + raw.Form + "\t" + raw.Lemma + "\t" + raw.Pos + "\t" + string.Join(",", raw.Tags));
        }
    }

    public static List<Raw> ReadRaw(string path) { return ReadRaw(path, null); }

    // (only the words whose form is one of those given, in lower case: the words a treebank has, to learn from)
    public static List<Raw> ReadRaw(string path, ISet<string> only)
    {
        List<Raw> raws = new List<Raw>();
        using (StreamReader reader = new StreamReader(new GZipStream(File.OpenRead(path), CompressionMode.Decompress), Encoding.UTF8))
        {
            string line;
            while ((line = reader.ReadLine()) != null)
            {
                string[] fields = line.Split('\t');
                if (fields.Length < 5) continue;
                if (only != null && !only.Contains(fields[1].ToLowerInvariant())) continue;
                raws.Add(new Raw { Kind = fields[0], Form = fields[1], Lemma = fields[2], Pos = fields[3], Tags = fields[4].Length == 0 ? new string[0] : fields[4].Split(',') });
            }
        }
        return raws;
    }

    // How Wiktionary's names turn into the tags of the treebanks, learned from the words both know: a part of speech
    // of Wiktionary is the UPOS most of its words are tagged with; a tag of Wiktionary is the one feature that tells
    // its words apart the most (met with nine in ten of them, at most half as often without it), learned from the
    // forms Wiktionary gives one reading of, met often enough to be sure; a tag that is no feature is kept when most
    // of the words with it are the forms of their lemma ("form-of"), else a word with it is left out ("diminutive")
    public class Mapping
    {
        public readonly SortedDictionary<string, string> Pos = new SortedDictionary<string, string>(StringComparer.Ordinal);
        public readonly SortedDictionary<string, string> Tags = new SortedDictionary<string, string>(StringComparer.Ordinal);
        public readonly SortedSet<string> Neutral = new SortedSet<string>(StringComparer.Ordinal);
    }

    // A word of a treebank: its form and lemma in lower case, its part of speech and its features
    public static Mapping Learn(IEnumerable<KeyValuePair<List<Raw>, List<LambekTreebankWord[]>>> languages, int least)
    {
        Dictionary<string, Dictionary<string, int>> posCounts = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
        Dictionary<string, Dictionary<string, int>> tagCounts = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
        Dictionary<string, int> tagSeen = new Dictionary<string, int>(StringComparer.Ordinal);
        Dictionary<string, int> tagLemma = new Dictionary<string, int>(StringComparer.Ordinal);
        List<KeyValuePair<List<Raw>, Dictionary<string, List<LambekTreebankWord>>>> indexed = new List<KeyValuePair<List<Raw>, Dictionary<string, List<LambekTreebankWord>>>>();
        foreach (KeyValuePair<List<Raw>, List<LambekTreebankWord[]>> language in languages)
        {
            Dictionary<string, List<LambekTreebankWord>> byForm = new Dictionary<string, List<LambekTreebankWord>>(StringComparer.Ordinal);
            foreach (LambekTreebankWord[] sentence in language.Value)
            {
                foreach (LambekTreebankWord word in sentence)
                {
                    string form = word.Form.ToLowerInvariant();
                    List<LambekTreebankWord> list;
                    if (!byForm.TryGetValue(form, out list)) byForm[form] = list = new List<LambekTreebankWord>();
                    if (list.Count < 50) list.Add(word);
                }
            }
            indexed.Add(new KeyValuePair<List<Raw>, Dictionary<string, List<LambekTreebankWord>>>(language.Key, byForm));
            foreach (Raw raw in language.Key)
            {
                List<LambekTreebankWord> seen;
                if (!byForm.TryGetValue(raw.Form.ToLowerInvariant(), out seen)) continue;
                string lemma = raw.Lemma.ToLowerInvariant();
                foreach (LambekTreebankWord word in seen)
                {
                    if (word.Lemma.ToLowerInvariant() != lemma) continue;
                    Add(posCounts, raw.Pos, word.Upos);
                }
            }
        }
        Mapping mapping = new Mapping();
        foreach (KeyValuePair<string, Dictionary<string, int>> pair in posCounts)
        {
            int total = pair.Value.Values.Sum();
            KeyValuePair<string, int> best = pair.Value.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal).First();
            if (total >= least && best.Value * 2 > total) mapping.Pos[pair.Key] = best.Key;
        }
        // (how often each feature is met in the words of each part of speech: a tag's feature must be met far more
        // with it than without it, "first-person" is Person=1, not VerbForm=Fin that every finite verb has)
        Dictionary<string, Dictionary<string, int>> baseCounts = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
        Dictionary<string, int> baseTotal = new Dictionary<string, int>(StringComparer.Ordinal);
        Dictionary<string, Dictionary<string, int>> tagUpos = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
        Dictionary<string, Dictionary<string, int>> tagUposFeature = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
        foreach (KeyValuePair<List<Raw>, Dictionary<string, List<LambekTreebankWord>>> language in indexed)
        {
            // (only the forms Wiktionary gives one reading of their lemma: a form of several, "spiele" both first
            // person and subjunctive, says not which its treebank words are)
            Dictionary<string, HashSet<string>> readings = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
            foreach (Raw raw in language.Key)
            {
                string key = raw.Form.ToLowerInvariant() + "\t" + raw.Lemma.ToLowerInvariant() + "\t" + raw.Pos;
                HashSet<string> set;
                if (!readings.TryGetValue(key, out set)) readings[key] = set = new HashSet<string>(StringComparer.Ordinal);
                set.Add(string.Join(",", raw.Tags));
            }
            HashSet<string> done = new HashSet<string>(StringComparer.Ordinal);
            foreach (Raw raw in language.Key)
            {
                string upos;
                List<LambekTreebankWord> seen;
                if (!mapping.Pos.TryGetValue(raw.Pos, out upos) || !language.Value.TryGetValue(raw.Form.ToLowerInvariant(), out seen)) continue;
                string lemma = raw.Lemma.ToLowerInvariant();
                string key = raw.Form.ToLowerInvariant() + "\t" + lemma + "\t" + raw.Pos;
                if (readings[key].Count != 1 || !done.Add(key)) continue;
                List<LambekTreebankWord> words = seen.Where(w => w.Upos == upos && w.Lemma.ToLowerInvariant() == lemma).ToList();
                bool same = seen.Any(w => w.Upos == upos);
                if (!same) continue;
                foreach (string tag in raw.Tags)
                {
                    int n;
                    tagSeen.TryGetValue(tag, out n); tagSeen[tag] = n + 1;
                    if (words.Count == 0) continue;
                    tagLemma.TryGetValue(tag, out n); tagLemma[tag] = n + 1;
                }
                // (each word of the treebank counts once for the tags and once for the base)
                foreach (LambekTreebankWord word in words)
                {
                    foreach (string tag in raw.Tags)
                    {
                        Add(tagUpos, tag, upos);
                        foreach (string feature in Features(word.Feats)) { Add(tagCounts, tag, feature); Add(tagUposFeature, tag + "\t" + upos, feature); }
                    }
                    int t; baseTotal.TryGetValue(upos, out t); baseTotal[upos] = t + 1;
                    foreach (string feature in Features(word.Feats)) Add(baseCounts, upos, feature);
                }
            }
        }
        foreach (KeyValuePair<string, int> pair in tagSeen)
        {
            int agreeing;
            tagLemma.TryGetValue(pair.Key, out agreeing);
            if (agreeing < least) continue;
            Dictionary<string, int> features;
            List<string> found = new List<string>();
            Dictionary<string, double> gap = new Dictionary<string, double>(StringComparer.Ordinal);
            int words = tagUpos.ContainsKey(pair.Key) ? tagUpos[pair.Key].Values.Sum() : 0;
            if (words > 0 && tagCounts.TryGetValue(pair.Key, out features))
            {
                int agreeingWords = words;
                // (the base: over the parts of speech the tag's words have, weighed as they are met with it)
                Dictionary<string, int> uposes = tagUpos[pair.Key];
                foreach (KeyValuePair<string, int> feature in features)
                {
                    if (feature.Value * 10 < agreeingWords * 9) continue;
                    // (and met at most half as often in the words of the same parts of speech without the tag:
                    // "masculine" is not Number=Plur, as many feminine words are plural too)
                    double without = 0;
                    foreach (KeyValuePair<string, int> upos in uposes)
                    {
                        int total; baseTotal.TryGetValue(upos.Key, out total);
                        Dictionary<string, int> counts; int count = 0;
                        if (baseCounts.TryGetValue(upos.Key, out counts)) counts.TryGetValue(feature.Key, out count);
                        Dictionary<string, int> mine; int withTag = 0, withFeature = 0;
                        if (tagUposFeature.TryGetValue(pair.Key + "\t" + upos.Key, out mine)) mine.TryGetValue(feature.Key, out withFeature);
                        withTag = upos.Value;
                        int rest = total - withTag;
                        if (rest > 0) without += (double) upos.Value / agreeingWords * Math.Max(0, count - withFeature) / rest;
                    }
                    double with = (double) feature.Value / agreeingWords;
                    if (without * 2 <= with && with - without >= 0.5) { found.Add(feature.Key); gap[feature.Key] = with - without; }
                }
            }
            // (one feature a tag: the one that tells its words apart the most, what is met with it far more than
            // without it; "first-person" is Person=1, not the Mood=Ind most first persons also have)
            if (found.Count > 0) { mapping.Tags[pair.Key] = found.OrderByDescending(f => gap[f]).ThenBy(f => f, StringComparer.Ordinal).First(); continue; }
            // (a tag that is no feature, kept when most of its words are the forms of the lemma it gives them)
            if (agreeing * 2 > pair.Value) mapping.Neutral.Add(pair.Key);
        }
        return mapping;
    }

    static string Shared(Dictionary<string, string> pool, string value)
    {
        string kept;
        if (pool.TryGetValue(value, out kept)) return kept;
        pool[value] = value;
        return value;
    }

    static IEnumerable<string> Features(string feats)
    {
        foreach (string feature in (feats ?? "_").Split('|')) { if (feature.Length > 0 && feature != "_") yield return feature; }
    }

    static void Add(Dictionary<string, Dictionary<string, int>> counts, string key, string value)
    {
        Dictionary<string, int> inner;
        if (!counts.TryGetValue(key, out inner)) counts[key] = inner = new Dictionary<string, int>(StringComparer.Ordinal);
        int n; inner.TryGetValue(value, out n); inner[value] = n + 1;
    }

    // The lexicon of a language: every word whose part of speech and tags all turn into the tags of the treebanks, when
    // the language is seen written so (attested in its sentences): a table may write what text does not (the stress of
    // "abbaiare" written on it), and a word never said is not one to read
    public static LambekLexicon Build(List<Raw> raws, Mapping mapping, ISet<string> attested)
    {
        Dictionary<string, SortedDictionary<string, LambekLexiconEntry>> found = new Dictionary<string, SortedDictionary<string, LambekLexiconEntry>>(StringComparer.Ordinal);
        foreach (Raw raw in raws)
        {
            string upos;
            if (!mapping.Pos.TryGetValue(raw.Pos, out upos)) continue;
            string form = raw.Form.ToLowerInvariant();
            if (!attested.Contains(form)) continue;
            SortedSet<string> features = new SortedSet<string>(StringComparer.Ordinal);
            bool kept = true;
            foreach (string tag in raw.Tags)
            {
                string feature;
                if (mapping.Tags.TryGetValue(tag, out feature)) { foreach (string one in feature.Split('|')) features.Add(one); }
                else if (!mapping.Neutral.Contains(tag)) { kept = false; break; }
            }
            if (!kept) continue;
            // (one value for each feature: two values of one say the word is two readings, kept apart by their tags)
            if (features.Select(f => f.Split('=')[0]).Distinct(StringComparer.Ordinal).Count() != features.Count) continue;
            string feats = features.Count == 0 ? "_" : string.Join("|", features);
            string key = upos + "\t" + raw.Lemma + "\t" + feats;
            SortedDictionary<string, LambekLexiconEntry> entries;
            if (!found.TryGetValue(form, out entries)) found[form] = entries = new SortedDictionary<string, LambekLexiconEntry>(StringComparer.Ordinal);
            entries[key] = new LambekLexiconEntry { Upos = upos, Lemma = raw.Lemma, Feats = feats };
        }
        LambekLexicon lexicon = new LambekLexicon();
        foreach (KeyValuePair<string, SortedDictionary<string, LambekLexiconEntry>> pair in found) lexicon.Forms[pair.Key] = pair.Value.Values.ToArray();
        return lexicon;
    }

    public void Save(string path)
    {
        using (StreamWriter writer = new StreamWriter(new GZipStream(File.Create(path), CompressionLevel.Optimal), new UTF8Encoding(false)))
        {
            writer.NewLine = "\n";
            writer.WriteLine("# " + Format + "\t" + Source);
            foreach (KeyValuePair<string, LambekLexiconEntry[]> pair in Forms.OrderBy(p => p.Key, StringComparer.Ordinal))
            {
                foreach (LambekLexiconEntry entry in pair.Value) writer.WriteLine(pair.Key + "\t" + entry.Upos + "\t" + entry.Lemma + "\t" + entry.Feats);
            }
        }
    }

    public static LambekLexicon Load(string path)
    {
        LambekLexicon lexicon = new LambekLexicon();
        Dictionary<string, List<LambekLexiconEntry>> forms = new Dictionary<string, List<LambekLexiconEntry>>(StringComparer.Ordinal);
        Dictionary<string, string> pool = new Dictionary<string, string>(StringComparer.Ordinal);
        using (StreamReader reader = new StreamReader(new GZipStream(File.OpenRead(path), CompressionMode.Decompress), Encoding.UTF8))
        {
            string line = reader.ReadLine();
            if (line == null || !line.StartsWith("# " + Format, StringComparison.Ordinal)) throw new InvalidDataException("Not a lexicon of Lambek: " + path);
            int tab = line.IndexOf('\t');
            lexicon.Source = tab >= 0 ? line.Substring(tab + 1) : "";
            while ((line = reader.ReadLine()) != null)
            {
                string[] fields = line.Split('\t');
                if (fields.Length < 4) continue;
                List<LambekLexiconEntry> list;
                if (!forms.TryGetValue(fields[0], out list)) forms[fields[0]] = list = new List<LambekLexiconEntry>();
                // (the parts of speech and features are few, said once; a lemma that is its form is the form)
                list.Add(new LambekLexiconEntry { Upos = Shared(pool, fields[1]), Lemma = fields[2] == fields[0] ? fields[0] : fields[2], Feats = Shared(pool, fields[3]) });
            }
        }
        foreach (KeyValuePair<string, List<LambekLexiconEntry>> pair in forms) lexicon.Forms[pair.Key] = pair.Value.ToArray();
        return lexicon;
    }
}
