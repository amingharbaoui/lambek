// General rules told in words ("tous les chats de ma soeur sont noirs", "aucun chien n'est un chat",
// "certains chats sont gris", "Minou est un chat"), reasoned about exactly.
// Each property is an atom; each sentence gives clauses:
// - a rule about every one ("tous", "aucun") is a clause every individual must keep;
// - a sentence about one named individual is a clause that individual must keep;
// - "certains" brings an individual of its own, imagined, that no name ever stands for.
// Individuals share nothing but the rules about every one, so the sentences can all be true together exactly when
// each individual, alone, can be given properties that keep its clauses and the rules: a small search for each,
// complete, never a guess. A conclusion follows when adding its opposite leaves no way for everything to be true;
// the smallest set of sentences that still leaves none is what the answer rests on.
using System;
using System.Collections.Generic;
using System.Linq;

// One sentence, as clauses. A literal is k + 1 for atom k, and -(k + 1) for its opposite
public sealed class LambekCategoryStatement
{
    // Clauses every individual keeps
    public List<int[]> Every = new List<int[]>();
    // Clauses one named individual keeps
    public Dictionary<string, List<int[]>> Named = new Dictionary<string, List<int[]>>(StringComparer.Ordinal);
    // Individuals of their own ("certains"), each with its clauses
    public List<List<int[]>> Witnesses = new List<List<int[]>>();

    public void AddEvery(int[] clause) { Every.Add(clause); }

    public void AddNamed(string name, int[] clause)
    {
        if (!Named.TryGetValue(name, out List<int[]> list)) { list = new List<int[]>(); Named[name] = list; }
        list.Add(clause);
    }

    // A new imagined individual, its index among this sentence's own
    public int AddWitness()
    {
        Witnesses.Add(new List<int[]>());
        return Witnesses.Count - 1;
    }

    public void AddToWitness(int witness, int[] clause) { Witnesses[witness].Add(clause); }
}

public static class LambekCategories
{
    // Whether the sentences can all be true together
    public static bool Satisfiable(LambekCategoryStatement[] statements)
    {
        if (statements == null) { throw new ArgumentNullException(nameof(statements)); }
        List<int[]> every = new List<int[]>();
        foreach (LambekCategoryStatement s in statements) { every.AddRange(s.Every); }
        // Every named individual, with what all the sentences say of it
        Dictionary<string, List<int[]>> named = new Dictionary<string, List<int[]>>(StringComparer.Ordinal);
        foreach (LambekCategoryStatement s in statements)
        {
            foreach (KeyValuePair<string, List<int[]>> pair in s.Named)
            {
                if (!named.TryGetValue(pair.Key, out List<int[]> list)) { list = new List<int[]>(); named[pair.Key] = list; }
                list.AddRange(pair.Value);
            }
        }
        foreach (List<int[]> own in named.Values) { if (!Keeps(own, every)) { return false; } }
        foreach (LambekCategoryStatement s in statements)
        {
            foreach (List<int[]> own in s.Witnesses) { if (!Keeps(own, every)) { return false; } }
        }
        return true;
    }

    // Whether the sentences give the conclusion: adding its opposite leaves no way for all to be true
    public static bool Follows(LambekCategoryStatement[] statements, LambekCategoryStatement opposite)
    {
        return !Satisfiable(With(statements, opposite));
    }

    // A smallest set of the sentences (their indices, in order) that, with the extra one, cannot all be true:
    // each sentence is taken out in turn, and left out when what remains still cannot. Null when they all can
    public static int[] Smallest(LambekCategoryStatement[] statements, LambekCategoryStatement extra)
    {
        if (statements == null) { throw new ArgumentNullException(nameof(statements)); }
        if (Satisfiable(With(statements, extra))) { return null; }
        List<int> kept = Enumerable.Range(0, statements.Length).ToList();
        for (int i = 0; i < statements.Length; i++)
        {
            List<int> without = kept.Where(k => k != i).ToList();
            if (!Satisfiable(With(without.Select(k => statements[k]).ToArray(), extra))) { kept = without; }
        }
        return kept.ToArray();
    }

    static LambekCategoryStatement[] With(LambekCategoryStatement[] statements, LambekCategoryStatement extra)
    {
        if (extra == null) { return statements; }
        LambekCategoryStatement[] all = new LambekCategoryStatement[statements.Length + 1];
        Array.Copy(statements, all, statements.Length);
        all[statements.Length] = extra;
        return all;
    }

    // One individual: some properties keep its own clauses and the rules about every one
    static bool Keeps(List<int[]> own, List<int[]> every)
    {
        List<int[]> clauses = new List<int[]>(own.Count + every.Count);
        clauses.AddRange(own);
        clauses.AddRange(every);
        return Search(clauses, new Dictionary<int, bool>());
    }

    // The search, with what is forced first: a clause with one literal left gives it
    static bool Search(List<int[]> clauses, Dictionary<int, bool> given)
    {
        Dictionary<int, bool> values = new Dictionary<int, bool>(given);
        bool changed = true;
        while (changed)
        {
            changed = false;
            foreach (int[] clause in clauses)
            {
                int open = 0;
                int last = 0;
                bool kept = false;
                foreach (int literal in clause)
                {
                    int atom = Math.Abs(literal);
                    if (values.TryGetValue(atom, out bool value))
                    {
                        if (value == (literal > 0)) { kept = true; break; }
                    }
                    else { open++; last = literal; }
                }
                if (kept) { continue; }
                if (open == 0) { return false; }
                if (open == 1) { values[Math.Abs(last)] = last > 0; changed = true; }
            }
        }
        // The first atom still open, tried both ways
        foreach (int[] clause in clauses)
        {
            bool kept = false;
            int free = 0;
            foreach (int literal in clause)
            {
                int atom = Math.Abs(literal);
                if (values.TryGetValue(atom, out bool value)) { if (value == (literal > 0)) { kept = true; break; } }
                else if (free == 0) { free = literal; }
            }
            if (kept || free == 0) { continue; }
            int chosen = Math.Abs(free);
            values[chosen] = free > 0;
            if (Search(clauses, values)) { return true; }
            values[chosen] = free <= 0;
            return Search(clauses, values);
        }
        return true;
    }
}
