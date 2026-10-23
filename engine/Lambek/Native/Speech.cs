// How Lambek speaks: the rules that make a sentence right (contractions, elisions, agreement, plural after a number),
// the register of the user (tu or vous), and variety without chance (a stable hash picks among equal phrasings).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

public static class LambekSpeech
{
    // Stable hash: FNV-1a over UTF-8 (String.GetHashCode changes from one process to the next)
    public static ulong Hash(string text)
    {
        ulong hash = 14695981039346656037UL;
        foreach (byte b in Encoding.UTF8.GetBytes(text ?? ""))
        {
            hash ^= b;
            hash *= 1099511628211UL;
        }
        return hash;
    }

    // One of n equal phrasings: H(key) mod n, then the next one not used in the last turns
    public static int Pick(string key, int count, int[] recent)
    {
        if (count <= 1) return 0;
        int start = (int)(Hash(key) % (ulong)count);
        HashSet<int> used = new HashSet<int>(recent ?? new int[0]);
        for (int k = 0; k < count; k++)
        {
            int index = (start + k) % count;
            if (!used.Contains(index)) return index;
        }
        return start;
    }

    // "{0:fichier|fichiers}": the form the number asks for. In French 0 and 1 take the singular, in English only 1
    public static string Plural(string text, string language, long[] numbers)
    {
        return Regex.Replace(text, @"\{(?<n>\d+):(?<one>[^|{}]*)\|(?<many>[^{}]*)\}", m =>
        {
            int index = int.Parse(m.Groups["n"].Value, CultureInfo.InvariantCulture);
            long n = index < numbers.Length ? numbers[index] : 2;
            bool one = language == "fr" ? (n == 0 || n == 1 || n == -1) : (n == 1 || n == -1);
            return one ? m.Groups["one"].Value : m.Groups["many"].Value;
        });
    }

    // Tokens: words Lambek may change, and everything else (quotes, paths, names, numbers) kept exactly
    class Token
    {
        public string Text;
        public bool Word;
    }

    static List<Token> Split(string text)
    {
        List<Token> tokens = new List<Token>();
        // Quoted parts first, then items with a path, a dot or a digit, then words, then the rest one character at a time
        // (a dot counts only inside a name: "archive.zip", ".log", never the period that ends a sentence)
        Regex pattern = new Regex(@"«[^»]*»|""[^""]*""|“[^”]*”|`[^`]*`|(?=[^\s«»""]*(?:[\\/:@\p{N}]|\.[\p{L}\p{N}_]))(?:[\p{L}\p{M}\p{N}_~$@\\/:+-]|\.(?=[\p{L}\p{N}_]))+|[\p{L}\p{M}]+|\s+|.", RegexOptions.Singleline);
        foreach (Match m in pattern.Matches(text))
        {
            string value = m.Value;
            bool word = Regex.IsMatch(value, @"^[\p{L}\p{M}]+$");
            tokens.Add(new Token { Text = value, Word = word });
        }
        return tokens;
    }

    static string Join(List<Token> tokens)
    {
        StringBuilder builder = new StringBuilder();
        foreach (Token token in tokens) builder.Append(token.Text);
        return builder.ToString();
    }

    static int Next(List<Token> tokens, int at)
    {
        // The next token that is not a space
        for (int k = at + 1; k < tokens.Count; k++)
        {
            if (!string.IsNullOrWhiteSpace(tokens[k].Text)) return k;
        }
        return -1;
    }

    static int Previous(List<Token> tokens, int at)
    {
        for (int k = at - 1; k >= 0; k--)
        {
            if (!string.IsNullOrWhiteSpace(tokens[k].Text)) return k;
        }
        return -1;
    }

    static bool OnlySpace(List<Token> tokens, int from, int to)
    {
        for (int k = from + 1; k < to; k++)
        {
            if (!string.IsNullOrWhiteSpace(tokens[k].Text)) return false;
        }
        return true;
    }

    static string Case(string model, string value)
    {
        // Keep a capital first letter
        if (model.Length > 0 && value.Length > 0 && char.IsUpper(model[0])) return char.ToUpperInvariant(value[0]) + value.Substring(1);
        return value;
    }

