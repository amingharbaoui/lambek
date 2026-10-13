// Problems told in words, solved exactly and checked. Two kinds:
// - quantities ("Marie a 2 ans de plus que Paul, a eux deux ils ont 30 ans"): linear equations over the rationals,
//   solved by Gauss-Jordan; every quantity the equations fix is given, the others are said to be free, and a set of
//   equations that cannot all hold is reduced to a smallest one that still cannot;
// - places in a row ("Alice n'est pas a cote de Bob"): every order of the people is tried, the ones that keep every
//   condition are the answers, and when none does, a smallest set of conditions that cannot all hold is given.
// Nothing is guessed: an answer is a value every equation gives back, or an order every condition accepts.
using System;
using System.Collections.Generic;
using System.Linq;

// sum(Coefficients[i] * Names[i]) = Constant
public sealed class LambekProblemEquation
{
    public string[] Names = new string[0];
    public LambekRational[] Coefficients = new LambekRational[0];
    public LambekRational Constant = LambekRational.Zero;

    public static LambekProblemEquation Make(string[] names, LambekRational[] coefficients, LambekRational constant)
    {
        if (names == null || coefficients == null || names.Length != coefficients.Length) { throw new ArgumentException("One coefficient for each quantity."); }
        return new LambekProblemEquation { Names = names, Coefficients = coefficients, Constant = constant };
    }

    // The value of the left side, the quantities given
    public LambekRational Left(IDictionary<string, LambekRational> values)
    {
        LambekRational sum = LambekRational.Zero;
        for (int i = 0; i < Names.Length; i++) { sum = sum + Coefficients[i] * values[Names[i]]; }
        return sum;
    }

    public bool Knows(IDictionary<string, LambekRational> values)
    {
        foreach (string name in Names) { if (!values.ContainsKey(name)) { return false; } }
        return true;
    }

    public bool Holds(IDictionary<string, LambekRational> values) { return Knows(values) && Left(values).CompareTo(Constant) == 0; }
}

public sealed class LambekProblemSolution
{
    // "solved": every quantity is fixed; "partial": some are not; "none": the equations cannot all hold
    public string Kind;
    public Dictionary<string, LambekRational> Values = new Dictionary<string, LambekRational>(StringComparer.Ordinal);
    public string[] Free = new string[0];
    // When none: the indices of a smallest set of equations that cannot all hold
    public int[] Conflict = new int[0];
}

// One condition on a row of people. Kind: left (A somewhere left of B), justleft (A just left of B), right, justright,
// next (side by side), between (A somewhere between B and C), at (A at Position, 1 the first), last, middle, end
public sealed class LambekPlace
{
    public string Kind;
    public string A;
    public string B;
    public string C;
    public int Position;
    public bool Negated;

    public static LambekPlace Make(string kind, string a, string b, string c, int position, bool negated)
    {
        string[] kinds = { "left", "justleft", "right", "justright", "next", "between", "at", "last", "middle", "end" };
        if (Array.IndexOf(kinds, kind) < 0) { throw new ArgumentException("Unknown place: " + kind); }
        // (an empty name is none: PowerShell gives "" for a missing one)
        return new LambekPlace { Kind = kind, A = a, B = string.IsNullOrEmpty(b) ? null : b, C = string.IsNullOrEmpty(c) ? null : c, Position = position, Negated = negated };
    }

    // Whether the row keeps this condition (positions from 0, left to right)
    public bool Holds(IDictionary<string, int> at, int count)
    {
        int a = at[A];
        int b = B == null ? -1 : at[B];
        int c = C == null ? -1 : at[C];
        bool holds;
        switch (Kind)
        {
            case "left": holds = a < b; break;
            case "justleft": holds = a + 1 == b; break;
            case "right": holds = a > b; break;
            case "justright": holds = a == b + 1; break;
            case "next": holds = Math.Abs(a - b) == 1; break;
            case "between": holds = (b < a && a < c) || (c < a && a < b); break;
            case "at": holds = a == Position - 1; break;
            case "last": holds = a == count - 1; break;
            case "middle": holds = count % 2 == 1 && a == count / 2; break;
            case "end": holds = a == 0 || a == count - 1; break;
            default: holds = false; break;
        }
        return Negated ? !holds : holds;
    }
}

public sealed class LambekArrangement
{
    // Every order that keeps every condition, up to the limit asked, each from left to right
    public List<string[]> Orders = new List<string[]>();
    // How many there are in all (the orders kept may be fewer)
    public int Count;
    // How many orders were tried: n!
    public int Tried;
    // When there are none: the indices of a smallest set of conditions that cannot all hold
    public int[] Conflict = new int[0];
}

public static class LambekProblems
{
    public static LambekProblemSolution Solve(LambekProblemEquation[] equations)
    {
        LambekProblemSolution solution = Reduce(equations);
        if (solution.Kind == "none") { solution.Conflict = Smallest(equations.Length, kept => Reduce(kept.Select(i => equations[i]).ToArray()).Kind == "none"); }
        return solution;
    }

