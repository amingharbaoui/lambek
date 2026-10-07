// Learning with guarantees: everything here is symbolic and exact (no neural net, no randomness).
// 1. Version spaces (Mitchell): which files the user means, from yes/no examples.
// 2. Size principle (Tenenbaum): exact probabilities of the hypotheses that are left.
// 3. Rename by example (FlashFill style): the cheapest program that turns each old name into its new name.
// 4. Explanation-based generalisation: one proof of the Datalog engine turned into one macro rule.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Numerics;
using System.Text;

// One attribute of a file (type, folder, size...) as a tree of values: each value has one parent, the root is "any"
public class LambekConceptTree
{
    public const string Root = "any";
    public string Name;
    public Dictionary<string, string> Parent = new Dictionary<string, string>(StringComparer.Ordinal);

    public LambekConceptTree(string name)
    {
        Name = name;
    }

    // A value under its parent; the first parent given for a value is kept (a tree, not a graph)
    // Returns true when the value was not known yet
    public bool Add(string node, string parent)
    {
        if (node == Root || Parent.ContainsKey(node)) { return false; }
        if (parent != Root && !Parent.ContainsKey(parent)) { Parent[parent] = Root; }
        Parent[node] = parent;
        return true;
    }

    // A chain from the most specific value up: ".jpg", "image", "media" (the root is implied)
    public void AddChain(string[] chain)
    {
        for (int i = chain.Length - 1; i >= 0; i--)
        {
            string parent = Root;
            if (i + 1 < chain.Length) { parent = chain[i + 1]; }
            Add(chain[i], parent);
        }
    }

    // The value, its parent, and so on up to the root
    public List<string> Ancestors(string node)
    {
        List<string> list = new List<string>();
        string current = node;
        while (current != Root)
        {
            list.Add(current);
            string parent;
            if (!Parent.TryGetValue(current, out parent)) { parent = Root; }
            current = parent;
            // A loop in the tree would be a mistake of the caller: stop instead of turning forever
            if (list.Count > 1000) { throw new InvalidOperationException("The tree of " + Name + " has a loop."); }
        }
        list.Add(Root);
        return list;
    }

    // general covers specific when it is the same value or one of its ancestors
    public bool Covers(string general, string specific)
    {
        if (general == Root) { return true; }
        return Ancestors(specific).Contains(general);
    }

    // The lowest value that covers both
    public string Join(string a, string b)
    {
        List<string> above = Ancestors(b);
        foreach (string node in Ancestors(a))
        {
            if (above.Contains(node)) { return node; }
        }
        return Root;
    }

    public List<string> Children(string node)
    {
        List<string> list = new List<string>();
        foreach (KeyValuePair<string, string> item in Parent)
        {
            if (item.Value == node) { list.Add(item.Key); }
        }
        list.Sort(StringComparer.Ordinal);
        return list;
    }
}

// One hypothesis of the version space with its exact probability
public class LambekConceptRank
{
    public string[] Hypothesis;
    public int Size;
    public LambekRational Probability;
    // "512/819" and 0.625...
    public string Exact;
    public double Value;
}

// Candidate elimination: a hypothesis is one value per attribute, and covers a file when each value covers the
// value of the file. S is the most specific hypothesis that covers every positive example (one only, because the
// attributes are trees); G holds the most general hypotheses that cover S and no negative example.
public class LambekVersionSpace
{
    public List<LambekConceptTree> Trees = new List<LambekConceptTree>();
    public string[] Specific;
    public List<string[]> General = new List<string[]>();
    public List<string[]> Positives = new List<string[]>();
    public List<string[]> Negatives = new List<string[]>();
    public bool Collapsed;
    public string CollapseReason = "";

    public LambekVersionSpace(LambekConceptTree[] trees)
    {
        Trees.AddRange(trees);
        string[] top = new string[trees.Length];
        for (int a = 0; a < top.Length; a++) { top[a] = LambekConceptTree.Root; }
        General.Add(top);
    }

    public bool Covers(string[] hypothesis, string[] instance)
    {
        for (int a = 0; a < Trees.Count; a++)
        {
            if (!Trees[a].Covers(hypothesis[a], instance[a])) { return false; }
        }
        return true;
    }

    static bool Same(string[] a, string[] b)
    {
        for (int i = 0; i < a.Length; i++)
        {
            if (!string.Equals(a[i], b[i], StringComparison.Ordinal)) { return false; }
        }
        return true;
    }

    // A value never seen is a new leaf under the root; true when the trees have grown
    bool Learn(string[] instance)
    {
        if (instance.Length != Trees.Count) { throw new ArgumentException("An example needs one value for each attribute."); }
        bool grown = false;
        for (int a = 0; a < Trees.Count; a++)
        {
            if (Trees[a].Add(instance[a], LambekConceptTree.Root)) { grown = true; }
        }
        return grown;
    }

    void Collapse(string reason)
    {
        Collapsed = true;
        CollapseReason = reason;
        General.Clear();
    }

    // A positive example: S climbs just enough to cover it, and G loses what does not cover it
    public bool AddPositive(string[] instance)
    {
        Learn(instance);
        Positives.Add(instance);
        Rebuild();
        return !Collapsed;
    }

    // A negative example: each member of G that covers it is replaced by its largest specialisations that do not
    public bool AddNegative(string[] instance)
    {
        Learn(instance);
        Negatives.Add(instance);
        Rebuild();
        return !Collapsed;
    }

    // S and G from all the examples so far. Done again after each example (and when a tree grows), because a
    // value met later is a new leaf that an older G could not hold; the result does not depend on the order
    void Rebuild()
    {
        Collapsed = false;
        CollapseReason = "";
        Specific = null;
        General = new List<string[]>();
        string[] top = new string[Trees.Count];
        for (int a = 0; a < top.Length; a++) { top[a] = LambekConceptTree.Root; }
        General.Add(top);

        // S: the lowest value that covers every positive example, attribute by attribute
        foreach (string[] positive in Positives)
        {
            if (Specific == null) { Specific = (string[])positive.Clone(); continue; }
            string[] next = new string[Trees.Count];
            for (int a = 0; a < Trees.Count; a++) { next[a] = Trees[a].Join(Specific[a], positive[a]); }
            Specific = next;
        }

        // Every hypothesis covers S, so a negative example inside S leaves none
        foreach (string[] negative in Negatives)
        {
            if (Specific != null && Covers(Specific, negative))
            {
                Collapse("No description covers every chosen file without covering a refused one.");
                return;
            }
        }

        foreach (string[] negative in Negatives)
        {
            Exclude(negative);
            if (General.Count == 0)
            {
                Collapse("No description is left that avoids the refused files.");
                return;
            }
        }
    }

    // G after one negative example
    void Exclude(string[] instance)
    {
        List<string[]> next = new List<string[]>();
        foreach (string[] general in General)
        {
            if (!Covers(general, instance))
            {
                next.Add(general);
                continue;
            }
            for (int a = 0; a < Trees.Count; a++)
            {
                foreach (string node in Specialisations(a, general[a], instance[a]))
                {
                    string[] changed = (string[])general.Clone();
                    changed[a] = node;
                    next.Add(changed);
                }
            }
        }

        // Only the most general are kept: no duplicate, nothing covered by another member
        List<string[]> maximal = new List<string[]>();
        for (int i = 0; i < next.Count; i++)
        {
            bool dominated = false;
            for (int j = 0; j < next.Count; j++)
            {
                if (i == j) { continue; }
                bool same = Same(next[i], next[j]);
                if (same && j < i) { dominated = true; break; }
                if (!same && MoreGeneral(next[j], next[i])) { dominated = true; break; }
            }
            if (!dominated) { maximal.Add(next[i]); }
        }
        General = maximal;
    }

    // a covers b on every attribute
    bool MoreGeneral(string[] a, string[] b)
    {
        for (int i = 0; i < Trees.Count; i++)
        {
            if (!Trees[i].Covers(a[i], b[i])) { return false; }
        }
        return true;
    }

