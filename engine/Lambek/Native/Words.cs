// The words of a language as Lambek learned them (Forms.cs), offered the way the dictionaries offer theirs, so that
// every reader and every speaker of the engine may ask the one or the other: what a word may be (Lemmas), and how a
// lemma is said with given features (Forms), in the features the dictionaries of Lambek write (Lefff: "P2p" is the
// present, second person plural; "Kfs" the past participle, feminine singular; "ms" a masculine singular).
// What the dictionaries know and the treebanks do not (the meanings of WordNet, the definitions) is not here: a word's
// meaning is looked up elsewhere (step 5 of the roadmap), never made up.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

// What the readers and the speakers ask of the words of a language, whoever answers
public interface ILambekWords
{
    LambekLemma[] Lemmas(string word, string language);
    LambekLemma[] Lemmas(string word, string language, bool exact);
    string[] Forms(string lemma, string language, string pos, string tag);
    string[] Senses(string lemma, string language, string pos);
}

public class LambekLearnedWords : ILambekWords
{
    public readonly LambekForms Model;
    public readonly string Language;
    public readonly HashSet<string> Languages = new HashSet<string>(StringComparer.Ordinal);
    public bool HasGlosses { get { return false; } }
    Dictionary<string, List<string>> plainForms;

    public LambekLearnedWords(LambekForms model, string language)
    {
        Model = model;
        Language = language;
        Languages.Add(language);
    }

    // The parts of speech of the treebanks, as the dictionaries name them
    public static string Pos(string upos)
    {
        switch (upos)
        {
            case "VERB": return "v";
            case "AUX": return "v";
            case "NOUN": return "n";
            case "PROPN": return "np";
            case "ADJ": return "a";
            case "ADV": return "r";
            case "DET": return "det";
            case "ADP": return "prep";
            case "PRON": return "pro";
            case "CCONJ": return "coo";
            case "SCONJ": return "csu";
            case "NUM": return "num";
            case "INTJ": return "intj";
            default: return upos.ToLowerInvariant();
        }
    }

    static Dictionary<string, string> Parse(string feats)
    {
        Dictionary<string, string> found = new Dictionary<string, string>(StringComparer.Ordinal);
        if (string.IsNullOrEmpty(feats) || feats == "_") return found;
        foreach (string feature in feats.Split('|'))
        {
            int equal = feature.IndexOf('=');
            if (equal > 0) found[feature.Substring(0, equal)] = feature.Substring(equal + 1);
        }
        return found;
    }

    // The features of the treebanks written as the dictionaries write them: the mood (P present, I imperfect, J simple
    // past, F future, C conditional, S subjunctive, T imperfect subjunctive, Y imperative, W infinitive, G present
    // participle, K past participle), the person, then the gender and the number
    public static string Lefff(string upos, string feats)
    {
        Dictionary<string, string> f = Parse(feats);
        StringBuilder tag = new StringBuilder();
        string value;
        if (upos == "VERB" || upos == "AUX")
        {
            string mood = f.TryGetValue("Mood", out value) ? value : null;
            string tense = f.TryGetValue("Tense", out value) ? value : null;
            string form = f.TryGetValue("VerbForm", out value) ? value : null;
            if (form == "Inf") tag.Append('W');
            // (the treebanks give a past participle its gender and number, often without its tense)
            else if (form == "Part") tag.Append(tense == "Pres" || (tense == null && !f.ContainsKey("Gender") && !f.ContainsKey("Number")) ? 'G' : 'K');
            else if (mood == "Imp") tag.Append('Y');
            else if (mood == "Cnd") tag.Append('C');
            else if (mood == "Sub") tag.Append(tense == "Imp" ? 'T' : 'S');
            else if (mood == "Ind" || form == "Fin")
            {
                switch (tense)
                {
                    case "Imp": tag.Append('I'); break;
                    case "Past": tag.Append('J'); break;
                    case "Fut": tag.Append('F'); break;
                    default: tag.Append('P'); break;
                }
            }
            if (f.TryGetValue("Person", out value)) tag.Append(value);
        }
        if (f.TryGetValue("Gender", out value)) { if (value == "Masc") tag.Append('m'); else if (value == "Fem") tag.Append('f'); }
        if (f.TryGetValue("Number", out value)) { if (value == "Sing") tag.Append('s'); else if (value == "Plur") tag.Append('p'); }
        return tag.ToString();
    }