    // After a number and its noun, words that never agree: "2 fois plus de livres"
    static readonly HashSet<string> Invariable = new HashSet<string>(StringComparer.Ordinal) { "plus", "moins", "autant", "de", "que" };

    // Between a number and its noun: "2 more cats", "3 fewer files"
    static readonly HashSet<string> Comparatives = new HashSet<string>(StringComparer.Ordinal) { "more", "fewer", "less" };

    // A number after these names a thing ("step 1 changes"), it does not count one
    static readonly HashSet<string> naming = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "step", "steps", "étape", "étapes", "version", "page", "line", "ligne", "chapter", "chapitre", "level", "niveau",
        "windows", "number", "numéro", "no", "n°", "item", "option", "article", "section", "partie", "part"
    };

    static bool Names(List<Token> tokens, int at)
    {
        int back = Previous(tokens, at);
        return back >= 0 && naming.Contains(tokens[back].Text);
    }

    // A number before the name of a month is a day, not a count: "le 26 février" stays as it is
    static readonly HashSet<string> months = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"
    };

    static readonly HashSet<string> pronouns = new HashSet<string>(StringComparer.Ordinal)
    {
        "je", "j'", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles", "ne", "n'", "me", "te", "se"
    };

    static readonly HashSet<string> aspirated = new HashSet<string>(StringComparer.Ordinal)
    {
        "hache", "haie", "haine", "haïr", "halte", "hamac", "hameau", "hanche", "handicap", "hangar", "hanter", "harceler",
        "hardi", "haricot", "harpe", "hasard", "hâte", "hausse", "haut", "hauteur", "héros", "hérisson", "hêtre", "hibou",
        "hiérarchie", "hockey", "homard", "honte", "hors", "housse", "huit", "huitième", "hurler", "hutte"
    };

    static bool StartsWithVowel(string word)
    {
        if (word.Length == 0) return false;
        string lower = word.ToLowerInvariant();
        string plain = LambekDictionary.Normalize(lower);
        if (lower[0] == 'h') return !aspirated.Contains(lower) && !aspirated.Contains(plain) && plain.Length > 1 && "aeiouy".IndexOf(plain[1]) >= 0;
        return "aeiouy".IndexOf(plain[0]) >= 0;
    }

    // French and English rules, applied to what Lambek says (never inside a quote, a path or a name)
    public static string Polish(string text, string language, ILambekWords dictionary)
    {
        if (string.IsNullOrEmpty(text)) return text;
        List<Token> tokens = Split(text);
        if (language == "fr") PolishFrench(tokens, dictionary);
        if (language == "en") PolishEnglish(tokens, dictionary);
        return Join(tokens);
    }

    static void PolishFrench(List<Token> tokens, ILambekWords dictionary)
    {
        // Number before a noun: 0 and 1 take the singular, 2 and more the plural
        for (int i = 0; i < tokens.Count; i++)
        {
            long n;
            if (!long.TryParse(tokens[i].Text, NumberStyles.Integer, CultureInfo.InvariantCulture, out n) || Names(tokens, i)) continue;
            int next = Next(tokens, i);
            if (next < 0 || !tokens[next].Word || !OnlySpace(tokens, i, next) || dictionary == null) continue;
            if (months.Contains(tokens[next].Text)) continue;
            // Units and names ("Go", "Mo") stay as they are
            if (tokens[next].Text != tokens[next].Text.ToLowerInvariant() || tokens[next].Text.Length < 3) continue;
            string number = (n == 0 || n == 1) ? "s" : "p";
            // The last group of a number written in groups ("2 100 000 habitants") is not the number
            if (i >= 2 && (tokens[i - 1].Text == "\u00A0" || tokens[i - 1].Text == "\u202F") && Regex.IsMatch(tokens[i - 2].Text, @"^\p{N}+$")) number = "p";
            string noun = Inflect(dictionary, tokens[next].Text, "n", null, number);
            if (noun == null) continue;
            string gender = Gender(dictionary, noun);
            tokens[next].Text = Case(tokens[next].Text, noun);
            // And the participle or adjective right after it ("1 élément concerné")
            int after = Next(tokens, next);
            // ("2 fois plus de livres": "plus" says how they compare, it agrees with nothing)
            if (after > 0 && Invariable.Contains(tokens[after].Text.ToLowerInvariant())) continue;
            if (after > 0 && tokens[after].Word && OnlySpace(tokens, next, after))
            {
                string agreed = Agree(dictionary, tokens[after].Text, gender, number);
                if (agreed != null) tokens[after].Text = Case(tokens[after].Text, agreed);
            }
        }

        // Determiners agree with their noun; a participle or adjective after a noun agrees with it
        if (dictionary != null)
        {
            Dictionary<string, string[]> determiners = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
            {
                { "un", new[] { "un", "une" } }, { "une", new[] { "un", "une" } },
                { "le", new[] { "le", "la" } }, { "la", new[] { "le", "la" } },
                { "ce", new[] { "ce", "cette" } }, { "cet", new[] { "cet", "cette" } }, { "cette", new[] { "ce", "cette" } },
                { "du", new[] { "du", "de la" } }, { "au", new[] { "au", "à la" } },
                { "nouveau", new[] { "nouveau", "nouvelle" } }, { "nouvelle", new[] { "nouveau", "nouvelle" } }
            };
            HashSet<string> degrees = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "plus", "moins", "tres", "très", "si", "aussi" };
            for (int i = 0; i < tokens.Count; i++)
            {
                if (!tokens[i].Word) continue;
                string[] pair;
                if (determiners.TryGetValue(tokens[i].Text, out pair))
                {
                    int next = Next(tokens, i);
                    if (next < 0 || !tokens[next].Word || !OnlySpace(tokens, i, next)) continue;
                    // "le" and "la" before a verb are pronouns ("je la copie"): only an article agrees
                    string low = tokens[i].Text.ToLowerInvariant();
                    int earlier = Previous(tokens, i);
                    if ((low == "le" || low == "la") && earlier >= 0 && pronouns.Contains(tokens[earlier].Text.ToLowerInvariant())) continue;
                    // A name keeps the article it was given ("la Suisse" is no Swiss man)
                    if (char.IsUpper(tokens[next].Text[0])) continue;
                    // Before "plus" or "moins" the article is that of the noun said before it ("la ville la plus peuplee")
                    if (degrees.Contains(tokens[next].Text)) continue;
                    string gender = NounGender(dictionary, tokens[next].Text);
                    if (gender == null) continue;
                    string chosen = gender == "f" ? pair[1] : pair[0];
                    if (chosen == "ce" && StartsWithVowel(tokens[next].Text)) chosen = "cet";
                    tokens[i].Text = Case(tokens[i].Text, chosen);
                    continue;
                }

                // Past participle after a noun, with at most one unknown word between them ("une classe PowerShell nommée")
                string participle = tokens[i].Text;
                if (!IsParticiple(dictionary, participle)) continue;
                int back = Previous(tokens, i);
                if (back < 0) continue;
                // ("la route est mouillee": "est" is a verb there, not the east; a participle after "etre" or "avoir" is left as it was written)
                if (tokens[back].Word && IsBeOrHave(dictionary, tokens[back].Text)) continue;
                if (!tokens[back].Word || NounGender(dictionary, tokens[back].Text) == null)
                {
                    // One name between them, like PowerShell
                    int before = back > 0 ? Previous(tokens, back) : -1;
                    if (before < 0 || !tokens[before].Word || NounGender(dictionary, tokens[before].Text) == null || tokens[back].Text.Length == 0 || !char.IsUpper(tokens[back].Text[0])) continue;
                    back = before;
                }
                string nounGender = NounGender(dictionary, tokens[back].Text);
                string nounNumber = NounNumber(dictionary, tokens[back].Text);
                if (nounGender == null || nounNumber == null) continue;
                string form = Agree(dictionary, participle, nounGender, nounNumber);
                if (form != null) tokens[i].Text = Case(participle, form);
            }
        }

        // Contractions: de le, de les, à le, à les
        for (int i = 0; i < tokens.Count; i++)
        {
            if (!tokens[i].Word) continue;
            string lower = tokens[i].Text.ToLowerInvariant();
            if (lower != "de" && lower != "à") continue;
            int next = Next(tokens, i);
            if (next < 0 || !tokens[next].Word || !OnlySpace(tokens, i, next)) continue;
            string article = tokens[next].Text.ToLowerInvariant();
            int after = Next(tokens, next);
            // "de le" before a vowel stays "de l'"
            if (article == "le" && after > 0 && tokens[after].Word && StartsWithVowel(tokens[after].Text)) continue;
            string merged = null;
            if (lower == "de" && article == "le") merged = "du";
            if (lower == "de" && article == "les") merged = "des";
            if (lower == "à" && article == "le") merged = "au";
            if (lower == "à" && article == "les") merged = "aux";
            if (merged == null) continue;
            tokens[i].Text = Case(tokens[i].Text, merged);
            tokens[next].Text = "";
            for (int k = i + 1; k < next; k++) tokens[k].Text = "";
        }

        // Elisions before a vowel or a mute h: le, la, de, que, je, ne, me, te, se, si il
        HashSet<string> elided = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "le", "la", "de", "que", "je", "ne", "me", "te", "se", "jusque", "lorsque", "puisque" };
        for (int i = 0; i < tokens.Count; i++)
        {
            if (!tokens[i].Word) continue;
            int next = Next(tokens, i);
            if (next < 0 || !OnlySpace(tokens, i, next) || next != i + 2) continue;
            string word = tokens[i].Text;
            string lower = word.ToLowerInvariant();
            string following = tokens[next].Text;
            bool vowel = following.Length > 0 && char.IsLetter(following[0]) && StartsWithVowel(Regex.Match(following, @"^[\p{L}\p{M}]+").Value);
            if (lower == "si" && (tokens[next].Text == "il" || tokens[next].Text == "ils"))
            {
                tokens[i].Text = Case(word, "s'");
                tokens[i + 1].Text = "";
                continue;
            }
            if (!elided.Contains(lower) || !vowel) continue;
            // "le un" of a number, and the pronoun after a verb ("donnez-le") stay whole
            if (i > 0 && tokens[i - 1].Text == "-") continue;
            tokens[i].Text = word.Substring(0, word.Length - 1) + "'";
            tokens[i + 1].Text = "";
        }
    }

    static void PolishEnglish(List<Token> tokens, ILambekWords dictionary)
    {
        // "a" before a vowel sound is "an"; "an" before a consonant is "a"
        HashSet<string> consonantSound = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "user", "use", "usb", "unicode", "unique", "unit", "url", "one", "once", "european", "uniform" };
        HashSet<string> vowelSound = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "hour", "honest", "honor", "honour", "heir", "mp3", "mp4", "html", "xml", "sql", "exe", "svg", "mkv" };
        for (int i = 0; i < tokens.Count; i++)
        {
            string lower = tokens[i].Text.ToLowerInvariant();
            if (!tokens[i].Word || (lower != "a" && lower != "an")) continue;
            int next = Next(tokens, i);
            if (next < 0 || !OnlySpace(tokens, i, next)) continue;
            string word = tokens[next].Text.TrimStart('.', '"', '«', '“');
            if (word.Length == 0 || !char.IsLetter(word[0])) continue;
            string plain = word.ToLowerInvariant();
            bool vowel = "aeiou".IndexOf(plain[0]) >= 0;
            if (consonantSound.Contains(plain)) vowel = false;
            if (vowelSound.Contains(plain)) vowel = true;
            tokens[i].Text = Case(tokens[i].Text, vowel ? "an" : "a");
        }

        // A number before a noun: 1 takes the singular, every other number the plural
        for (int i = 0; i < tokens.Count; i++)
        {
            long n;
            if (!long.TryParse(tokens[i].Text, NumberStyles.Integer, CultureInfo.InvariantCulture, out n) || Names(tokens, i)) continue;
            int next = Next(tokens, i);
            if (next < 0 || !tokens[next].Word || !OnlySpace(tokens, i, next)) continue;
            string word = tokens[next].Text;
            // "2 more cats": the word after the number only says how they compare, the noun comes after it
            if (Comparatives.Contains(word.ToLowerInvariant())) continue;
            if (n == 1 && word.EndsWith("s", StringComparison.Ordinal) && !word.EndsWith("ss", StringComparison.Ordinal) && dictionary != null)
            {
                LambekLemma noun = dictionary.Lemmas(word, "en", true).FirstOrDefault(l => l.Pos == "n" && l.Lemma != LambekDictionary.Normalize(word));
                if (noun != null) tokens[next].Text = Case(word, noun.Lemma);
            }
            else if (n != 1 && dictionary != null && word == word.ToLowerInvariant() && word.Length > 2 && !word.EndsWith("s", StringComparison.Ordinal) && dictionary.Senses(word, "en", "n").Length > 0)
            {
                if (Regex.IsMatch(word, "[^aeiou]y$")) tokens[next].Text = word.Substring(0, word.Length - 1) + "ies";
                else tokens[next].Text = word + (Regex.IsMatch(word, "(s|x|z|ch|sh)$") ? "es" : "s");
            }
        }
    }

    // French words through Lefff
    static string NounGender(ILambekWords dictionary, string word)
    {
        // Only a word Lefff reads as a noun and in one gender (Lefff writes "soeur" where the user writes "s\u0153ur")
        HashSet<string> genders = new HashSet<string>(StringComparer.Ordinal);
        foreach (string form in Ligatures(word))
        {
            foreach (LambekLemma lemma in dictionary.Lemmas(form, "fr", true))
            {
                if (lemma.Pos != "n") continue;
                if (lemma.Tag.Contains('m')) genders.Add("m");
                if (lemma.Tag.Contains('f')) genders.Add("f");
            }
        }
        return genders.Count == 1 ? genders.First() : null;
    }

    static IEnumerable<string> Ligatures(string word)
    {
        yield return word;
        string open = word.Replace("\u0153", "oe").Replace("\u0152", "Oe").Replace("\u00E6", "ae").Replace("\u00C6", "Ae");
        if (open != word) yield return open;
    }

    static string NounNumber(ILambekWords dictionary, string word)
    {
        HashSet<string> numbers = new HashSet<string>(StringComparer.Ordinal);
        foreach (LambekLemma lemma in dictionary.Lemmas(word, "fr", true))
        {
            if (lemma.Pos != "n") continue;
            if (lemma.Tag.Contains('s')) numbers.Add("s");
            if (lemma.Tag.Contains('p')) numbers.Add("p");
        }
        return numbers.Count == 1 ? numbers.First() : null;
    }

    static string Gender(ILambekWords dictionary, string noun)
    {
        return NounGender(dictionary, noun) ?? "m";
    }

    static bool IsBeOrHave(ILambekWords dictionary, string word)
    {
        // A form of "etre" or "avoir", the verbs a participle follows
        foreach (LambekLemma lemma in dictionary.Lemmas(word.ToLowerInvariant(), "fr"))
        {
            if ((lemma.Pos == "v" || lemma.Pos.StartsWith("aux", StringComparison.Ordinal)) && (lemma.Lemma == "etre" || lemma.Lemma == "\u00eatre" || lemma.Lemma == "avoir")) return true;
        }
        return false;
    }

    static bool IsParticiple(ILambekWords dictionary, string word)
    {
        // Only a word that is nothing but a participle or an adjective: "plus" is also an adverb, it never agrees
        bool participle = false;
        foreach (LambekLemma lemma in dictionary.Lemmas(word, "fr", true))
        {
            if (lemma.Pos == "v" && lemma.Tag.Length > 0 && lemma.Tag[0] == 'K') participle = true;
            else if (lemma.Pos != "a" && lemma.Pos != "v") return false;
        }
        return participle;
    }

    static string Inflect(ILambekWords dictionary, string word, string pos, string gender, string number)
    {
        // The form of the same lemma with the number asked (and the gender, when given)
        foreach (LambekLemma lemma in dictionary.Lemmas(word, "fr", true))
        {
            if (lemma.Pos != pos) continue;
            // A word written in small letters is never the name it may also be ("euros" is not "Euros")
            bool small = word == word.ToLowerInvariant();
            if (small && lemma.Shown.Length > 0 && char.IsUpper(lemma.Shown[0])) continue;
            string wanted = (gender ?? "") + number;
            string itsGender = lemma.Tag.Contains('f') ? "f" : "m";
            if (gender == null) wanted = itsGender + number;
            string[] forms = dictionary.Forms(lemma.Shown, "fr", pos, wanted);
            if (forms.Length == 0 && gender == null) forms = dictionary.Forms(lemma.Shown, "fr", pos, number);
            if (small) { foreach (string form in forms) { if (form == form.ToLowerInvariant()) return form; } }
            if (forms.Length > 0) return forms[0];
        }
        return null;
    }

    static string Agree(ILambekWords dictionary, string word, string gender, string number)
    {
        // A past participle (K) or an adjective in the gender and number of its noun
        foreach (LambekLemma lemma in dictionary.Lemmas(word, "fr", true))
        {
            if (lemma.Pos == "v" && lemma.Tag.Length > 0 && lemma.Tag[0] == 'K')
            {
                string[] forms = dictionary.Forms(lemma.Shown, "fr", "v", "K" + gender + number);
                if (forms.Length > 0) return forms[0];
            }
            if (lemma.Pos == "a")
            {
                string[] forms = dictionary.Forms(lemma.Shown, "fr", "a", gender + number);
                if (forms.Length > 0) return forms[0];
            }
        }
        return null;
    }

    // Tu instead of vous, for a user who says tu: the verbs of the second person plural become singular (Lefff gives the form)
    public static string Familiar(string text, ILambekWords dictionary)
    {
        if (string.IsNullOrEmpty(text) || dictionary == null) return text;
        List<Token> tokens = Split(text);
        for (int i = 0; i < tokens.Count; i++)
        {
            if (!tokens[i].Word) continue;
            string word = tokens[i].Text;
            string lower = word.ToLowerInvariant();
            int next = Next(tokens, i);
            int back = Previous(tokens, i);

            if (lower == "votre" || lower == "vos")
            {
                if (lower == "vos") { tokens[i].Text = Case(word, "tes"); continue; }
                string gender = next > 0 && tokens[next].Word ? NounGender(dictionary, tokens[next].Text) : null;
                bool vowel = next > 0 && tokens[next].Word && StartsWithVowel(tokens[next].Text);
                tokens[i].Text = Case(word, gender == "f" && !vowel ? "ta" : "ton");
                continue;
            }
            if (lower == "vôtre" || lower == "vôtres") { tokens[i].Text = Case(word, lower == "vôtre" ? "tien" : "tiens"); continue; }

            if (lower == "vous")
            {
                // After a verb and a hyphen ("voulez-vous"): the verb before it becomes singular, then "tu"
                if (back >= 0 && tokens[back].Text == "-" && back > 0)
                {
                    // "Voulez-vous" asks (present tense), "Asseyez-vous" tells (imperative)
                    int verb = Previous(tokens, back);
                    bool imperative = verb >= 0 && !dictionary.Lemmas(tokens[verb].Text, "fr", true).Any(l => l.Pos == "v" && l.Tag.Contains('P') && l.Tag.Contains('2') && l.Tag.EndsWith("p", StringComparison.Ordinal));
                    tokens[i].Text = Case(word, imperative ? "toi" : "tu");
                    if (verb >= 0) tokens[verb].Text = Case(tokens[verb].Text, Singular(dictionary, tokens[verb].Text, imperative) ?? tokens[verb].Text);
                    continue;
                }
                // Before a verb of the second person plural: the subject "tu"; the small pronouns between them stay
                // ("vous m'avez dit": "tu m'as dit", "vous vous appelez": "tu t'appelles")
                int verbAt = next;
                while (verbAt > 0 && verbAt != i && (Clitics.Contains(tokens[verbAt].Text.ToLowerInvariant()) || tokens[verbAt].Text == "'" || tokens[verbAt].Text == "\u2019"))
                    verbAt = Next(tokens, verbAt);
                if (verbAt > 0 && tokens[verbAt].Word && IsSecondPlural(dictionary, tokens[verbAt].Text))
                {
                    tokens[i].Text = Case(word, "tu");
                    tokens[verbAt].Text = Case(tokens[verbAt].Text, Singular(dictionary, tokens[verbAt].Text, false) ?? tokens[verbAt].Text);
                    continue;
                }
                // Before another verb: the object "te" ("je vous montre": "je te montre"), "t'" before a vowel
                if (next > 0 && tokens[next].Word && IsVerb(dictionary, tokens[next].Text))
                {
                    if (StartsWithVowel(tokens[next].Text) && next == i + 2) { tokens[i].Text = Case(word, "t'"); tokens[i + 1].Text = ""; }
                    else tokens[i].Text = Case(word, "te");
                    continue;
                }
                tokens[i].Text = Case(word, "toi");
                continue;
            }

            // A verb in the imperative plural at the start of a clause ("Simulez d'abord", "Répondez oui"),
            // unless "-vous" follows: that one is changed with its pronoun
            bool inverted = i + 2 < tokens.Count && tokens[i + 1].Text == "-" && tokens[i + 2].Text.ToLowerInvariant() == "vous";
            if (!inverted && IsImperative(dictionary, word, tokens, i))
            {
                string singular = Singular(dictionary, word, true);
                if (singular != null) tokens[i].Text = Case(word, singular);
            }
        }
        return Join(tokens);
    }

    // The small pronouns that stand between a subject and its verb
    static readonly HashSet<string> Clitics = new HashSet<string>(StringComparer.Ordinal) { "me", "m", "te", "t", "se", "s", "nous", "vous", "le", "la", "les", "l", "lui", "leur", "y", "en" };

    static bool IsVerb(ILambekWords dictionary, string word)
    {
        return dictionary.Lemmas(word, "fr", true).Any(l => l.Pos == "v");
    }

    static bool IsSecondPlural(ILambekWords dictionary, string word)
    {
        return dictionary.Lemmas(word, "fr", true).Any(l => l.Pos == "v" && l.Tag.Contains('2') && l.Tag.EndsWith("p", StringComparison.Ordinal));
    }

    static bool IsImperative(ILambekWords dictionary, string word, List<Token> tokens, int at)
    {
        // An imperative plural form, first in its clause (after the start, a period, a colon or a comma)
        if (!dictionary.Lemmas(word, "fr", true).Any(l => l.Pos == "v" && l.Tag.Contains('Y') && l.Tag.Contains('2') && l.Tag.EndsWith("p", StringComparison.Ordinal))) return false;
        int back = Previous(tokens, at);
        if (back < 0) return true;
        string before = tokens[back].Text.Trim();
        return before == "." || before == ":" || before == "," || before == ";" || before == "!" || before == "?" || before == "puis" || before == "et";
    }

    static string Singular(ILambekWords dictionary, string word, bool imperative)
    {
        // The same lemma and mood, second person singular; an imperative first when one is asked
        List<LambekLemma> readings = dictionary.Lemmas(word, "fr", true).Where(l => l.Pos == "v" && l.Tag.Contains('2') && l.Tag.EndsWith("p", StringComparison.Ordinal)).ToList();
        if (imperative) readings = readings.OrderBy(l => l.Tag.Contains('Y') ? 0 : 1).ToList();
        foreach (LambekLemma lemma in readings)
        {
            string moods = new string(lemma.Tag.Where(c => "PIJFCSTY".IndexOf(c) >= 0).ToArray());
            string mood = imperative && moods.Contains('Y') ? "Y" : moods.Length > 0 ? moods.Substring(0, 1) : "P";
            string[] forms = dictionary.Forms(lemma.Shown, "fr", "v", mood + "2s");
            if (forms.Length > 0) return forms[0];
        }
        return null;
    }
}