    // The largest values under "from" that do not cover "avoid" (and still cover S when S exists):
    // the children that leave the path from "from" down to "avoid"
    List<string> Specialisations(int attribute, string from, string avoid)
    {
        LambekConceptTree tree = Trees[attribute];
        List<string> found = new List<string>();
        List<string> path = tree.Ancestors(avoid);
        foreach (string node in path)
        {
            if (!tree.Covers(from, node)) { continue; }
            foreach (string child in tree.Children(node))
            {
                if (path.Contains(child)) { continue; }
                if (Specific != null && !tree.Covers(child, Specific[attribute])) { continue; }
                found.Add(child);
            }
        }
        return found;
    }

    // Learned exactly: one hypothesis is left
    public bool Converged
    {
        get { return !Collapsed && Specific != null && General.Count == 1 && Same(General[0], Specific); }
    }

    // yes: every hypothesis left covers it; no: none does; unknown: they disagree
    public string Classify(string[] instance)
    {
        if (Learn(instance)) { Rebuild(); }
        if (Collapsed) { return "unknown"; }
        if (Specific != null && Covers(Specific, instance)) { return "yes"; }
        foreach (string[] general in General)
        {
            if (Covers(general, instance)) { return "unknown"; }
        }
        return "no";
    }

    // Every hypothesis between S and G: one ancestor of S per attribute, under some member of G
    public List<string[]> Hypotheses()
    {
        List<string[]> all = new List<string[]>();
        if (Collapsed || Specific == null) { return all; }
        all.Add(new string[Trees.Count]);
        for (int a = 0; a < Trees.Count; a++)
        {
            List<string[]> grown = new List<string[]>();
            foreach (string[] partial in all)
            {
                foreach (string node in Trees[a].Ancestors(Specific[a]))
                {
                    string[] copy = (string[])partial.Clone();
                    copy[a] = node;
                    grown.Add(copy);
                }
            }
            all = grown;
        }
        List<string[]> kept = new List<string[]>();
        foreach (string[] hypothesis in all)
        {
            foreach (string[] general in General)
            {
                if (MoreGeneral(general, hypothesis)) { kept.Add(hypothesis); break; }
            }
        }
        return kept;
    }

    // The question to ask: the candidate on which the hypotheses left disagree most evenly
    // (the largest min(yes, no); the first candidate wins a tie). -1 when they all agree on every candidate
    public int NextQuestion(IList<string[]> candidates)
    {
        bool grown = false;
        foreach (string[] candidate in candidates)
        {
            if (Learn(candidate)) { grown = true; }
        }
        if (grown) { Rebuild(); }
        List<string[]> hypotheses = Hypotheses();
        int best = -1;
        int bestScore = 0;
        for (int c = 0; c < candidates.Count; c++)
        {
            int yes = 0;
            foreach (string[] hypothesis in hypotheses)
            {
                if (Covers(hypothesis, candidates[c])) { yes++; }
            }
            int score = Math.Min(yes, hypotheses.Count - yes);
            if (score > bestScore)
            {
                bestScore = score;
                best = c;
            }
        }
        return best;
    }

    // How many items of the universe a hypothesis covers: its size |h|
    public int Size(string[] hypothesis, IList<string[]> universe)
    {
        int count = 0;
        foreach (string[] item in universe)
        {
            if (Covers(hypothesis, item)) { count++; }
        }
        return count;
    }

    // The hypotheses left, the most likely first (size principle); the universe must hold the positive examples
    public List<LambekConceptRank> Rank(IList<string[]> universe)
    {
        List<LambekConceptRank> ranks = new List<LambekConceptRank>();
        bool grown = false;
        foreach (string[] item in universe)
        {
            if (Learn(item)) { grown = true; }
        }
        if (grown) { Rebuild(); }
        List<string[]> hypotheses = Hypotheses();
        if (hypotheses.Count == 0) { return ranks; }
        int[] sizes = new int[hypotheses.Count];
        for (int h = 0; h < sizes.Length; h++) { sizes[h] = Size(hypotheses[h], universe); }
        LambekRational[] posterior = LambekSizePrinciple.Posterior(sizes, Positives.Count, null);
        for (int h = 0; h < sizes.Length; h++)
        {
            LambekConceptRank rank = new LambekConceptRank();
            rank.Hypothesis = hypotheses[h];
            rank.Size = sizes[h];
            rank.Probability = posterior[h];
            rank.Exact = posterior[h].Exact();
            rank.Value = LambekSizePrinciple.ToDouble(posterior[h]);
            ranks.Add(rank);
        }
        // Most likely first, then the smallest, then by text, so the order never depends on chance
        ranks.Sort(delegate (LambekConceptRank x, LambekConceptRank y)
        {
            int byChance = y.Probability.CompareTo(x.Probability);
            if (byChance != 0) { return byChance; }
            if (x.Size != y.Size) { return x.Size.CompareTo(y.Size); }
            return string.CompareOrdinal(string.Join("\u001f", x.Hypothesis), string.Join("\u001f", y.Hypothesis));
        });
        return ranks;
    }
}

// Size principle: P(h | X) = P(h) * (1/|h|)^n / sum over k of P(k) * (1/|k|)^n, for n examples all inside h.
// Exact fractions; a hypothesis that covers nothing gets 0.
public static class LambekSizePrinciple
{
    public static LambekRational[] Posterior(int[] sizes, int examples, LambekRational[] priors)
    {
        if (examples < 0) { throw new ArgumentException("The number of examples cannot be negative."); }
        if (priors != null && priors.Length != sizes.Length) { throw new ArgumentException("One prior for each hypothesis."); }
        LambekRational[] weights = new LambekRational[sizes.Length];
        LambekRational total = LambekRational.Zero;
        for (int h = 0; h < sizes.Length; h++)
        {
            LambekRational prior = LambekRational.One;
            if (priors != null) { prior = priors[h]; }
            if (prior.Sign < 0) { throw new ArgumentException("A prior cannot be negative."); }
            if (sizes[h] <= 0) { weights[h] = LambekRational.Zero; }
            else { weights[h] = prior * new LambekRational(BigInteger.One, BigInteger.Pow(new BigInteger(sizes[h]), examples)); }
            total = total + weights[h];
        }
        if (total.IsZero) { throw new ArgumentException("No hypothesis covers the examples."); }
        LambekRational[] posterior = new LambekRational[sizes.Length];
        for (int h = 0; h < sizes.Length; h++) { posterior[h] = weights[h] / total; }
        return posterior;
    }

    // The fraction as a double, safe when the numbers are too long for a double
    public static double ToDouble(LambekRational value)
    {
        if (value.IsZero) { return 0.0; }
        double numerator = (double)value.Numerator;
        double denominator = (double)value.Denominator;
        if (!double.IsInfinity(numerator) && !double.IsInfinity(denominator)) { return numerator / denominator; }
        return Math.Exp(BigInteger.Log(BigInteger.Abs(value.Numerator)) - BigInteger.Log(value.Denominator)) * value.Numerator.Sign;
    }
}

// A place in a name without its extension: the start, the end, the edge of the k-th run of a kind of character
// (k counted from the start, or from the end when negative), a few characters inside that run counted from its
// edge ("Digits(1).Start+4": after the year of 20240315), or a fixed number of characters
public class LambekRenamePosition
{
    // "Start", "End", "Token" or "Char"
    public string Kind;
    // "Digits", "Letters", "Upper", "Lower" or "Alnum" (for a token)
    public string Class = "";
    public int Index;
    // "Start" or "End" of the run (for a token)
    public string Side = "";
    // Characters after the start of the run (positive) or before its end (negative)
    public int Offset;
    public int Cost;
    public string Key;
    // Its number among the places of the search going on (-1 outside a search): see LambekRenameSource
    public int Slot = -1;

    public static string[] Classes = new string[] { "Alnum", "Digits", "Letters", "Lower", "Upper" };

    public static LambekRenamePosition Edge(string kind)
    {
        LambekRenamePosition position = new LambekRenamePosition();
        position.Kind = kind;
        position.Cost = 0;
        position.Key = kind;
        return position;
    }

