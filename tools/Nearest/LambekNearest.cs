// The nearest examples, weighed by a bell curve: a reader made of remembered examples instead of neurons. Each example
// is a vector of its features (a feature many examples share weighs less); each feature lists the examples that have
// it (an inverted index: the counting turned around, so a question only meets the examples it shares something with).
// The k nearest vote for their class, each with the weight a Gaussian gives its distance. Everything is sorted
// ordinally and rounded, so the same examples give the same votes on every machine.
using System;
using System.Collections.Generic;
using System.Linq;

public class LambekNearest
{
    readonly List<int[]> examples = new List<int[]>();
    readonly List<int> labels = new List<int>();
    readonly List<string> texts = new List<string>();
    readonly Dictionary<string, int> featureIds = new Dictionary<string, int>(StringComparer.Ordinal);
    readonly List<List<int>> postings = new List<List<int>>();
    double[] weights;
    double[] norms;
    public readonly List<string> Classes = new List<string>();
    readonly Dictionary<string, int> classIds = new Dictionary<string, int>(StringComparer.Ordinal);

    public int Count { get { return examples.Count; } }

    // Supervised: a feature also weighs by how much it tells the classes apart (how pure the classes of the examples
    // that have it are), learned by counting, not by gradient
    public bool Supervised;

    public void Add(string[] features, string label, string text)
    {
        int @class;
        if (!classIds.TryGetValue(label, out @class)) { @class = Classes.Count; Classes.Add(label); classIds[label] = @class; }
        List<int> ids = new List<int>();
        foreach (string name in features.Distinct(StringComparer.Ordinal))
        {
            int id;
            if (!featureIds.TryGetValue(name, out id)) { id = postings.Count; featureIds[name] = id; postings.Add(new List<int>()); }
            ids.Add(id);
            postings[id].Add(examples.Count);
        }
        examples.Add(ids.ToArray());
        labels.Add(@class);
        texts.Add(text);
        weights = null;
    }

    void Prepare()
    {
        if (weights != null) return;
        weights = new double[postings.Count];
        for (int f = 0; f < postings.Count; f++)
        {
            weights[f] = 1.0 / Math.Sqrt(postings[f].Count);
            if (!Supervised) continue;
            int[] counts = new int[Classes.Count];
            foreach (int e in postings[f]) counts[labels[e]]++;
            double purity = (double)counts.Max() / postings[f].Count;
            double chance = 1.0 / Classes.Count;
            double telling = Math.Max(0, (purity - chance) / (1 - chance));
            // A feature seen once tells little, however pure
            weights[f] = telling * telling * Math.Log(1 + postings[f].Count);
        }
        norms = new double[examples.Count];
        for (int e = 0; e < examples.Count; e++)
        {
            double sum = 0;
            foreach (int f in examples[e]) sum += weights[f] * weights[f];
            norms[e] = Math.Sqrt(sum);
        }
    }

    // The class the k nearest examples vote for, with the share of the vote it got; width is the width of the bell
    // (on the distance between unit vectors, from 0 to 2). Neighbours: the three nearest, to say why
    public string Vote(string[] features, int k, double width, out double share, out string[] neighbours)
    {
        Prepare();
        Dictionary<int, double> dots = new Dictionary<int, double>();
        double sum = 0;
        foreach (string name in features.Distinct(StringComparer.Ordinal))
        {
            int f;
            if (!featureIds.TryGetValue(name, out f)) { sum += 1; continue; }
            double w = weights[f];
            sum += w * w;
            foreach (int e in postings[f])
            {
                double dot;
                dots.TryGetValue(e, out dot);
                dots[e] = dot + w * w;
            }
        }
        double norm = Math.Sqrt(sum);
        share = 0;
        neighbours = new string[0];
        if (dots.Count == 0 || norm <= 0) return null;
        List<KeyValuePair<int, double>> near = dots.Select(pair => new KeyValuePair<int, double>(pair.Key, Math.Round(pair.Value / (norm * norms[pair.Key]), 9)))
            .OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key).Take(k).ToList();
        double[] votes = new double[Classes.Count];
        double total = 0;
        foreach (KeyValuePair<int, double> pair in near)
        {
            double distance = Math.Sqrt(Math.Max(0, 2 - 2 * pair.Value));
            double bell = Math.Round(Math.Exp(-(distance * distance) / (2 * width * width)), 9);
            votes[labels[pair.Key]] += bell;
            total += bell;
        }
        int best = 0;
        for (int c = 1; c < votes.Length; c++) if (votes[c] > votes[best]) best = c;
        share = total > 0 ? votes[best] / total : 0;
        neighbours = near.Take(3).Select(pair => texts[pair.Key] + " " + Classes[labels[pair.Key]]).ToArray();
        return Classes[best];
    }
}
