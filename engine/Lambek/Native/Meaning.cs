// The meaning of a sentence as DisCoCat computes it in the category of relations (Coecke, Sadrzadeh and Clark 2010):
// each word is a boolean tensor, one index per simple type of its pregroup type, and every link of the reduction
// sums over the two indices it joins. What is left on the s of the head is the set of actions the sentence can mean.
// In relations this is a join of tables (de Felice et al.), exact and the same every time.
using System;
using System.Collections.Generic;
using System.Linq;

public class LambekMeaning
{
    // A basis for each base type: s holds the actions, o the kinds of object, and so on
    public Dictionary<string, List<string>> Spaces = new Dictionary<string, List<string>>(StringComparer.Ordinal);
    // Tensors given by the packs: "word|type" -> the index tuples that are true
    public Dictionary<string, List<int[]>> Tensors = new Dictionary<string, List<int[]>>(StringComparer.Ordinal);

    public int Size(string basis)
    {
        List<string> space;
        return Spaces.TryGetValue(basis, out space) ? Math.Max(1, space.Count) : 1;
    }

    public int Index(string basis, string name)
    {
        List<string> space;
        if (!Spaces.TryGetValue(basis, out space)) return -1;
        return space.IndexOf(name);
    }

    public void Space(string basis, string[] names)
    {
        Spaces[basis] = new List<string>(names);
    }

    public void Word(string word, string type, int[][] ones)
    {
        Tensors[word + "|" + type] = ones.ToList();
    }

    // The tensor of a word: the one a pack gave, else the spider of its type (indices of one base stay equal, the others are free)
    List<int[]> TensorOf(string word, string type, string[] bases)
    {
        List<int[]> given;
        if (Tensors.TryGetValue(word + "|" + type, out given)) return given;
        List<int[]> ones = new List<int[]> { new int[0] };
        for (int k = 0; k < bases.Length; k++)
        {
            List<int[]> next = new List<int[]>();
            int first = Array.IndexOf(bases, bases[k]);
            foreach (int[] partial in ones)
            {
                if (first < k)
                {
                    // Same base as an index before it: the same value (the spider copies)
                    next.Add(partial.Concat(new[] { partial[first] }).ToArray());
                    continue;
                }
                for (int v = 0; v < Size(bases[k]); v++) next.Add(partial.Concat(new[] { v }).ToArray());
            }
            ones = next;
        }
        return ones;
    }

    // Words with their types (their simple types' bases in order), the links as pairs of positions among all simple types,
    // and the position left open: the values it can take, as names of its basis
    public string[] Contract(string[] words, string[] types, string[][] bases, int[][] links, int output)
    {
        // Each simple type position gets a variable; a link makes its two positions share one
        int total = bases.Sum(b => b.Length);
        int[] variable = new int[total];
        for (int k = 0; k < total; k++) variable[k] = k;
        foreach (int[] link in links)
        {
            int a = Find(variable, link[0]);
            int b = Find(variable, link[1]);
            if (a != b) variable[Math.Max(a, b)] = Math.Min(a, b);
        }
        string[] baseAt = new string[total];
        int at = 0;
        for (int w = 0; w < words.Length; w++) foreach (string b in bases[w]) baseAt[at++] = b;

        // Join the words one after the other: a partial assignment of variables survives if every word so far is true on it
        List<Dictionary<int, int>> rows = new List<Dictionary<int, int>> { new Dictionary<int, int>() };
        at = 0;
        for (int w = 0; w < words.Length; w++)
        {
            List<int[]> tensor = TensorOf(words[w], types[w], bases[w]);
            List<Dictionary<int, int>> next = new List<Dictionary<int, int>>();
            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (Dictionary<int, int> row in rows)
            {
                foreach (int[] ones in tensor)
                {
                    Dictionary<int, int> joined = new Dictionary<int, int>(row);
                    bool fits = true;
                    for (int k = 0; k < ones.Length && fits; k++)
                    {
                        int v = Find(variable, at + k);
                        int had;
                        if (joined.TryGetValue(v, out had)) fits = had == ones[k];
                        else joined[v] = ones[k];
                    }
                    if (!fits) continue;
                    string key = string.Join(",", joined.OrderBy(p => p.Key).Select(p => p.Key + "=" + p.Value));
                    if (seen.Add(key)) next.Add(joined);
                }
            }
            rows = next;
            at += bases[w].Length;
            if (rows.Count == 0) break;
        }

        // What the open position can be
        SortedSet<string> meaning = new SortedSet<string>(StringComparer.Ordinal);
        if (output < 0 || output >= total) return meaning.ToArray();
        int open = Find(variable, output);
        List<string> space;
        Spaces.TryGetValue(baseAt[output], out space);
        foreach (Dictionary<int, int> row in rows)
        {
            int value;
            if (!row.TryGetValue(open, out value)) continue;
            meaning.Add(space != null && value < space.Count ? space[value] : value.ToString());
        }
        return meaning.ToArray();
    }

    static int Find(int[] parent, int k)
    {
        while (parent[k] != k) k = parent[k];
        return k;
    }
}
