// The blackboard of Lambek: the one place where everything it holds is kept, once, with what it is (told, read,
// deduced, assumed, imagined), where it comes from, the day it came, and what it rests on. A thing and its contrary
// both stay: nothing is ever erased because something else says the opposite (four-valued logic of Belnap).
using System;
using System.Collections.Generic;
using System.Text;

// One thing on the board
public sealed class LambekBoardEntry
{
    // In the order things came, from 1
    public int Id;
    // told: the user said it; read: found in a document; deduced: proved from others;
    // assumed: taken as so until said otherwise; imagined: an idea, never presented as a fact
    public string Status;
    // Who it comes from: "user", "journal" (told in an earlier conversation), or the name of an intelligence
    public string Source;
    // The day it came, yyyy-MM-dd
    public string Day;
    // What it says, the same whatever the order of its parts: two things with the same key and opposite signs are contrary
    public string Key;
    public bool Negated;
    // The key of the thing it is the reason of ("... because ..."), if any
    public string ReasonFor;
    // How it was written down, to say it once when it is held twice (this conversation and the journal)
    public string Form;
    // The entries it rests on, for a thing deduced
    public int[] Basis = new int[0];
    // The thing itself, as the rest of Lambek knows it
    public object Payload;
}

public sealed class LambekBoard
{
    // From the strongest to the weakest: when two things disagree, the stronger is the one to act on
    public static readonly string[] Statuses = { "told", "read", "deduced", "assumed", "imagined" };

    private readonly List<LambekBoardEntry> entries = new List<LambekBoardEntry>();
    private readonly Dictionary<object, LambekBoardEntry> byPayload = new Dictionary<object, LambekBoardEntry>(ReferenceEqualityComparer.Instance);
    private int next = 1;

    public int Count { get { return entries.Count; } }

    public LambekBoardEntry[] Entries() { return entries.ToArray(); }

    // Puts a thing on the board; a thing already there is kept as it is
    public LambekBoardEntry Put(object payload, string status, string source, string day, string core, bool negated, string reasonFor, string form, int[] basis)
    {
        if (payload == null) { throw new ArgumentNullException("payload"); }
        if (Array.IndexOf(Statuses, status) < 0) { throw new ArgumentException("Unknown status: " + status + ". Known: " + string.Join(", ", Statuses) + "."); }
        LambekBoardEntry found;
        if (byPayload.TryGetValue(payload, out found)) { return found; }
        foreach (int id in basis ?? new int[0])
        {
            if (id < 1 || id >= next) { throw new ArgumentException("A thing can only rest on things already on the board."); }
        }
        LambekBoardEntry entry = new LambekBoardEntry
        {
            Id = next++,
            Status = status,
            Source = source ?? "",
            Day = day ?? "",
            Key = string.IsNullOrEmpty(core) ? null : Canonical(core),
            Negated = negated,
            ReasonFor = string.IsNullOrEmpty(reasonFor) ? null : Canonical(reasonFor),
            Form = form ?? "",
            Basis = basis ?? new int[0],
            Payload = payload,
        };
        entries.Add(entry);
        byPayload[payload] = entry;
        return entry;
    }

    public LambekBoardEntry Entry(object payload)
    {
        LambekBoardEntry found;
        if (payload != null && byPayload.TryGetValue(payload, out found)) { return found; }
        return null;
    }

    // Takes off what came from one source, to read it again (the journal read again from the disk)
    public void Drop(string source)
    {
        entries.RemoveAll(e => e.Source == source);
        byPayload.Clear();
        foreach (LambekBoardEntry e in entries) { byPayload[e.Payload] = e; }
    }

    // "Forget what I told you": everything goes
    public void Clear()
    {
        entries.Clear();
        byPayload.Clear();
    }

    // The things among these that say the opposite of what this key says: the same key, the other sign.
    // In the order they are given, once each by the way they were written and the day they came
    public object[] Contraries(object payload, string core, bool negated, object[] among)
    {
        List<object> found = new List<object>();
        if (string.IsNullOrEmpty(core) || among == null) { return found.ToArray(); }
        string key = Canonical(core);
        HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (object other in among)
        {
            LambekBoardEntry e = Entry(other);
            if (e == null) { continue; }
            if (!seen.Add(e.Form + "|" + e.Day)) { continue; }
            if (ReferenceEquals(other, payload) || e.Key == null) { continue; }
            if (e.Key == key && e.Negated != negated) { found.Add(other); }
        }
        return found.ToArray();
    }