    // Gauss-Jordan on the augmented matrix, exact. A quantity is fixed when its row has nothing left on the free ones
    static LambekProblemSolution Reduce(LambekProblemEquation[] equations)
    {
        List<string> names = new List<string>();
        foreach (LambekProblemEquation e in equations) { foreach (string n in e.Names) { if (!names.Contains(n)) { names.Add(n); } } }
        int rows = equations.Length;
        int columns = names.Count;
        LambekRational[,] m = new LambekRational[rows, columns + 1];
        for (int i = 0; i < rows; i++)
        {
            for (int j = 0; j <= columns; j++) { m[i, j] = LambekRational.Zero; }
            for (int k = 0; k < equations[i].Names.Length; k++)
            {
                int j = names.IndexOf(equations[i].Names[k]);
                m[i, j] = m[i, j] + equations[i].Coefficients[k];
            }
            m[i, columns] = equations[i].Constant;
        }
        List<int> pivots = new List<int>();
        int row = 0;
        for (int j = 0; j < columns && row < rows; j++)
        {
            int found = -1;
            for (int i = row; i < rows; i++) { if (!m[i, j].IsZero) { found = i; break; } }
            if (found < 0) { continue; }
            for (int k = 0; k <= columns; k++) { LambekRational t = m[row, k]; m[row, k] = m[found, k]; m[found, k] = t; }
            LambekRational p = m[row, j];
            for (int k = 0; k <= columns; k++) { m[row, k] = m[row, k] / p; }
            for (int i = 0; i < rows; i++)
            {
                if (i == row || m[i, j].IsZero) { continue; }
                LambekRational f = m[i, j];
                for (int k = 0; k <= columns; k++) { m[i, k] = m[i, k] - f * m[row, k]; }
            }
            pivots.Add(j);
            row++;
        }
        LambekProblemSolution solution = new LambekProblemSolution();
        // A row with nothing on the left and something on the right: 0 = c
        for (int i = row; i < rows; i++)
        {
            if (!m[i, columns].IsZero) { solution.Kind = "none"; return solution; }
        }
        List<string> free = new List<string>();
        for (int j = 0; j < columns; j++) { if (!pivots.Contains(j)) { free.Add(names[j]); } }
        for (int r = 0; r < pivots.Count; r++)
        {
            bool fixedValue = true;
            for (int j = 0; j < columns; j++) { if (!pivots.Contains(j) && !m[r, j].IsZero) { fixedValue = false; break; } }
            if (fixedValue) { solution.Values[names[pivots[r]]] = m[r, columns]; }
            else { free.Add(names[pivots[r]]); }
        }
        solution.Free = names.Where(n => !solution.Values.ContainsKey(n)).ToArray();
        solution.Kind = solution.Free.Length == 0 ? "solved" : "partial";
        return solution;
    }

    public static LambekArrangement Arrange(string[] people, LambekPlace[] conditions, int limit)
    {
        if (people == null || people.Length < 2) { throw new ArgumentException("At least two people to place."); }
        if (people.Length > 8) { throw new ArgumentException("At most 8 people to place."); }
        foreach (LambekPlace c in conditions)
        {
            foreach (string name in new[] { c.A, c.B, c.C })
            {
                if (name != null && Array.IndexOf(people, name) < 0) { throw new ArgumentException("Not among the people: " + name); }
            }
        }
        LambekArrangement result = Count(people, conditions, limit);
        if (result.Count == 0) { result.Conflict = Smallest(conditions.Length, kept => Count(people, kept.Select(i => conditions[i]).ToArray(), 0).Count == 0); }
        return result;
    }

    static LambekArrangement Count(string[] people, LambekPlace[] conditions, int limit)
    {
        LambekArrangement result = new LambekArrangement();
        int n = people.Length;
        int[] order = Enumerable.Range(0, n).ToArray();
        Dictionary<string, int> at = new Dictionary<string, int>(StringComparer.Ordinal);
        do
        {
            result.Tried++;
            for (int i = 0; i < n; i++) { at[people[order[i]]] = i; }
            bool keeps = true;
            foreach (LambekPlace c in conditions) { if (!c.Holds(at, n)) { keeps = false; break; } }
            if (!keeps) { continue; }
            result.Count++;
            if (result.Orders.Count < limit) { result.Orders.Add(order.Select(i => people[i]).ToArray()); }
        }
        while (NextPermutation(order));
        return result;
    }

    // The orders in lexicographic order: the same answers, in the same order, every time
    static bool NextPermutation(int[] a)
    {
        int i = a.Length - 2;
        while (i >= 0 && a[i] >= a[i + 1]) { i--; }
        if (i < 0) { return false; }
        int j = a.Length - 1;
        while (a[j] <= a[i]) { j--; }
        int t = a[i]; a[i] = a[j]; a[j] = t;
        Array.Reverse(a, i + 1, a.Length - i - 1);
        return true;
    }

    // A smallest set that still fails: each one is left out in turn, and stays out when the rest still fails
    // (deletion filter: no smaller set inside it fails, though another set elsewhere might be smaller)
    static int[] Smallest(int count, Func<List<int>, bool> fails)
    {
        List<int> kept = Enumerable.Range(0, count).ToList();
        for (int i = 0; i < count; i++)
        {
            List<int> without = kept.Where(k => k != i).ToList();
            if (without.Count < kept.Count && fails(without)) { kept = without; }
        }
        return kept.ToArray();
    }
}
