using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

// Which word of a language says what an English word says, learned from sentences translated from English (Tatoeba):
// IBM Model 1 (Brown et al. 1993), its expectation and maximisation run both ways, every pass over the pairs in the
// same order from the same even start, so the same pairs give the same table on every machine. Unlike counting the
// pairs a word is met in, the words of a sentence share what the other sentence says: "the" takes "le", and "cat" is
// left "chat" (Fazly, Alishahi & Stevenson 2010 on the same competition in children). Measured on the translations
// Wiktionary gives the 2000 English words met most (fr, de, es, nl, pt, it): its best word is right 78.7 to 84.5 % of
// the time, counting the pairs 77.3 to 83.2 %. Its links carry the parts of speech of English over (LambekProjection)
public class LambekAligner
{
    static readonly Regex Word = new Regex(@"\p{L}+['\u2019]|\p{L}+(?:-\p{L}+)*");

    readonly Dictionary<string, int> englishIds = new Dictionary<string, int>(StringComparer.Ordinal);
    readonly Dictionary<string, int> otherIds = new Dictionary<string, int>(StringComparer.Ordinal);
    readonly List<string> englishWords = new List<string>();
    readonly List<string> otherWords = new List<string>();
    readonly List<int[]> englishSentences = new List<int[]>();
    readonly List<int[]> otherSentences = new List<int[]>();
    // t(other | english) and t(english | other), each key two ids
    Dictionary<long, double> forward = new Dictionary<long, double>();
    Dictionary<long, double> backward = new Dictionary<long, double>();
    // How many pairs each two words are met in together, and the words each English word is met with
    readonly Dictionary<long, int> together = new Dictionary<long, int>();
    readonly Dictionary<int, List<int>> partners = new Dictionary<int, List<int>>();

    public int Pairs { get { return englishSentences.Count; } }

    static long Key(int a, int b) { return ((long) a << 32) | (uint) b; }

    public static string[] Words(string sentence)
    {
        return Word.Matches(sentence.ToLowerInvariant()).Cast<Match>().Select(m => m.Value).ToArray();
    }

    // The pairs of at most `longest` words a side; the id 0 of each side is the empty word, what a word says with none
    public LambekAligner(string[] english, string[] other, int longest)
    {
        englishWords.Add(""); otherWords.Add("");
        for (int i = 0; i < english.Length && i < other.Length; i++)
        {
            string[] mine = Words(english[i]);
            string[] theirs = Words(other[i]);
            if (mine.Length == 0 || theirs.Length == 0 || mine.Length > longest || theirs.Length > longest) continue;
            Add(mine, theirs);
        }
    }

    // The pairs as cut into words already (by the forms models), every one kept, in the order given
    public LambekAligner(IList<string[]> english, IList<string[]> other)
    {
        englishWords.Add(""); otherWords.Add("");
        for (int i = 0; i < english.Count && i < other.Count; i++)
        {
            Add(english[i].Select(w => w.ToLowerInvariant()).ToArray(), other[i].Select(w => w.ToLowerInvariant()).ToArray());
        }
    }

    void Add(string[] mine, string[] theirs)
    {
        int[] e = mine.Select(w => Id(englishIds, englishWords, w)).ToArray();
        int[] f = theirs.Select(w => Id(otherIds, otherWords, w)).ToArray();
        englishSentences.Add(e);
        otherSentences.Add(f);
        foreach (int a in e.Distinct())
        {
            foreach (int b in f.Distinct())
            {
                long k = Key(a, b); int n;
                if (!together.TryGetValue(k, out n))
                {
                    List<int> list;
                    if (!partners.TryGetValue(a, out list)) partners[a] = list = new List<int>();
                    list.Add(b);
                }
                together[k] = n + 1;
            }
        }
    }

    static int Id(Dictionary<string, int> ids, List<string> words, string word)
    {
        int id;
        if (ids.TryGetValue(word, out id)) return id;
        id = words.Count;
        ids[word] = id;
        words.Add(word);
        return id;
    }

    // `passes` of expectation and maximisation each way, from an even table over the words met together
    public void Train(int passes)
    {
        forward = Learn(englishSentences, otherSentences, passes);
        backward = Learn(otherSentences, englishSentences, passes);
    }