    // Cost of a token edge: |k| (3 at most), +1 when counted from the end, +1 for the wider classes,
    // +3 when the place is inside the run
    public static LambekRenamePosition Token(string name, int index, string side, int offset)
    {
        LambekRenamePosition position = new LambekRenamePosition();
        position.Kind = "Token";
        position.Class = name;
        position.Index = index;
        position.Side = side;
        position.Cost = Math.Min(Math.Abs(index), 3);
        if (index < 0) { position.Cost += 1; }
        if (name != "Digits" && name != "Letters") { position.Cost += 1; }
        position.Key = name + "(" + index.ToString(CultureInfo.InvariantCulture) + ")." + side;
        position.Offset = offset;
        if (offset != 0)
        {
            position.Cost += 3;
            position.Key += (offset > 0 ? "+" : "-") + Math.Abs(offset).ToString(CultureInfo.InvariantCulture);
        }
        return position;
    }

    // A fixed count of characters says little about the other names: it costs 8
    public static LambekRenamePosition Character(int index)
    {
        LambekRenamePosition position = new LambekRenamePosition();
        position.Kind = "Char";
        position.Index = index;
        position.Cost = 8;
        position.Key = "Char(" + index.ToString(CultureInfo.InvariantCulture) + ")";
        return position;
    }

    static bool InClass(char c, string name)
    {
        switch (name)
        {
            case "Digits": return char.IsDigit(c);
            case "Letters": return char.IsLetter(c);
            case "Upper": return char.IsUpper(c);
            case "Lower": return char.IsLower(c);
            case "Alnum": return char.IsLetterOrDigit(c);
        }
        return false;
    }

    // The runs of a class in a text: each as { start, end } with the end excluded
    public static List<int[]> Runs(string text, string name)
    {
        List<int[]> runs = new List<int[]>();
        int i = 0;
        while (i < text.Length)
        {
            if (!InClass(text[i], name)) { i++; continue; }
            int start = i;
            while (i < text.Length && InClass(text[i], name)) { i++; }
            runs.Add(new int[] { start, i });
        }
        return runs;
    }

    // Where this place falls in a text, or -1 when the text has no such place
    public int Resolve(string text)
    {
        return Resolve(text, null);
    }

    // The same for a file of a search: each numbered place is looked for once
    public int Resolve(LambekRenameSource source)
    {
        if (Slot < 0 || Slot >= source.Places.Length) { return Resolve(source.Stem, source.Runs); }
        if (!source.Found[Slot])
        {
            source.Places[Slot] = Resolve(source.Stem, source.Runs);
            source.Found[Slot] = true;
        }
        return source.Places[Slot];
    }

    // The same, with the runs of the text kept by class, so many places of one text are found quickly
    public int Resolve(string text, Dictionary<string, List<int[]>> known)
    {
        if (Kind == "Start") { return 0; }
        if (Kind == "End") { return text.Length; }
        if (Kind == "Char")
        {
            int at = Index;
            if (Index < 0) { at = text.Length + Index; }
            if (at < 0 || at > text.Length) { return -1; }
            return at;
        }
        List<int[]> runs;
        if (known == null) { runs = Runs(text, Class); }
        else if (!known.TryGetValue(Class, out runs))
        {
            runs = Runs(text, Class);
            known[Class] = runs;
        }
        int k = Index - 1;
        if (Index < 0) { k = runs.Count + Index; }
        if (k < 0 || k >= runs.Count) { return -1; }
        int edge = runs[k][1];
        if (Side == "Start") { edge = runs[k][0]; }
        // A place inside the run must stay inside it
        if (edge + Offset < runs[k][0] || edge + Offset > runs[k][1]) { return -1; }
        return edge + Offset;
    }

    // Every way to name one index of a text
    public static List<LambekRenamePosition> At(string text, int index)
    {
        List<LambekRenamePosition> list = new List<LambekRenamePosition>();
        if (index == 0) { list.Add(Edge("Start")); }
        if (index == text.Length) { list.Add(Edge("End")); }
        if (index > 0) { list.Add(Character(index)); }
        if (index < text.Length) { list.Add(Character(index - text.Length)); }
        foreach (string name in Classes)
        {
            List<int[]> runs = Runs(text, name);
            for (int r = 0; r < runs.Count; r++)
            {
                if (runs[r][0] == index)
                {
                    list.Add(Token(name, r + 1, "Start", 0));
                    list.Add(Token(name, r - runs.Count, "Start", 0));
                }
                if (runs[r][1] == index)
                {
                    list.Add(Token(name, r + 1, "End", 0));
                    list.Add(Token(name, r - runs.Count, "End", 0));
                }
                // Inside a run of digits or of letters: so many characters from its start, or before its end
                bool inside = runs[r][0] < index && index < runs[r][1];
                if (inside && (name == "Digits" || name == "Letters"))
                {
                    list.Add(Token(name, r + 1, "Start", index - runs[r][0]));
                    list.Add(Token(name, r - runs.Count, "Start", index - runs[r][0]));
                    list.Add(Token(name, r + 1, "End", index - runs[r][1]));
                    list.Add(Token(name, r - runs.Count, "End", index - runs[r][1]));
                }
            }
        }
        return list;
    }
}

// One file as the pieces read it: its name cut in two, its rank in the list and its date,
// with what was already found in it (the runs of each class, the numbered places of a search)
public class LambekRenameSource
{
    public string Stem;
    public string Extension;
    public int Index;
    public DateTime? Time;
    public Dictionary<string, List<int[]>> Runs = new Dictionary<string, List<int[]>>(StringComparer.Ordinal);
    public int[] Places;
    public bool[] Found;

    public LambekRenameSource(string name, int index, DateTime? time, int slots)
    {
        LambekRename.Split(name, out Stem, out Extension);
        Index = index;
        Time = time;
        Places = new int[slots];
        Found = new bool[slots];
    }
}

// One piece of a new name. Costs (MDL, fixed): Const 4 + 13 per letter or digit + 4 per other character;
// Substr 10 + its two positions; a change of case or of zero padding +3; Extension 8; Counter 12 + 8 per digit of
// its start; Date 16. So copying beats typing, short constants beat long ones, and a separator is cheap to type
public class LambekRenameAtom
{
    // "Const", "Substr", "Extension", "Counter" or "Date"
    public string Kind;
    // "", "Lower", "Upper", "Title" (for Substr and Extension) or "Number" (a Substr of digits padded to Width)
    public string Case = "";
    public string Text = "";
    public LambekRenamePosition From;
    public LambekRenamePosition To;
    public int Start;
    public int Width;
    public string Format = "";
    public int Cost;
    public string Key;

    static string Quote(string text)
    {
        return "\"" + text.Replace("\"", "\"\"") + "\"";
    }

    public static LambekRenameAtom Const(string text)
    {
        LambekRenameAtom atom = new LambekRenameAtom();
        atom.Kind = "Const";
        atom.Text = text;
        atom.Cost = 4;
        foreach (char c in text)
        {
            if (char.IsLetterOrDigit(c)) { atom.Cost += 13; } else { atom.Cost += 4; }
        }
        atom.Key = "Const(" + Quote(text) + ")";
        return atom;
    }

    public static LambekRenameAtom Substr(LambekRenamePosition from, LambekRenamePosition to, string change)
    {
        LambekRenameAtom atom = new LambekRenameAtom();
        atom.Kind = "Substr";
        atom.From = from;
        atom.To = to;
        atom.Case = change;
        atom.Cost = 10 + from.Cost + to.Cost;
        atom.Key = "Substr(" + from.Key + ", " + to.Key + ")";
        if (change != "")
        {
            atom.Cost += 3;
            atom.Key = change + "(" + atom.Key + ")";
        }
        return atom;
    }

    // The digits of a part of the old name, without their leading zeros, then padded with zeros to the width
    public static LambekRenameAtom Number(LambekRenamePosition from, LambekRenamePosition to, int width)
    {
        LambekRenameAtom atom = Substr(from, to, "");
        atom.Case = "Number";
        atom.Width = width;
        atom.Cost += 3;
        atom.Key = "Number(" + atom.Key + ", " + width.ToString(CultureInfo.InvariantCulture) + ")";
        return atom;
    }

