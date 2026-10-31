// What Lambek knows of the world: the facts of Wikidata written by tools/Get-LambekFacts.ps1 (Data/Knowledge), read once.
// Each thing has its kinds (a country, a city, a person, a book, a film, a painting, or only a value other facts point
// at), how many Wikipedias have a page on it (the better known first when a name is shared), its names and
// descriptions in French and English, and its facts: a property and a value (another thing, a date with its precision,
// a number with the year it was counted). A name is found in a sentence by its words, without accents or case, the
// longest first. Nothing here guesses: what is not in the file is not known.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Text;

public sealed class LambekFact
{
    public string Property;
    // Q90 for a thing, 1802-02-26 for a date (the year negative before our era), 68373433 for a number
    public string Value;
    // The precision of a date (9 the year, 10 the month, 11 the day), the year a number was counted
    public string Extra;
}

public sealed class LambekThing
{
    public string Id;
    public string[] Kinds = new string[0];
    public int Links;
    public readonly Dictionary<string, string> Labels = new Dictionary<string, string>(StringComparer.Ordinal);
    public readonly Dictionary<string, string> Descriptions = new Dictionary<string, string>(StringComparer.Ordinal);
    public readonly List<string> Aliases = new List<string>();
    public readonly List<LambekFact> Facts = new List<LambekFact>();

    public bool Is(string kind) { return Array.IndexOf(Kinds, kind) >= 0; }

    // The name in a language, else the name Wikidata gives for every language (mul), else in the other one, else the id
    public string Label(string language)
    {
        string name;
        if (Labels.TryGetValue(language, out name)) { return name; }
        foreach (string other in new[] { "mul", "en", "fr" }) { if (Labels.TryGetValue(other, out name)) { return name; } }
        return Id;
    }

    public string Description(string language)
    {
        string text;
        return Descriptions.TryGetValue(language, out text) ? text : null;
    }

    public LambekFact[] Values(string property)
    {
        List<LambekFact> found = new List<LambekFact>();
        foreach (LambekFact fact in Facts) { if (fact.Property == property) { found.Add(fact); } }
        return found.ToArray();
    }
}

// A name found in a sentence: where it starts among the words, how many words it has, the things it names
public sealed class LambekNameMention
{
    public int Start;
    public int Length;
    public string Name;
    public LambekThing[] Things;
    // Only the last word of a person's name ("Mozart"), said alone
    public bool Surname;
}

public sealed class LambekFacts
{
    public string Source = "";
    public string Endpoint = "";
    public string Day = "";
    public int Count { get { return things.Count; } }

    readonly Dictionary<string, LambekThing> things = new Dictionary<string, LambekThing>(StringComparer.Ordinal);
    readonly Dictionary<string, List<LambekThing>> names = new Dictionary<string, List<LambekThing>>(StringComparer.Ordinal);
    readonly Dictionary<string, List<LambekThing>> surnames = new Dictionary<string, List<LambekThing>>(StringComparer.Ordinal);
    readonly Dictionary<string, List<LambekThing>> pointing = new Dictionary<string, List<LambekThing>>(StringComparer.Ordinal);
    readonly Dictionary<string, List<LambekThing>> kinds = new Dictionary<string, List<LambekThing>>(StringComparer.Ordinal);
    int longest = 1;
    // The names of one word, by their length, made when a name is first looked for one slip away
    Dictionary<int, List<string>> single;