    // The things among these given as the reason of what this key says, once each by the way they were written
    public object[] Reasons(string core, object[] among)
    {
        List<object> found = new List<object>();
        if (string.IsNullOrEmpty(core) || among == null) { return found.ToArray(); }
        string key = Canonical(core);
        HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (object other in among)
        {
            LambekBoardEntry e = Entry(other);
            if (e == null || e.ReasonFor == null || e.ReasonFor != key) { continue; }
            if (seen.Add(e.Form)) { found.Add(other); }
        }
        return found.ToArray();
    }

    // What the things among these make of a key, in the four values of Belnap:
    // "true" (only said so), "false" (only said not), "both" (said both ways), "none" (never said)
    public string Value(string core, object[] among)
    {
        if (string.IsNullOrEmpty(core) || among == null) { return "none"; }
        string key = Canonical(core);
        bool yes = false, no = false;
        foreach (object other in among)
        {
            LambekBoardEntry e = Entry(other);
            if (e == null || e.Key != key || e.Status == "imagined") { continue; }
            if (e.Negated) { no = true; } else { yes = true; }
        }
        if (yes && no) { return "both"; }
        if (yes) { return "true"; }
        if (no) { return "false"; }
        return "none";
    }

    // The one to act on when things disagree about a key: the strongest status, then the latest day, then the latest come.
    // The others stay on the board
    public object Preferred(string core, object[] among)
    {
        if (string.IsNullOrEmpty(core) || among == null) { return null; }
        string key = Canonical(core);
        LambekBoardEntry best = null;
        foreach (object other in among)
        {
            LambekBoardEntry e = Entry(other);
            if (e == null || e.Key != key) { continue; }
            if (best == null || Stronger(e, best)) { best = e; }
        }
        return best == null ? null : best.Payload;
    }

    private static bool Stronger(LambekBoardEntry a, LambekBoardEntry b)
    {
        int ra = Array.IndexOf(Statuses, a.Status), rb = Array.IndexOf(Statuses, b.Status);
        if (ra != rb) { return ra < rb; }
        int day = string.CompareOrdinal(a.Day, b.Day);
        if (day != 0) { return day > 0; }
        return a.Id > b.Id;
    }

    // The same meaning whatever the order its parts were said in: "lives in Lyon with Marie" and "lives with Marie in Lyon".
    // The parts of every term are sorted (ordinal), at every depth; what follows "|" (the day) stays as it is.
    // A text that does not read as terms is kept as it is
    public static string Canonical(string core)
    {
        if (string.IsNullOrEmpty(core)) { return core; }
        int bar = TopLevelBar(core);
        string term = bar < 0 ? core : core.Substring(0, bar);
        string rest = bar < 0 ? "" : core.Substring(bar);
        int at = 0;
        string sorted = Term(term, ref at);
        if (sorted == null || at != term.Length) { return core; }
        return sorted + rest;
    }

    private static int TopLevelBar(string text)
    {
        int depth = 0;
        bool quoted = false;
        for (int i = 0; i < text.Length; i++)
        {
            char c = text[i];
            if (c == '"') { quoted = !quoted; continue; }
            if (quoted) { continue; }
            if (c == '(') { depth++; }
            else if (c == ')') { depth--; }
            else if (c == '|' && depth == 0) { return i; }
        }
        return -1;
    }

    // name(part, part, ...) | "text" | name; null when it does not read
    private static string Term(string text, ref int at)
    {
        SkipSpaces(text, ref at);
        if (at >= text.Length) { return null; }
        if (text[at] == '"')
        {
            int start = at++;
            while (at < text.Length)
            {
                if (text[at] == '"')
                {
                    // "" is a quote inside the text
                    if (at + 1 < text.Length && text[at + 1] == '"') { at += 2; continue; }
                    at++;
                    return text.Substring(start, at - start);
                }
                at++;
            }
            return null;
        }
        StringBuilder name = new StringBuilder();
        while (at < text.Length && text[at] != '(' && text[at] != ')' && text[at] != ',' && text[at] != '"')
        {
            name.Append(text[at]);
            at++;
        }
        string head = name.ToString().Trim();
        if (head.Length == 0) { return null; }
        if (at >= text.Length || text[at] != '(') { return head; }
        at++;
        List<string> parts = new List<string>();
        SkipSpaces(text, ref at);
        if (at < text.Length && text[at] == ')') { at++; return head + "()"; }
        while (true)
        {
            string part = Term(text, ref at);
            if (part == null) { return null; }
            parts.Add(part);
            SkipSpaces(text, ref at);
            if (at >= text.Length) { return null; }
            if (text[at] == ',') { at++; continue; }
            if (text[at] == ')') { at++; break; }
            return null;
        }
        parts.Sort(StringComparer.Ordinal);
        return head + "(" + string.Join(", ", parts) + ")";
    }

    private static void SkipSpaces(string text, ref int at)
    {
        while (at < text.Length && text[at] == ' ') { at++; }
    }
}