    public static LambekRenameAtom Extension(string change)
    {
        LambekRenameAtom atom = new LambekRenameAtom();
        atom.Kind = "Extension";
        atom.Case = change;
        atom.Cost = 8;
        atom.Key = "Extension";
        if (change != "")
        {
            atom.Cost += 3;
            atom.Key = change + "(Extension)";
        }
        return atom;
    }

    public static LambekRenameAtom Counter(int start, int width)
    {
        LambekRenameAtom atom = new LambekRenameAtom();
        atom.Kind = "Counter";
        atom.Start = start;
        atom.Width = width;
        atom.Cost = 12 + 8 * start.ToString(CultureInfo.InvariantCulture).Length;
        atom.Key = "Counter(" + start.ToString(CultureInfo.InvariantCulture) + ", " + width.ToString(CultureInfo.InvariantCulture) + ")";
        return atom;
    }

    public static LambekRenameAtom Date(string format)
    {
        LambekRenameAtom atom = new LambekRenameAtom();
        atom.Kind = "Date";
        atom.Format = format;
        atom.Cost = 16;
        atom.Key = "Date(" + Quote(format) + ")";
        return atom;
    }

    // Lower, upper, or title (the first letter of each run of letters in capitals, the others in small letters)
    public static string Change(string text, string change)
    {
        if (change == "Lower") { return text.ToLowerInvariant(); }
        if (change == "Upper") { return text.ToUpperInvariant(); }
        if (change == "Title")
        {
            StringBuilder builder = new StringBuilder();
            bool inside = false;
            foreach (char c in text)
            {
                if (char.IsLetter(c))
                {
                    if (inside) { builder.Append(char.ToLowerInvariant(c)); } else { builder.Append(char.ToUpperInvariant(c)); }
                    inside = true;
                }
                else
                {
                    builder.Append(c);
                    inside = false;
                }
            }
            return builder.ToString();
        }
        return text;
    }

    // What this piece gives for one file: null when it cannot (no such run of digits, no date)
    public string Evaluate(string stem, string extension, int index, DateTime? time)
    {
        LambekRenameSource source = new LambekRenameSource("", index, time, 0);
        source.Stem = stem;
        source.Extension = extension;
        return Evaluate(source);
    }

    public string Evaluate(LambekRenameSource source)
    {
        switch (Kind)
        {
            case "Const":
                return Text;
            case "Extension":
                return Change(source.Extension, Case);
            case "Substr":
                int from = From.Resolve(source);
                int to = To.Resolve(source);
                if (from < 0 || to < 0 || from >= to) { return null; }
                string part = source.Stem.Substring(from, to - from);
                if (Case != "Number") { return Change(part, Case); }
                foreach (char c in part)
                {
                    if (!char.IsDigit(c)) { return null; }
                }
                string trimmed = part.TrimStart('0');
                return trimmed.PadLeft(Math.Max(Width, 1), '0');
            case "Counter":
                long number = (long)Start + source.Index;
                return number.ToString(CultureInfo.InvariantCulture).PadLeft(Width, '0');
            case "Date":
                if (!source.Time.HasValue) { return null; }
                return source.Time.Value.ToString(Format, CultureInfo.InvariantCulture);
        }
        return null;
    }
}

// A program: the pieces put one after the other
public class LambekRenameProgram
{
    public LambekRenameAtom[] Atoms;
    public int Cost;
    // "Const("holiday") + Substr(Letters(1).End, End) + Extension"
    public string Text;

    public LambekRenameProgram(List<LambekRenameAtom> atoms)
    {
        Atoms = atoms.ToArray();
        Cost = 0;
        List<string> keys = new List<string>();
        foreach (LambekRenameAtom atom in Atoms)
        {
            Cost += atom.Cost;
            keys.Add(atom.Key);
        }
        Text = string.Join(" + ", keys);
    }

    // The new name of one file (index: its rank in the list, time: its date), or null when a piece cannot apply
    public string Apply(string name, int index, DateTime? time)
    {
        LambekRenameSource source = new LambekRenameSource(name, index, time, 0);
        StringBuilder builder = new StringBuilder();
        foreach (LambekRenameAtom atom in Atoms)
        {
            string part = atom.Evaluate(source);
            if (part == null) { return null; }
            builder.Append(part);
        }
        return builder.ToString();
    }
}

// A file to rename; Target is its new name when it is an example, and empty otherwise
public class LambekRenameItem
{
    public string Name;
    public string Target;
    public int Index;
    public DateTime? Time;

    public LambekRenameItem(string name, string target, int index, DateTime? time)
    {
        Name = name;
        Target = target == null ? "" : target;
        Index = index;
        Time = time;
    }
}

// Something that must be said before renaming: "Undefined" (the program cannot name this file), "Empty",
// "Separator" (a / or \ in the new name), "Duplicate" (two files get the same name), "Order" (the new name is
// the present name of another file that moves too)
public class LambekRenameIssue
{
    public string Kind;
    public string Name;
    public string Target;
    public string Other;

    public LambekRenameIssue(string kind, string name, string target, string other)
    {
        Kind = kind;
        Name = name;
        Target = target;
        Other = other;
    }
}

public class LambekRenameResult
{
    // The cheapest program consistent with every example; null when there is none (Reason says why)
    public LambekRenameProgram Program;
    public string Reason = "";
    // The cheapest program that gives another name to at least one file, and the first file where they differ
    public LambekRenameProgram Alternative;
    public string Question;
    public string QuestionFirst;
    public string QuestionSecond;
    public string[] Names = new string[0];
    public string[] Targets = new string[0];
    public List<LambekRenameIssue> Issues = new List<LambekRenameIssue>();
    // How much was searched
    public int AtomCount;
    public int NodeCount;
}

// Rename by example. For each example the programs that give its new name form a graph: the nodes are the places
// in the new name, and a piece that writes the characters i..j is an edge from i to j. Several examples: a node is
// one place in each new name, and a piece is an edge only when it writes the right characters in each of them
// (the intersection of the graphs). The cheapest path from the starts to the ends is the program.
public static class LambekRename
{
    const long Infinite = long.MaxValue / 4;

    static string[] Formats = new string[] {
        "yyyy-MM-dd", "yyyyMMdd", "yyyy_MM_dd", "yyyy.MM.dd", "dd-MM-yyyy", "dd.MM.yyyy", "yyyy-MM", "yyyyMM", "yyyy",
        "MM", "dd", "HHmmss", "HH-mm-ss", "HHmm", "HH-mm"
    };

    // "photo.JPG" is "photo" and ".JPG"; ".gitignore" and "README" have no extension
    public static void Split(string name, out string stem, out string extension)
    {
        int dot = name.LastIndexOf('.');
        if (dot > 0)
        {
            stem = name.Substring(0, dot);
            extension = name.Substring(dot);
        }
        else
        {
            stem = name;
            extension = "";
        }
    }

    // What the search needs to carry around
    class Search
    {
        public List<LambekRenameAtom> Atoms = new List<LambekRenameAtom>();
        // Outputs[a][k]: what atom a writes for example k
        public List<string[]> Outputs = new List<string[]>();
        public string[] Targets;
        // The atoms by what they write for the first example, so a node only tries those that can fit
        public Dictionary<string, List<int>> ByFirst = new Dictionary<string, List<int>>(StringComparer.Ordinal);
        public Dictionary<string, long> Cost = new Dictionary<string, long>(StringComparer.Ordinal);
        public Dictionary<string, int> Choice = new Dictionary<string, int>(StringComparer.Ordinal);
        public Dictionary<string, List<int>> Edges = new Dictionary<string, List<int>>(StringComparer.Ordinal);

        // The nodes met by the first search, numbered: their places, whether they are the end
        public Dictionary<string, int> NodeId = new Dictionary<string, int>(StringComparer.Ordinal);
        public List<int[]> Nodes = new List<int[]>();
        public List<bool> NodeEnd = new List<bool>();

