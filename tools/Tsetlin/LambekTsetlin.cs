// A Tsetlin machine: it learns rules that can be read. Each class has clauses, each clause is an AND of literals (a
// feature, or its absence), and the clauses of a class vote for it (half of them) or against it (the other half).
// What it learns are small automata, one for each literal of each clause, that say whether the literal is in the
// clause: integers only, changed by a generator of numbers that starts from a fixed seed, so the same examples give
// the same rules on every machine. Granmo, "The Tsetlin Machine" (2018).
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

public class LambekTsetlin
{
    public readonly string[] Classes;
    public readonly string[] Features;
    public readonly int Clauses;
    public readonly int Threshold;
    public readonly bool Positive;
    readonly int states;
    readonly uint rarely;
    readonly int literals;
    readonly int words;
    readonly short[] automata;
    readonly ulong[] include;
    ulong seed;

    // classes and features in their order; clauses per class (even); threshold T of the votes; s, how rarely a literal
    // is forgotten; states of each automaton on each side
    public LambekTsetlin(string[] classes, string[] features, int clauses, int threshold, double s, int states, ulong seed)
        : this(classes, features, clauses, threshold, s, states, seed, false) { }

    // positive: clauses are made of features only, never of their absence (rules easier to read, on sparse features)
    public LambekTsetlin(string[] classes, string[] features, int clauses, int threshold, double s, int states, ulong seed, bool positive)
    {
        Positive = positive;
        Classes = classes;
        Features = features;
        Clauses = clauses - clauses % 2;
        Threshold = threshold;
        this.states = states;
        this.seed = seed == 0 ? 0x9E3779B97F4A7C15UL : seed;
        rarely = (uint)(4294967296.0 / s);
        literals = positive ? features.Length : 2 * features.Length;
        words = (literals + 63) / 64;
        automata = new short[classes.Length * Clauses * literals];
        include = new ulong[classes.Length * Clauses * words];
        for (int i = 0; i < automata.Length; i++) automata[i] = (short)(states + (Next() & 1));
        for (int i = 0; i < automata.Length; i++) if (automata[i] > states) Set(i, true);
    }

    uint Next()
    {
        // xorshift64*: the same numbers on every machine
        seed ^= seed >> 12;
        seed ^= seed << 25;
        seed ^= seed >> 27;
        return (uint)((seed * 2685821657736338717UL) >> 32);
    }

    void Set(int automaton, bool on)
    {
        int clause = automaton / literals;
        int literal = automaton % literals;
        int index = clause * words + literal / 64;
        ulong bit = 1UL << (literal % 64);
        if (on) include[index] |= bit; else include[index] &= ~bit;
    }

    // The literals that hold for these features: feature i is literal i, its absence literal F + i
    public ulong[] Literals(int[] present)
    {
        ulong[] value = new ulong[words];
        int features = Features.Length;
        for (int i = features; i < literals; i++) value[i / 64] |= 1UL << (i % 64);
        foreach (int feature in present)
        {
            value[feature / 64] |= 1UL << (feature % 64);
            if (Positive) continue;
            int absent = features + feature;
            value[absent / 64] &= ~(1UL << (absent % 64));
        }
        return value;
    }

    bool Fires(int clause, ulong[] value, bool learning)
    {
        bool empty = true;
        int start = clause * words;
        for (int w = 0; w < words; w++)
        {
            ulong wanted = include[start + w];
            if (wanted != 0) empty = false;
            if ((wanted & ~value[w]) != 0) return false;
        }
        return learning || !empty;
    }

    int Vote(int @class, ulong[] value, bool learning, bool[] fired)
    {
        int sum = 0;
        for (int j = 0; j < Clauses; j++)
        {
            int clause = @class * Clauses + j;
            bool fires = Fires(clause, value, learning);
            if (fired != null) fired[j] = fires;
            if (fires) sum += j % 2 == 0 ? 1 : -1;
        }
        return Math.Max(-Threshold, Math.Min(Threshold, sum));
    }

    public int[] Votes(int[] present)
    {
        ulong[] value = Literals(present);
        int[] votes = new int[Classes.Length];
        for (int k = 0; k < Classes.Length; k++) votes[k] = Vote(k, value, false, null);
        return votes;
    }

    public int Predict(int[] present)
    {
        int[] votes = Votes(present);
        int best = 0;
        for (int k = 1; k < votes.Length; k++) if (votes[k] > votes[best]) best = k;
        return best;
    }

    bool Holds(ulong[] value, int literal) { return (value[literal / 64] & (1UL << (literal % 64))) != 0; }

    void Step(int automaton, int delta)
    {
        int before = automata[automaton];
        int after = Math.Max(1, Math.Min(2 * states, before + delta));
        if (after == before) return;
        automata[automaton] = (short)after;
        if ((before > states) != (after > states)) Set(automaton, after > states);
    }

    // Type I: a clause that fires learns the literals that hold, slowly forgets the others; one that does not fire forgets
    void Remember(int clause, ulong[] value, bool fires)
    {
        int start = clause * literals;
        for (int l = 0; l < literals; l++)
        {
            if (fires && Holds(value, l)) { if (Next() >= rarely) Step(start + l, 1); }
            else if (Next() < rarely) Step(start + l, -1);
        }
    }

    // Type II: a clause that fires where it should not takes in a literal that does not hold, to stop firing there
    void Refuse(int clause, ulong[] value)
    {
        int start = clause * literals;
        for (int l = 0; l < literals; l++)
        {
            if (!Holds(value, l) && automata[start + l] <= states) Step(start + l, 1);
        }
    }

    void Feedback(int @class, ulong[] value, bool toward)
    {
        bool[] fired = new bool[Clauses];
        int vote = Vote(@class, value, true, fired);
        // The closer the vote already is to the threshold, the less the clauses are changed
        int chance = toward ? Threshold - vote : Threshold + vote;
        for (int j = 0; j < Clauses; j++)
        {
            if ((int)(Next() % (uint)(2 * Threshold)) >= chance) continue;
            int clause = @class * Clauses + j;
            bool positive = j % 2 == 0;
            if (positive == toward) Remember(clause, value, fired[j]);
            else if (fired[j]) Refuse(clause, value);
        }
    }

    // One example: its class is pushed up, one other class, drawn at random, pushed down
    public void Learn(int[] present, int truth)
    {
        ulong[] value = Literals(present);
        Feedback(truth, value, true);
        int other = (int)(Next() % (uint)(Classes.Length - 1));
        if (other >= truth) other++;
        Feedback(other, value, false);
    }

    // The clauses of a class as rules that can be read: "+ s3=ent AND NOT cap", the strongest first
    public string[] Rules(int @class)
    {
        List<string> rules = new List<string>();
        for (int j = 0; j < Clauses; j++)
        {
            int clause = @class * Clauses + j;
            List<string> parts = new List<string>();
            for (int l = 0; l < literals; l++)
            {
                if (automata[clause * literals + l] <= states) continue;
                parts.Add(l < Features.Length ? Features[l] : "NOT " + Features[l - Features.Length]);
            }
            if (parts.Count == 0) continue;
            rules.Add((j % 2 == 0 ? "+ " : "- ") + string.Join(" AND ", parts));
        }
        return rules.ToArray();
    }

    public int Included
    {
        get
        {
            int count = 0;
            foreach (short state in automata) if (state > states) count++;
            return count;
        }
    }
}