    // A tag of the dictionaries read back as the features of the treebanks, to find a form: only what it says
    public static string Features(string pos, string tag)
    {
        List<string> wanted = new List<string>();
        foreach (char c in tag ?? "")
        {
            switch (c)
            {
                case 'P': wanted.Add("Mood=Ind"); wanted.Add("Tense=Pres"); break;
                case 'I': wanted.Add("Mood=Ind"); wanted.Add("Tense=Imp"); break;
                case 'J': wanted.Add("Mood=Ind"); wanted.Add("Tense=Past"); break;
                case 'F': wanted.Add("Mood=Ind"); wanted.Add("Tense=Fut"); break;
                case 'C': wanted.Add("Mood=Cnd"); break;
                case 'S': wanted.Add("Mood=Sub"); wanted.Add("Tense=Pres"); break;
                case 'T': wanted.Add("Mood=Sub"); wanted.Add("Tense=Imp"); break;
                case 'Y': wanted.Add("Mood=Imp"); break;
                case 'W': wanted.Add("VerbForm=Inf"); break;
                case 'G': wanted.Add("VerbForm=Part"); break;
                case 'K': wanted.Add("VerbForm=Part"); break;
                case '1': case '2': case '3': wanted.Add("Person=" + c); break;
                case 'm': wanted.Add("Gender=Masc"); break;
                case 'f': wanted.Add("Gender=Fem"); break;
                case 's': wanted.Add("Number=Sing"); break;
                case 'p': wanted.Add("Number=Plur"); break;
            }
        }
        wanted.Sort(StringComparer.Ordinal);
        return string.Join("|", wanted.Distinct());
    }

    static string[] Upos(string pos)
    {
        switch (pos)
        {
            case "v": return new[] { "VERB" };
            case "n": return new[] { "NOUN" };
            case "np": return new[] { "PROPN" };
            case "a": return new[] { "ADJ" };
            case "r": return new[] { "ADV" };
            case "det": return new[] { "DET" };
            case "pro": return new[] { "PRON" };
            default:
                if (pos != null && pos.StartsWith("aux", StringComparison.Ordinal)) return new[] { "VERB" };
                return new[] { (pos ?? "").ToUpperInvariant() };
        }
    }

    // The forms seen, by their letters without accents ("etes": êtes)
    List<string> SeenForms(string word, bool exact)
    {
        string lower = word.ToLowerInvariant();
        if (exact) return Model.Tags.ContainsKey(lower) ? new List<string> { lower } : new List<string>();
        if (plainForms == null)
        {
            Dictionary<string, List<string>> built = new Dictionary<string, List<string>>(StringComparer.Ordinal);
            foreach (string form in Model.Tags.Keys)
            {
                string plain = LambekDictionary.Normalize(form);
                List<string> list;
                if (!built.TryGetValue(plain, out list)) built[plain] = list = new List<string>();
                list.Add(form);
            }
            plainForms = built;
        }
        List<string> found;
        if (plainForms.TryGetValue(LambekDictionary.Normalize(lower), out found)) return found;
        return new List<string>();
    }

    public LambekLemma[] Lemmas(string word, string language) { return Lemmas(word, language, false); }

    // What a word may be, out of any sentence: every reading it was seen with often enough; a word never seen, what
    // the model reads in it from its ends
    // (what a word may be is asked many times a message: kept, until the model learns again)
    readonly Dictionary<string, LambekLemma[]> known = new Dictionary<string, LambekLemma[]>(StringComparer.Ordinal);
    int knownVersion;

    public LambekLemma[] Lemmas(string word, string language, bool exact)
    {
        if (knownVersion != Model.Version) { known.Clear(); knownVersion = Model.Version; }
        string key = (exact ? "1" : "0") + language + "\t" + word;
        LambekLemma[] kept;
        if (!known.TryGetValue(key, out kept))
        {
            kept = Find(word, language, exact);
            if (known.Count > 50000) known.Clear();
            known[key] = kept;
        }
        return (LambekLemma[]) kept.Clone();
    }