        // Atoms that write the same thing for every example are one class: they lead to the same node.
        // NodeClasses: the classes that leave a node; NodeNext: the node each of them reaches
        public List<int> ClassOf = new List<int>();
        public Dictionary<string, int> Classes = new Dictionary<string, int>(StringComparer.Ordinal);
        public List<List<int>> NodeClasses = new List<List<int>>();
        public List<Dictionary<int, int>> NodeNext = new List<Dictionary<int, int>>();
        public List<int> Live = new List<int>();
        // How many places the atoms name (each has its number: LambekRenamePosition.Slot)
        public int Slots;

        // For the second program: what each atom writes for the file looked at, what the first program writes,
        // and for each class its cheapest atom for each thing written (the cheapest first)
        public Dictionary<int, string> Other = new Dictionary<int, string>();
        public string First;
        public int Span;
        public Dictionary<int, List<int>> Chosen = new Dictionary<int, List<int>>();
        // Same[class * Span + m]: the atoms of the class that write what the first program's name holds at m
        public Dictionary<long, List<int>> Same = new Dictionary<long, List<int>>();
        public Dictionary<long, long> OtherCost = new Dictionary<long, long>();
        public Dictionary<long, int> OtherChoice = new Dictionary<long, int>();
    }

    static string NodeKey(int[] node)
    {
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < node.Length; i++)
        {
            if (i > 0) { builder.Append(','); }
            builder.Append(node[i].ToString(CultureInfo.InvariantCulture));
        }
        return builder.ToString();
    }

    static bool AtEnd(Search search, int[] node)
    {
        for (int k = 0; k < node.Length; k++)
        {
            if (node[k] != search.Targets[k].Length) { return false; }
        }
        return true;
    }

    // The node reached by an atom, or null when it does not write what the new names hold there
    static int[] Step(Search search, int[] node, int atom)
    {
        string[] outputs = search.Outputs[atom];
        int[] next = new int[node.Length];
        for (int k = 0; k < node.Length; k++)
        {
            string output = outputs[k];
            string target = search.Targets[k];
            if (node[k] + output.Length > target.Length) { return null; }
            if (string.CompareOrdinal(target, node[k], output, 0, output.Length) != 0) { return null; }
            next[k] = node[k] + output.Length;
        }
        return next;
    }

    // The cheapest way from a node to the end. The atoms are tried in the order of their text and only a strictly
    // cheaper one replaces the choice, so among equal costs the program whose text comes first is kept
    static long Best(Search search, int[] node)
    {
        string key = NodeKey(node);
        long known;
        if (search.Cost.TryGetValue(key, out known)) { return known; }
        search.NodeId[key] = search.Nodes.Count;
        search.Nodes.Add(node);
        search.NodeEnd.Add(AtEnd(search, node));
        if (AtEnd(search, node))
        {
            search.Cost[key] = 0;
            search.Edges[key] = new List<int>();
            return 0;
        }
        long best = Infinite;
        int choice = -1;
        List<int> edges = new List<int>();

        // The atoms that write what the first new name holds here, in the order of their text
        List<int> fitting = new List<int>();
        string first = search.Targets[0];
        for (int length = 1; node[0] + length <= first.Length; length++)
        {
            List<int> group;
            if (search.ByFirst.TryGetValue(first.Substring(node[0], length), out group)) { fitting.AddRange(group); }
        }
        fitting.Sort();
        foreach (int a in fitting)
        {
            int[] next = Step(search, node, a);
            if (next == null) { continue; }
            long rest = Best(search, next);
            if (rest >= Infinite) { continue; }
            edges.Add(a);
            long cost = search.Atoms[a].Cost + rest;
            if (cost < best)
            {
                best = cost;
                choice = a;
            }
        }
        search.Cost[key] = best;
        search.Choice[key] = choice;
        search.Edges[key] = edges;
        return best;
    }

    // How far the name written so far agrees with the name the first program gives:
    // matched >= 0: that many characters are the same; -1: already different;
    // -2: the first program cannot name this file, so any program that can is different
    static int Follow(Search search, int matched, string output)
    {
        if (matched < 0) { return matched; }
        if (matched + output.Length <= search.First.Length && string.CompareOrdinal(search.First, matched, output, 0, output.Length) == 0)
        {
            return matched + output.Length;
        }
        return -1;
    }

    static long OtherKey(Search search, int node, int matched)
    {
        return (long)node * search.Span + matched + 2;
    }

    // The same search, for the cheapest program that gives another name than the first program to one more file.
    // A program that cannot name the file is never the second program: it would be a question with no answer
    static long BestOther(Search search, int node, int matched)
    {
        long key = OtherKey(search, node, matched);
        long known;
        if (search.OtherCost.TryGetValue(key, out known)) { return known; }
        if (search.NodeEnd[node])
        {
            bool differs = matched < 0 || matched != search.First.Length;
            long end = differs ? 0 : Infinite;
            search.OtherCost[key] = end;
            return end;
        }
        long best = Infinite;
        int choice = -1;
        foreach (int id in search.NodeClasses[node])
        {
            List<int> atoms;
            if (!search.Chosen.TryGetValue(id, out atoms)) { continue; }
            int next = search.NodeNext[node][id];

            // The atoms that go on writing the name of the first program
            List<int> same;
            if (matched >= 0 && search.Same.TryGetValue((long)id * search.Span + matched, out same))
            {
                foreach (int a in same)
                {
                    long rest = BestOther(search, next, matched + search.Other[a].Length);
                    if (rest >= Infinite) { continue; }
                    long cost = search.Atoms[a].Cost + rest;
                    // Among equal costs, the atom whose text comes first (the atoms are numbered in that order)
                    if (cost < best || (cost == best && a < choice))
                    {
                        best = cost;
                        choice = a;
                    }
                }
            }

            // Once the name is different, what the atom writes no longer matters: only the cheapest atom of
            // the class that makes (or leaves) it different is tried (the atoms of a class come the cheapest first)
            foreach (int a in atoms)
            {
                int after = Follow(search, matched, search.Other[a]);
                if (after >= 0) { continue; }
                long rest = BestOther(search, next, after);
                if (rest < Infinite)
                {
                    long cost = search.Atoms[a].Cost + rest;
                    if (cost < best || (cost == best && a < choice))
                    {
                        best = cost;
                        choice = a;
                    }
                }
                break;
            }
        }
        search.OtherCost[key] = best;
        search.OtherChoice[key] = choice;
        return best;
    }

    // After the first search: the atoms on some way to the end, and the classes that leave each node
    static void Prepare(Search search)
    {
        SortedSet<int> live = new SortedSet<int>();
        for (int n = 0; n < search.Nodes.Count; n++)
        {
            List<int> classes = new List<int>();
            Dictionary<int, int> reached = new Dictionary<int, int>();
            foreach (int a in search.Edges[NodeKey(search.Nodes[n])])
            {
                live.Add(a);
                int id = search.ClassOf[a];
                if (reached.ContainsKey(id)) { continue; }
                classes.Add(id);
                reached[id] = search.NodeId[NodeKey(Step(search, search.Nodes[n], a))];
            }
            search.NodeClasses.Add(classes);
            search.NodeNext.Add(reached);
        }
        search.Live = new List<int>(live);
    }

    // For one more file: what each live atom writes for it, and the cheapest atom of each class for each output
    static void Look(Search search, LambekRenameItem item, string first)
    {
        LambekRenameSource source = new LambekRenameSource(item.Name, item.Index, item.Time, search.Slots);
        search.First = first;
        search.Span = (first == null ? 0 : first.Length) + 3;
        search.Other = new Dictionary<int, string>();
        search.OtherCost = new Dictionary<long, long>();
        search.OtherChoice = new Dictionary<long, int>();
        search.Chosen = new Dictionary<int, List<int>>();
        Dictionary<string, int> cheapest = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (int a in search.Live)
        {
            string output = search.Atoms[a].Evaluate(source);
            if (output == null) { continue; }
            search.Other[a] = output;
            string key = search.ClassOf[a].ToString(CultureInfo.InvariantCulture) + ":" + output;
            int known;
            // Live is in the order of the texts, so only a strictly cheaper atom takes the place
            if (!cheapest.TryGetValue(key, out known) || search.Atoms[a].Cost < search.Atoms[known].Cost) { cheapest[key] = a; }
        }
        foreach (int a in cheapest.Values)
        {
            List<int> atoms;
            if (!search.Chosen.TryGetValue(search.ClassOf[a], out atoms))
            {
                atoms = new List<int>();
                search.Chosen[search.ClassOf[a]] = atoms;
            }
            atoms.Add(a);
        }
        foreach (List<int> atoms in search.Chosen.Values)
        {
            atoms.Sort(delegate (int x, int y)
            {
                if (search.Atoms[x].Cost != search.Atoms[y].Cost) { return search.Atoms[x].Cost.CompareTo(search.Atoms[y].Cost); }
                return x.CompareTo(y);
            });
        }

        // Where in the name of the first program each of these atoms could go on writing it
        search.Same = new Dictionary<long, List<int>>();
        if (first == null) { return; }
        foreach (int a in cheapest.Values)
        {
            string output = search.Other[a];
            for (int m = 0; m + output.Length <= first.Length; m++)
            {
                if (string.CompareOrdinal(first, m, output, 0, output.Length) != 0) { continue; }
                long key = (long)search.ClassOf[a] * search.Span + m;
                List<int> atoms;
                if (!search.Same.TryGetValue(key, out atoms))
                {
                    atoms = new List<int>();
                    search.Same[key] = atoms;
                }
                atoms.Add(a);
            }
        }
    }

    static void AddAtom(Dictionary<string, LambekRenameAtom> atoms, LambekRenameAtom atom)
    {
        if (!atoms.ContainsKey(atom.Key)) { atoms[atom.Key] = atom; }
    }

    // Every piece that could write a part of the new name of the first example. A change that changes nothing in
    // that example (lower case of "notes", a width for a number that needs no zero) is only tried when there are
    // several examples: another example may need it, but one example alone gives no reason to suppose it
    static Dictionary<string, LambekRenameAtom> Candidates(LambekRenameItem example, bool several)
    {
        Dictionary<string, LambekRenameAtom> atoms = new Dictionary<string, LambekRenameAtom>(StringComparer.Ordinal);
        string target = example.Target;
        string stem;
        string extension;
        Split(example.Name, out stem, out extension);

        // Constants: every part of the new name
        for (int i = 0; i < target.Length; i++)
        {
            for (int j = i + 1; j <= target.Length; j++) { AddAtom(atoms, LambekRenameAtom.Const(target.Substring(i, j - i))); }
        }

        // Parts of the old name, as they are or in another case, between every pair of places that name them
        List<List<LambekRenamePosition>> places = new List<List<LambekRenamePosition>>();
        for (int i = 0; i <= stem.Length; i++) { places.Add(LambekRenamePosition.At(stem, i)); }
        string[] changes = new string[] { "", "Lower", "Upper", "Title" };
        for (int i = 0; i < stem.Length; i++)
        {
            for (int j = i + 1; j <= stem.Length; j++)
            {
                string part = stem.Substring(i, j - i);
                foreach (string change in changes)
                {
                    string written = LambekRenameAtom.Change(part, change);
                    if (change != "" && written == part && !several) { continue; }
                    if (target.IndexOf(written, StringComparison.Ordinal) < 0) { continue; }
                    foreach (LambekRenamePosition from in places[i])
                    {
                        foreach (LambekRenamePosition to in places[j]) { AddAtom(atoms, LambekRenameAtom.Substr(from, to, change)); }
                    }
                }
            }
        }

        // A whole number of the old name written with another count of leading zeros ("3" as "003", "0042" as "42").
        // Number(w) writes the digits without their zeros, padded to w: so a padded number fixes w, and a number
        // without padding fits every w up to its length
        List<int[]> targetRuns = LambekRenamePosition.Runs(target, "Digits");
        foreach (int[] run in LambekRenamePosition.Runs(stem, "Digits"))
        {
            string digits = stem.Substring(run[0], run[1] - run[0]);
            string bare = digits.TrimStart('0');
            foreach (int[] other in targetRuns)
            {
                string wanted = target.Substring(other[0], other[1] - other[0]);
                if (wanted.TrimStart('0') != bare) { continue; }
                if (wanted == digits && !several) { continue; }
                bool padded = wanted.Length > Math.Max(bare.Length, 1);
                List<int> widths = new List<int>();
                if (padded) { widths.Add(wanted.Length); }
                else if (!several) { widths.Add(1); }
                else
                {
                    for (int w = 1; w <= wanted.Length; w++) { widths.Add(w); }
                }
                foreach (int width in widths)
                {
                    foreach (LambekRenamePosition from in places[run[0]])
                    {
                        foreach (LambekRenamePosition to in places[run[1]]) { AddAtom(atoms, LambekRenameAtom.Number(from, to, width)); }
                    }
                }
            }
        }

        // The extension, with its dot
        if (extension != "")
        {
            foreach (string change in new string[] { "", "Lower", "Upper" })
            {
                string written = LambekRenameAtom.Change(extension, change);
                if (change != "" && written == extension && !several) { continue; }
                if (target.IndexOf(written, StringComparison.Ordinal) >= 0) { AddAtom(atoms, LambekRenameAtom.Extension(change)); }
            }
        }

        // Counters: a whole run of digits is start + rank of the file, padded with zeros to the width
        foreach (int[] run in LambekRenamePosition.Runs(target, "Digits"))
        {
            string digits = target.Substring(run[0], run[1] - run[0]);
            int value;
            if (digits.Length > 9 || !int.TryParse(digits, NumberStyles.None, CultureInfo.InvariantCulture, out value)) { continue; }
            int start = value - example.Index;
            if (start < 0) { continue; }
            AddAtom(atoms, LambekRenameAtom.Counter(start, digits.Length));
            // Without a zero in front, a smaller width writes the same digits (every one of them with several examples)
            if (digits.Length > 1 && digits[0] != '0')
            {
                AddAtom(atoms, LambekRenameAtom.Counter(start, 1));
                for (int w = 2; several && w < digits.Length; w++) { AddAtom(atoms, LambekRenameAtom.Counter(start, w)); }
            }
        }

        // Dates of the file
        if (example.Time.HasValue)
        {
            foreach (string format in Formats)
            {
                string written = example.Time.Value.ToString(format, CultureInfo.InvariantCulture);
                if (target.IndexOf(written, StringComparison.Ordinal) >= 0) { AddAtom(atoms, LambekRenameAtom.Date(format)); }
            }
        }
        return atoms;
    }

    // The cheapest program, read from the choices of the first search
    static LambekRenameProgram Path(Search search)
    {
        List<LambekRenameAtom> atoms = new List<LambekRenameAtom>();
        int[] node = new int[search.Targets.Length];
        while (!AtEnd(search, node))
        {
            int choice = search.Choice[NodeKey(node)];
            atoms.Add(search.Atoms[choice]);
            node = Step(search, node, choice);
        }
        return new LambekRenameProgram(atoms);
    }

    // The second program, read from the choices of the search for one more file
    static LambekRenameProgram OtherPath(Search search)
    {
        List<LambekRenameAtom> atoms = new List<LambekRenameAtom>();
        int node = 0;
        int matched = search.First == null ? -2 : 0;
        while (!search.NodeEnd[node])
        {
            int choice = search.OtherChoice[OtherKey(search, node, matched)];
            matched = Follow(search, matched, search.Other[choice]);
            atoms.Add(search.Atoms[choice]);
            node = search.NodeNext[node][search.ClassOf[choice]];
        }
        return new LambekRenameProgram(atoms);
    }

    // items: every file of the list in order; those with a Target are the examples
    public static LambekRenameResult Find(LambekRenameItem[] items)
    {
        LambekRenameResult result = new LambekRenameResult();
        List<LambekRenameItem> examples = new List<LambekRenameItem>();
        foreach (LambekRenameItem item in items)
        {
            if (item.Target != "") { examples.Add(item); }
        }
        result.Names = items.Select(i => i.Name).ToArray();
        result.Targets = new string[items.Length];
        if (examples.Count == 0)
        {
            result.Reason = "No example was given.";
            return result;
        }
        foreach (LambekRenameItem example in examples)
        {
            if (example.Name == "" || example.Target.IndexOf('/') >= 0 || example.Target.IndexOf('\\') >= 0)
            {
                result.Reason = "The new name of an example cannot hold a path separator, and its old name cannot be empty.";
                return result;
            }
        }

        // The pieces come from the first example, and are kept when they also write a part of every other example
        Search search = new Search();
        search.Targets = examples.Select(e => e.Target).ToArray();
        Dictionary<string, LambekRenameAtom> candidates = Candidates(examples[0], examples.Count > 1);

        // Each place the pieces name gets a number, so it is looked for once in each file
        List<string> keys = candidates.Keys.OrderBy(k => k, StringComparer.Ordinal).ToList();
        foreach (string key in keys)
        {
            LambekRenameAtom atom = candidates[key];
            if (atom.From != null && atom.From.Slot < 0) { atom.From.Slot = search.Slots++; }
            if (atom.To != null && atom.To.Slot < 0) { atom.To.Slot = search.Slots++; }
        }
        LambekRenameSource[] sources = new LambekRenameSource[examples.Count];
        for (int k = 0; k < examples.Count; k++) { sources[k] = new LambekRenameSource(examples[k].Name, examples[k].Index, examples[k].Time, search.Slots); }
        foreach (string key in keys)
        {
            LambekRenameAtom atom = candidates[key];
            string[] outputs = new string[examples.Count];
            bool useful = true;
            for (int k = 0; k < examples.Count && useful; k++)
            {
                outputs[k] = atom.Evaluate(sources[k]);
                if (outputs[k] == null || (k == 0 && outputs[k] == "")) { useful = false; }
                else if (search.Targets[k].IndexOf(outputs[k], StringComparison.Ordinal) < 0) { useful = false; }
            }
            if (!useful) { continue; }
            List<int> group;
            if (!search.ByFirst.TryGetValue(outputs[0], out group))
            {
                group = new List<int>();
                search.ByFirst[outputs[0]] = group;
            }
            group.Add(search.Atoms.Count);
            string signature = string.Join("\u001f", outputs);
            int id;
            if (!search.Classes.TryGetValue(signature, out id))
            {
                id = search.Classes.Count;
                search.Classes[signature] = id;
            }
            search.ClassOf.Add(id);
            search.Atoms.Add(atom);
            search.Outputs.Add(outputs);
        }
        result.AtomCount = search.Atoms.Count;

        long cost = Best(search, new int[examples.Count]);
        result.NodeCount = search.Cost.Count;
        if (cost >= Infinite)
        {
            result.Reason = "No single rule gives every example its new name.";
            return result;
        }
        result.Program = Path(search);

        // The new name of every file, and what must be said about them
        for (int i = 0; i < items.Length; i++) { result.Targets[i] = result.Program.Apply(items[i].Name, items[i].Index, items[i].Time); }
        result.Issues = Check(result.Names, result.Targets);

        // The second program: for each file, the cheapest program that names it differently; the cheapest of them all
        // (then the first by text) is kept
        Prepare(search);
        LambekRenameProgram second = null;
        for (int i = 0; i < items.Length; i++)
        {
            if (items[i].Target != "") { continue; }
            Look(search, items[i], result.Targets[i]);
            long otherCost = BestOther(search, 0, result.Targets[i] == null ? -2 : 0);
            if (otherCost >= Infinite) { continue; }
            LambekRenameProgram found = OtherPath(search);
            if (second == null || found.Cost < second.Cost || (found.Cost == second.Cost && string.CompareOrdinal(found.Text, second.Text) < 0)) { second = found; }
        }
        if (second != null)
        {
            result.Alternative = second;
            for (int i = 0; i < items.Length; i++)
            {
                string other = second.Apply(items[i].Name, items[i].Index, items[i].Time);
                if (!string.Equals(other, result.Targets[i], StringComparison.Ordinal))
                {
                    result.Question = items[i].Name;
                    result.QuestionFirst = result.Targets[i];
                    result.QuestionSecond = other;
                    break;
                }
            }
        }
        return result;
    }

    // Never two equal names, an empty name or a path separator: each is reported (file names compare without case)
    public static List<LambekRenameIssue> Check(string[] names, string[] targets)
    {
        List<LambekRenameIssue> issues = new List<LambekRenameIssue>();
        Dictionary<string, int> seen = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, int> present = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        for (int i = 0; i < names.Length; i++)
        {
            if (!present.ContainsKey(names[i])) { present[names[i]] = i; }
        }
        for (int i = 0; i < names.Length; i++)
        {
            string target = targets[i];
            if (target == null)
            {
                issues.Add(new LambekRenameIssue("Undefined", names[i], null, null));
                continue;
            }
            if (target.Trim() == "")
            {
                issues.Add(new LambekRenameIssue("Empty", names[i], target, null));
                continue;
            }
            if (target.IndexOf('/') >= 0 || target.IndexOf('\\') >= 0) { issues.Add(new LambekRenameIssue("Separator", names[i], target, null)); }
            int first;
            if (seen.TryGetValue(target, out first)) { issues.Add(new LambekRenameIssue("Duplicate", names[i], target, names[first])); }
            else { seen[target] = i; }
            int holder;
            if (present.TryGetValue(target, out holder) && holder != i && !string.Equals(targets[holder], names[holder], StringComparison.OrdinalIgnoreCase))
            {
                issues.Add(new LambekRenameIssue("Order", names[i], target, names[holder]));
            }
        }
        return issues;
    }
}

