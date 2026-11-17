// The letters of a language: how often each letter follows the two before it in the words its treebanks wrote, as
// written (with their accents, small), each word counted as often as it was written. What a short sentence says of
// its language when its few words are written in several ("e" is a word of Italian and of Portuguese, "e" with a
// grave accent only of Italian; "abbaia" looks Italian, "ladra" Spanish or Portuguese). Learned from the forms models,
// nothing written by hand; the same for every language
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

public sealed class LambekLetters
{
    readonly Dictionary<string, long> three = new Dictionary<string, long>(StringComparer.Ordinal);
    readonly Dictionary<string, long> two = new Dictionary<string, long>(StringComparer.Ordinal);
    readonly HashSet<char> alphabet = new HashSet<char>();
    readonly Dictionary<string, long> words = new Dictionary<string, long>(StringComparer.Ordinal);
    readonly Dictionary<string, long> small = new Dictionary<string, long>(StringComparer.Ordinal);
    readonly HashSet<string> names = new HashSet<string>(StringComparer.Ordinal);
    static readonly HashSet<string> Closed = new HashSet<string>(StringComparer.Ordinal) { "DET", "ADP", "PRON", "CCONJ", "SCONJ", "AUX", "PART" };

    // All the words written, as often as each was
    public long Total { get; private set; }

    // The letters of the words of the forms model at a path, read without its tagger
    public static LambekLetters Load(string path) { return Of(LambekForms.Load(path, false)); }

    // The letters of the words of a forms model (names, numbers and signs left out)
    public static LambekLetters Of(LambekForms forms)
    {
        if (forms == null) { throw new ArgumentNullException(nameof(forms)); }
        LambekLetters letters = new LambekLetters();
        foreach (KeyValuePair<string, SortedDictionary<string, int>> paradigm in forms.Paradigms)
        {
            string upos = paradigm.Key.Split('\t')[0];
            if (upos == "PROPN") { foreach (string name in paradigm.Value.Keys) { letters.names.Add(Plain(name)); } continue; }
            if (upos == "PUNCT" || upos == "NUM" || upos == "SYM" || upos == "X") { continue; }
            bool closed = Closed.Contains(upos);
            foreach (KeyValuePair<string, int> seen in paradigm.Value) { letters.Add(seen.Key, seen.Value, closed); }
        }
        return letters;
    }

    // A word as its letters are compared: small, its accents joined to their letters
    public static string Plain(string word) { return (word ?? "").Normalize(NormalizationForm.FormC).ToLowerInvariant(); }

    void Add(string word, int times, bool closed)
    {
        string plain = Plain(word);
        if (plain.Length == 0) { return; }
        foreach (char c in plain) { if (!char.IsLetter(c)) { return; } }
        long w;
        words.TryGetValue(plain, out w); words[plain] = w + times;

        if (closed) { small.TryGetValue(plain, out w); small[plain] = w + times; }
        Total += times;
        foreach (char c in plain) { alphabet.Add(c); }
        string padded = "^^" + plain + "$";
        for (int i = 2; i < padded.Length; i++)
        {
            string context = padded.Substring(i - 2, 2);
            string key = padded.Substring(i - 2, 3);
            long n;
            three.TryGetValue(key, out n); three[key] = n + times;
            two.TryGetValue(context, out n); two[context] = n + times;
        }
    }

    // How often the word was written, as written; and as a small word
    public long Count(string word) { long n; return words.TryGetValue(Plain(word), out n) ? n : 0; }
    public long SmallCount(string word) { long n; return small.TryGetValue(Plain(word), out n) ? n : 0; }

    // Whether the treebanks wrote the word as a name ("Tom", "Rosa"), whatever else they wrote it as
    public bool IsName(string word) { return names.Contains(Plain(word)); }

    // How likely the language writes the word, in log10: as often as it was written, and, for one written seldom or
    // never, as its letters say (Letters), weighed as if it had been met so many times (weight)
    public double Word(string word, double weight)
    {
        double letters = Math.Pow(10, Letters(word));
        return Math.Log10((Count(word) + weight * letters) / (Total + weight));
    }

    // How likely the language writes the word, in log10, letter by letter: each letter after the two before it, with
    // one more of each letter of its alphabet and of a letter it never writes, so that what was never seen is unlikely,
    // never impossible
    public double Letters(string word)
    {
        string plain = Plain(word);
        string padded = "^^" + plain + "$";
        double sum = 0;
        int size = alphabet.Count + 2;
        for (int i = 2; i < padded.Length; i++)
        {
            long n3, n2;
            three.TryGetValue(padded.Substring(i - 2, 3), out n3);
            two.TryGetValue(padded.Substring(i - 2, 2), out n2);
            sum += Math.Log10((n3 + 1.0) / (n2 + size));
        }
        return sum;
    }
}