    public static LambekFacts Load(string path)
    {
        LambekFacts facts = new LambekFacts();
        using (FileStream file = File.OpenRead(path))
        using (GZipStream zip = new GZipStream(file, CompressionMode.Decompress))
        using (StreamReader reader = new StreamReader(zip, new UTF8Encoding(false)))
        {
            string line;
            LambekThing thing = null;
            while ((line = reader.ReadLine()) != null)
            {
                if (line.Length == 0) { continue; }
                string[] parts = line.Split('\t');
                if (parts[0] == "# lambek-facts-1")
                {
                    if (parts.Length > 1) { facts.Source = parts[1]; }
                    if (parts.Length > 2) { facts.Endpoint = parts[2]; }
                    if (parts.Length > 3) { facts.Day = parts[3]; }
                    continue;
                }
                if (parts.Length < 3) { continue; }
                if (thing == null || thing.Id != parts[1])
                {
                    if (!facts.things.TryGetValue(parts[1], out thing))
                    {
                        thing = new LambekThing { Id = parts[1] };
                        facts.things[thing.Id] = thing;
                    }
                }
                switch (parts[0])
                {
                    case "K":
                        thing.Kinds = parts[2].Split(',');
                        if (parts.Length > 3) { int.TryParse(parts[3], NumberStyles.Integer, CultureInfo.InvariantCulture, out thing.Links); }
                        break;
                    case "L":
                        if (parts.Length > 3) { thing.Labels[parts[2]] = parts[3]; }
                        break;
                    case "A":
                        if (parts.Length > 3) { thing.Aliases.Add(parts[3]); }
                        break;
                    case "D":
                        if (parts.Length > 3) { thing.Descriptions[parts[2]] = parts[3]; }
                        break;
                    case "F":
                        thing.Facts.Add(new LambekFact { Property = parts[2], Value = parts.Length > 3 ? parts[3] : "", Extra = parts.Length > 4 ? parts[4] : "" });
                        break;
                }
            }
        }
        facts.Index();
        return facts;
    }

    void Index()
    {
        foreach (LambekThing thing in things.Values)
        {
            HashSet<string> own = new HashSet<string>(StringComparer.Ordinal);
            foreach (string label in thing.Labels.Values) { own.Add(Plain(label)); }
            foreach (string alias in thing.Aliases) { own.Add(Plain(alias)); }
            foreach (string name in own)
            {
                // A name of one or two letters is a word of the sentence, not a name ("a", "us")
                if (name.Length < 3) { continue; }
                Add(names, name, thing);
                int words = name.Split(' ').Length;
                if (words > longest) { longest = words; }
            }
            // A person is often named by the last word of their name alone ("Mozart", "Einstein")
            if (thing.Is("person"))
            {
                HashSet<string> last = new HashSet<string>(StringComparer.Ordinal);
                foreach (string label in thing.Labels.Values)
                {
                    string[] words = Plain(label).Split(' ');
                    if (words.Length > 1 && words[words.Length - 1].Length >= 4) { last.Add(words[words.Length - 1]); }
                }
                foreach (string word in last) { Add(surnames, word, thing); }
            }
            foreach (LambekFact fact in thing.Facts)
            {
                if (fact.Value.Length > 1 && fact.Value[0] == 'Q') { Add(pointing, fact.Property + "|" + fact.Value, thing); }
            }
            // (a thing has each of its kinds once: no need to look for it in the list)
            foreach (string kind in thing.Kinds)
            {
                List<LambekThing> list;
                if (!kinds.TryGetValue(kind, out list)) { list = new List<LambekThing>(); kinds[kind] = list; }
                list.Add(thing);
            }
        }
        // The better known first: the order every answer is read in
        foreach (Dictionary<string, List<LambekThing>> index in new[] { names, surnames, pointing, kinds })
        {
            foreach (List<LambekThing> list in index.Values) { list.Sort(Better); }
        }
    }

    static int Better(LambekThing a, LambekThing b)
    {
        if (a.Links != b.Links) { return b.Links.CompareTo(a.Links); }
        return string.CompareOrdinal(a.Id, b.Id);
    }

    static void Add(Dictionary<string, List<LambekThing>> index, string key, LambekThing thing)
    {
        List<LambekThing> list;
        if (!index.TryGetValue(key, out list)) { list = new List<LambekThing>(); index[key] = list; }
        if (!list.Contains(thing)) { list.Add(thing); }
    }

    public LambekThing Thing(string id)
    {
        LambekThing thing;
        return id != null && things.TryGetValue(id, out thing) ? thing : null;
    }