// Explanation-based generalisation over LambekLogic. The proof of one fact is a tree of rules. Each rule of the tree
// is taken with fresh variables; where a body literal was proved by another rule, that rule's head is unified with
// the literal and its body takes the literal's place. What is left (facts given to the engine, tests, negations)
// is the body of the macro rule. A constant stays only where a rule wrote it: the others have become variables.
public static class LambekLearning
{
    static string ProofKey(string name, string[] terms)
    {
        return name + (char)30 + string.Join(((char)31).ToString(), terms);
    }

    static bool IsBuiltin(string name)
    {
        return Array.IndexOf(LambekLogic.Builtins, name) >= 0;
    }

    // What a term stands for after the unifications made so far
    static string Resolve(Dictionary<string, string> bound, string term)
    {
        string current = term;
        string next;
        int guard = 0;
        while (LambekLogic.IsVariable(current) && bound.TryGetValue(current, out next))
        {
            current = next;
            guard++;
            if (guard > 100000) { throw new InvalidOperationException("The unification turned in a loop."); }
        }
        return current;
    }

    // Two terms made equal: a variable takes the other term; two constants must already be equal
    static bool Unify(Dictionary<string, string> bound, string a, string b)
    {
        string x = Resolve(bound, a);
        string y = Resolve(bound, b);
        if (string.Equals(x, y, StringComparison.Ordinal)) { return true; }
        if (LambekLogic.IsVariable(x)) { bound[x] = y; return true; }
        if (LambekLogic.IsVariable(y)) { bound[y] = x; return true; }
        return false;
    }