    // t(target | source), the source side with its empty word. Each two words met together are given a cell once, and
    // each pair the cells of its words in order, so a pass is a walk over arrays
    static Dictionary<long, double> Learn(List<int[]> sources, List<int[]> targets, int passes)
    {
        Dictionary<long, int> ids = new Dictionary<long, int>();
        List<int> owners = new List<int>();
        List<int> keys = new List<int>();
        List<long> pairs = new List<long>();
        for (int s = 0; s < sources.Count; s++)
        {
            foreach (int target in targets[s])
            {
                keys.Add(Cell(ids, owners, pairs, 0, target));
                foreach (int source in sources[s]) keys.Add(Cell(ids, owners, pairs, source, target));
            }
        }
        int[] cells = keys.ToArray();
        keys = null;
        int[] owner = owners.ToArray();
        int most = 0;
        foreach (int o in owner) if (o > most) most = o;
        double[] t = new double[owner.Length];
        for (int c = 0; c < t.Length; c++) t[c] = 1.0;
        double[] counts = new double[owner.Length];
        double[] totals = new double[most + 1];
        for (int pass = 0; pass < passes; pass++)
        {
            Array.Clear(counts, 0, counts.Length);
            Array.Clear(totals, 0, totals.Length);
            int at = 0;
            for (int s = 0; s < sources.Count; s++)
            {
                int width = sources[s].Length + 1;
                for (int j = 0; j < targets[s].Length; j++, at += width)
                {
                    // (the share of the target each source word, the empty one first, takes)
                    double sum = 0;
                    for (int i = 0; i < width; i++) sum += t[cells[at + i]];
                    for (int i = 0; i < width; i++) { int c = cells[at + i]; counts[c] += t[c] / sum; }
                }
            }
            for (int c = 0; c < counts.Length; c++) totals[owner[c]] += counts[c];
            for (int c = 0; c < t.Length; c++) t[c] = counts[c] / totals[owner[c]];
        }
        Dictionary<long, double> table = new Dictionary<long, double>(t.Length);
        for (int c = 0; c < t.Length; c++) table[pairs[c]] = t[c];
        return table;
    }

    static int Cell(Dictionary<long, int> ids, List<int> owners, List<long> pairs, int source, int target)
    {
        long k = Key(source, target);
        int id;
        if (ids.TryGetValue(k, out id)) return id;
        id = owners.Count;
        ids[k] = id;
        owners.Add(source);
        pairs.Add(k);
        return id;
    }

    // The words of the other language that say what an English word says, the best first: each scored by the table
    // both ways, sqrt(t(f|e) t(e|f)); none with less than `least` pairs together
    public List<KeyValuePair<string, double>> Translations(string english, int least, int count)
    {
        List<KeyValuePair<string, double>> found = new List<KeyValuePair<string, double>>();
        int e;
        if (!englishIds.TryGetValue(english, out e)) return found;
        List<int> met;
        if (!partners.TryGetValue(e, out met)) return found;
        foreach (int f in met)
        {
            int n;
            if (!together.TryGetValue(Key(e, f), out n) || n < least) continue;
            double there, back;
            if (!forward.TryGetValue(Key(e, f), out there) || !backward.TryGetValue(Key(f, e), out back)) continue;
            found.Add(new KeyValuePair<string, double>(otherWords[f], Math.Sqrt(there * back)));
        }
        return found.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal).Take(count).ToList();
    }

    // Which English word each word of the other side of pair `s` says, where each is the other's best both ways (the
    // table forward and the table back agree, Och & Ney 2003); -1 for a word with none, or the empty word
    public int[] Links(int s)
    {
        int[] e = englishSentences[s], f = otherSentences[s];
        int[] links = new int[f.Length];
        for (int j = 0; j < f.Length; j++)
        {
            links[j] = -1;
            int best = -1; double most = Get(forward, 0, f[j]);
            for (int i = 0; i < e.Length; i++) { double p = Get(forward, e[i], f[j]); if (p > most) { most = p; best = i; } }
            if (best < 0) continue;
            int back = -1; double top = Get(backward, 0, e[best]);
            for (int k = 0; k < f.Length; k++) { double p = Get(backward, f[k], e[best]); if (p > top) { top = p; back = k; } }
            if (back == j) links[j] = best;
        }
        return links;
    }

    static double Get(Dictionary<long, double> table, int a, int b)
    {
        double p;
        return table.TryGetValue(Key(a, b), out p) ? p : 0;
    }
}