    // The things whose property has this value: the books of an author, the country a city is the capital of
    public LambekThing[] Having(string property, string value)
    {
        List<LambekThing> list;
        return pointing.TryGetValue(property + "|" + value, out list) ? list.ToArray() : new LambekThing[0];
    }

    // Every thing of a kind (every country, every city), the better known first
    public LambekThing[] OfKind(string kind)
    {
        List<LambekThing> list;
        return kinds.TryGetValue(kind, out list) ? list.ToArray() : new LambekThing[0];
    }

    // Every name in the words of a sentence (already plain), at every place, the longest first at each place
    public LambekNameMention[] Find(string plain)
    {
        List<LambekNameMention> found = new List<LambekNameMention>();
        string[] words = plain.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
        for (int start = 0; start < words.Length; start++)
        {
            for (int length = Math.Min(longest, words.Length - start); length >= 1; length--)
            {
                string name = string.Join(" ", words, start, length);
                List<LambekThing> list;
                if (names.TryGetValue(name, out list)) { found.Add(new LambekNameMention { Start = start, Length = length, Name = name, Things = list.ToArray() }); }
                else if (length == 1 && surnames.TryGetValue(name, out list)) { found.Add(new LambekNameMention { Start = start, Length = 1, Name = name, Things = list.ToArray(), Surname = true }); }
            }
        }
        return found.ToArray();
    }

    // The names of one word one slip from a word (already plain): "frahce" is one slip from "france", "bressil" from
    // "bresil". The better known first (the thing each names that the most pages tell of), then in order
    public LambekNameMention[] Near(string plain)
    {
        if (string.IsNullOrEmpty(plain) || plain.IndexOf(' ') >= 0) { return new LambekNameMention[0]; }
        if (single == null)
        {
            Dictionary<int, List<string>> made = new Dictionary<int, List<string>>();
            foreach (string name in names.Keys)
            {
                if (name.IndexOf(' ') >= 0) { continue; }
                List<string> list;
                if (!made.TryGetValue(name.Length, out list)) { list = new List<string>(); made[name.Length] = list; }
                list.Add(name);
            }
            foreach (List<string> list in made.Values) { list.Sort(string.CompareOrdinal); }
            single = made;
        }
        List<LambekNameMention> found = new List<LambekNameMention>();
        for (int length = plain.Length - 1; length <= plain.Length + 1; length++)
        {
            List<string> list;
            if (!single.TryGetValue(length, out list)) { continue; }
            foreach (string name in list)
            {
                if (LambekDictionary.OneEdit(name, 0, name.Length, plain)) { found.Add(new LambekNameMention { Start = 0, Length = 1, Name = name, Things = names[name].ToArray() }); }
            }
        }
        found.Sort((a, b) =>
        {
            int known = b.Things[0].Links.CompareTo(a.Things[0].Links);
            return known != 0 ? known : string.CompareOrdinal(a.Name, b.Name);
        });
        return found.ToArray();
    }

    // The words of a text as names are compared: no accents, no case, no punctuation, single spaces
    public static string Plain(string text)
    {
        if (string.IsNullOrEmpty(text)) { return ""; }
        string decomposed = text.Normalize(NormalizationForm.FormD);
        StringBuilder builder = new StringBuilder(decomposed.Length);
        bool space = true;
        foreach (char c in decomposed)
        {
            UnicodeCategory category = CharUnicodeInfo.GetUnicodeCategory(c);
            if (category == UnicodeCategory.NonSpacingMark) { continue; }
            if (char.IsLetterOrDigit(c))
            {
                if (c == 'ß') { builder.Append("ss"); }
                else { builder.Append(char.ToLowerInvariant(c)); }
                space = false;
            }
            else if (!space)
            {
                builder.Append(' ');
                space = true;
            }
        }
        return builder.ToString().TrimEnd(' ').Normalize(NormalizationForm.FormC);
    }
}