    // State of one generalisation: the fresh variable counter, the unifications, how many rules were folded
    class Work
    {
        public LambekLogic Logic;
        public int Fresh;
        public int Steps;
        public Dictionary<string, string> Bound = new Dictionary<string, string>(StringComparer.Ordinal);
        public HashSet<string> Open = new HashSet<string>(StringComparer.Ordinal);
    }

    // The fact a body literal was matched with. The proof keeps no value where the rule says "_": the first
    // fact that fits the other values is taken (any of them proves the literal just as well)
    static string[] Row(LambekLogic logic, LambekLiteral literal, string[] values)
    {
        if (Array.IndexOf(literal.Terms, "_") < 0) { return values; }
        foreach (string[] row in logic.Get(literal.Name))
        {
            if (row.Length != values.Length) { continue; }
            bool fits = true;
            for (int t = 0; fits && t < row.Length; t++)
            {
                if (literal.Terms[t] != "_" && !string.Equals(row[t], values[t], StringComparison.Ordinal)) { fits = false; }
            }
            if (fits) { return row; }
        }
        return values;
    }

    // A rule that counts or sums is never folded into another: its value depends on all the facts, not on one proof
    static bool IsAggregate(LambekClause rule)
    {
        foreach (string term in rule.Head.Terms)
        {
            if (LambekLogic.IsAggregate(term)) { return true; }
        }
        return false;
    }