    LambekLemma[] Find(string word, string language, bool exact)
    {
        List<LambekLemma> found = new List<LambekLemma>();
        if (string.IsNullOrEmpty(word) || language != Language || word.IndexOf('_') >= 0 || word.IndexOf(' ') >= 0) return found.ToArray();
        HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
        List<string> forms = SeenForms(word, exact);
        foreach (string form in forms)
        {
            foreach (string tag in Model.Tags[form])
            {
                int bar = tag.IndexOf('|');
                string upos = bar >= 0 ? tag.Substring(0, bar) : tag;
                string feats = bar >= 0 ? tag.Substring(bar + 1) : "_";
                if (upos == "PUNCT" || upos == "SYM" || upos == "X") continue;
                Add(found, seen, Model.LemmaFor(form, tag), upos, feats);
            }
        }
        // A word seen too seldom to keep its readings: what it was each time it was seen ("volent": voler)
        if (found.Count == 0)
        {
            List<string[]> heard;
            if (Model.Heard().TryGetValue(exact ? word.ToLowerInvariant() : LambekDictionary.Normalize(word), out heard))
            {
                foreach (string[] reading in heard)
                {
                    if (exact && reading[0] != word.ToLowerInvariant()) continue;
                    Add(found, seen, reading[2], reading[1], reading[3]);
                }
            }
        }
        // A word never seen: what it may be, found by saying it, then what the model reads in it
        if (found.Count == 0)
        {
            foreach (LambekFormReading reading in Model.Analyze(word)) Add(found, seen, reading.Lemma, reading.Upos, reading.Feats);
            LambekFormReading[] read = found.Count > 0 ? new LambekFormReading[0] : Model.Read(new[] { word });
            if (read.Length == 1 && read[0].Upos != "PUNCT" && read[0].Upos != "SYM" && read[0].Upos != "X")
            {
                Add(found, seen, read[0].Lemma, read[0].Upos, read[0].Feats);
                if (read[0].Alternative != null && !read[0].Alternative.StartsWith("AUX|", StringComparison.Ordinal))
                {
                    int bar = read[0].Alternative.IndexOf('|');
                    Add(found, seen, Model.LemmaFor(word, read[0].Alternative), read[0].Alternative.Substring(0, bar), read[0].Alternative.Substring(bar + 1));
                }
            }
        }
        return found.ToArray();
    }

    static void Add(List<LambekLemma> found, HashSet<string> seen, string lemma, string upos, string feats)
    {
        string tag = Lefff(upos, feats);
        string plain = LambekDictionary.Normalize(lemma);
        foreach (string pos in upos == "AUX" ? new[] { "aux", "v" } : new[] { Pos(upos) })
        {
            if (seen.Add(plain + "\t" + pos + "\t" + tag)) found.Add(new LambekLemma { Lemma = plain, Shown = lemma, Pos = pos, Tag = tag });
        }
    }

    // How a lemma is said with the features asked, learned from the paradigms of the treebanks
    public string[] Forms(string lemma, string language, string pos, string tag)
    {
        if (string.IsNullOrEmpty(lemma) || language != Language) return new string[0];
        string wanted = Features(pos, tag);
        foreach (string upos in Upos(pos))
        {
            string[] forms = Model.Inflect(lemma, upos, wanted);
            if (forms.Length > 0) return forms;
        }
        return new string[0];
    }

    // The past participle of a verb, to say what was done
    public string Participle(string lemma, string language)
    {
        string[] forms = language == "fr" ? Forms(lemma, language, "v", "Kms") : Model.Inflect(lemma, "VERB", "Tense=Past|VerbForm=Part");
        return forms.Length > 0 ? forms[0] : null;
    }

    // The meanings are not learned from treebanks: nothing is said of them here
    public string[] Senses(string lemma, string language, string pos) { return new string[0]; }
    public string[] Members(string synset, string language) { return new string[0]; }
    public string[] Links(string synset) { return new string[0]; }
    public string[] Written(string synset, string language) { return new string[0]; }
    public string Gloss(string synset) { return null; }
    // Typing slips: the words seen often enough (twice at least) one edit away from a word that is none of them,
    // compared without accents, as the dictionaries find them. At most max + 1, so one more than max says there are
    // too many to choose from
    string[] plainSeen;
    public string[] Near(string word, string language, int max)
    {
        List<string> found = new List<string>();
        if (language != Language || string.IsNullOrEmpty(word)) return found.ToArray();
        string form = LambekDictionary.Normalize(word);
        if (plainSeen == null)
        {
            SortedSet<string> letters = new SortedSet<string>(StringComparer.Ordinal);
            foreach (string seen in Model.Tags.Keys)
            {
                if (Model.Tags[seen].Length == 0) continue;
                string plain = LambekDictionary.Normalize(seen);
                if (plain.Length > 0 && plain.All(char.IsLetter)) letters.Add(plain);
            }
            plainSeen = letters.ToArray();
        }
        if (Array.BinarySearch(plainSeen, form, StringComparer.Ordinal) >= 0) return found.ToArray();
        foreach (string seen in plainSeen)
        {
            if (Math.Abs(seen.Length - form.Length) > 1 || !LambekDictionary.OneEdit(seen, 0, seen.Length, form)) continue;
            found.Add(seen);
            if (found.Count > max) break;
        }
        return found.ToArray();
    }
    public string[] Core(string[] verbs, string[] languages, string pos) { return new string[0]; }
    public string[] Within(string word, string language, string pos, string[] domain) { return new string[0]; }
    public LambekRelated[] Related(string word, string language, string pos, ICollection<string> known, int hops) { return new LambekRelated[0]; }
    public LambekRelated[] Related(string word, string language, string pos, ICollection<string> known, IDictionary<string, string[]> domain, int hops) { return new LambekRelated[0]; }
    public double WuPalmer(string a, string b) { return 0; }
    public bool Ensure(string path) { return true; }
}