    // The rule that proved the fact, with fresh variables, its proved literals replaced by their own proofs
    static LambekLiteral Build(Work work, string name, string[] terms, List<LambekLiteral> body)
    {
        KeyValuePair<LambekClause, List<KeyValuePair<string, string[]>>> proof = work.Logic.Proofs[ProofKey(name, terms)];
        LambekClause rule = proof.Key;
        work.Steps++;
        work.Fresh++;
        string suffix = "#" + work.Fresh.ToString(CultureInfo.InvariantCulture);
        int anonymous = 0;

        // Fresh variables: X becomes X#3, and each _ becomes a variable of its own
        Func<LambekLiteral, LambekLiteral> rename = delegate (LambekLiteral literal)
        {
            string[] renamed = new string[literal.Terms.Length];
            for (int t = 0; t < renamed.Length; t++)
            {
                string term = literal.Terms[t];
                if (!LambekLogic.IsVariable(term)) { renamed[t] = term; }
                else if (term == "_")
                {
                    anonymous++;
                    renamed[t] = "_" + suffix + "." + anonymous.ToString(CultureInfo.InvariantCulture);
                }
                else { renamed[t] = term + suffix; }
            }
            return new LambekLiteral(literal.Name, renamed, literal.Negated);
        };

        LambekLiteral head = rename(rule.Head);
        for (int i = 0; i < rule.Body.Length; i++)
        {
            LambekLiteral literal = rename(rule.Body[i]);
            string[] values = proof.Value[i].Value;
            if (!rule.Body[i].Negated && !IsBuiltin(rule.Body[i].Name)) { values = Row(work.Logic, rule.Body[i], values); }
            string key = ProofKey(rule.Body[i].Name, values);

            // Tests, negations and facts given to the engine stay as they are
            bool proved = !literal.Negated && !IsBuiltin(literal.Name) && work.Logic.Proofs.ContainsKey(key) && !work.Open.Contains(key);
            if (proved && IsAggregate(work.Logic.Proofs[key].Key)) { proved = false; }
            if (!proved)
            {
                body.Add(literal);
                continue;
            }

            // A literal proved by a rule: that rule's head must be this literal, and its body takes the place
            work.Open.Add(key);
            Dictionary<string, string> saved = new Dictionary<string, string>(work.Bound, StringComparer.Ordinal);
            int savedSteps = work.Steps;
            List<LambekLiteral> inner = new List<LambekLiteral>();
            LambekLiteral innerHead = Build(work, rule.Body[i].Name, values, inner);
            bool fits = innerHead.Terms.Length == literal.Terms.Length;
            for (int t = 0; fits && t < literal.Terms.Length; t++) { fits = Unify(work.Bound, literal.Terms[t], innerHead.Terms[t]); }
            work.Open.Remove(key);
            if (fits) { body.AddRange(inner); }
            else
            {
                // Cannot happen with a proof of the engine; if it did, the literal is kept and nothing is lost
                work.Bound = saved;
                work.Steps = savedSteps;
                body.Add(literal);
            }
        }
        return head;
    }

    // The macro rule of a derived fact; null when the fact was given, not derived (nothing to generalise)
    public static LambekClause Generalise(LambekLogic logic, string name, string[] terms)
    {
        int steps;
        return Generalise(logic, name, terms, out steps);
    }

    // steps: how many rules the proof used (1: the macro rule is the rule itself)
    public static LambekClause Generalise(LambekLogic logic, string name, string[] terms, out int steps)
    {
        steps = 0;
        if (!logic.Proofs.ContainsKey(ProofKey(name, terms))) { return null; }
        if (IsAggregate(logic.Proofs[ProofKey(name, terms)].Key)) { return null; }
        Work work = new Work();
        work.Logic = logic;
        List<LambekLiteral> body = new List<LambekLiteral>();
        LambekLiteral head = Build(work, name, terms, body);
        steps = work.Steps;

        // The unifications applied everywhere
        List<LambekLiteral> all = new List<LambekLiteral>();
        all.Add(head);
        all.AddRange(body);
        List<LambekLiteral> resolved = new List<LambekLiteral>();
        foreach (LambekLiteral literal in all)
        {
            string[] done = new string[literal.Terms.Length];
            for (int t = 0; t < done.Length; t++) { done[t] = Resolve(work.Bound, literal.Terms[t]); }
            resolved.Add(new LambekLiteral(literal.Name, done, literal.Negated));
        }

        // Readable names: the name the variable had in its rule, with a number when two rules used the same name;
        // a variable met once that was "_" is "_" again
        Dictionary<string, int> uses = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (LambekLiteral literal in resolved)
        {
            foreach (string term in literal.Terms)
            {
                if (!LambekLogic.IsVariable(term)) { continue; }
                int count;
                uses.TryGetValue(term, out count);
                uses[term] = count + 1;
            }
        }
        Dictionary<string, string> names = new Dictionary<string, string>(StringComparer.Ordinal);
        HashSet<string> taken = new HashSet<string>(StringComparer.Ordinal);
        List<LambekLiteral> named = new List<LambekLiteral>();
        foreach (LambekLiteral literal in resolved)
        {
            string[] done = new string[literal.Terms.Length];
            for (int t = 0; t < done.Length; t++)
            {
                string term = literal.Terms[t];
                if (!LambekLogic.IsVariable(term)) { done[t] = term; continue; }
                string basis = term.Substring(0, term.IndexOf('#'));
                if (basis == "_" && uses[term] == 1) { done[t] = "_"; continue; }
                if (basis == "_") { basis = "V"; }
                string chosen;
                if (!names.TryGetValue(term, out chosen))
                {
                    chosen = basis;
                    int number = 2;
                    while (taken.Contains(chosen))
                    {
                        chosen = basis + number.ToString(CultureInfo.InvariantCulture);
                        number++;
                    }
                    taken.Add(chosen);
                    names[term] = chosen;
                }
                done[t] = chosen;
            }
            named.Add(new LambekLiteral(literal.Name, done, literal.Negated));
        }

        // The same literal twice says nothing more (a literal with "_" is kept: each "_" is its own variable)
        List<LambekLiteral> kept = new List<LambekLiteral>();
        HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
        for (int i = 1; i < named.Count; i++)
        {
            string text = Format(named[i]);
            if (Array.IndexOf(named[i].Terms, "_") < 0 && !seen.Add(text)) { continue; }
            kept.Add(named[i]);
        }
        return new LambekClause(named[0], kept.ToArray());
    }

    // A literal in the syntax ConvertFrom-LambekLogic reads: constants in double quotes, "" for a quote inside
    public static string Format(LambekLiteral literal)
    {
        List<string> terms = new List<string>();
        foreach (string term in literal.Terms)
        {
            if (LambekLogic.IsVariable(term)) { terms.Add(term); }
            else { terms.Add("\"" + LambekLogic.Value(term).Replace("\"", "\"\"") + "\""); }
        }
        return (literal.Negated ? "not " : "") + literal.Name + "(" + string.Join(", ", terms) + ")";
    }

    public static string Format(LambekClause clause)
    {
        if (clause.Body.Length == 0) { return Format(clause.Head) + "."; }
        return Format(clause.Head) + " :- " + string.Join(", ", clause.Body.Select(l => Format(l))) + ".";
    }
}
