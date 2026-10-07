// The hot loops of Lambek, compiled once when the module loads.
// Same algorithms as the PowerShell they replace, only faster.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

// A literal of Datalog: name(Terms), maybe under "not". Constants start with \0, variables with a capital or _
public class LambekLiteral
{
    public string Name;
    public string[] Terms;
    public bool Negated;

    public LambekLiteral(string name, string[] terms, bool negated)
    {
        Name = name;
        Terms = terms;
        Negated = negated;
    }
}

// A clause: a fact (no body) or a rule head :- body
public class LambekClause
{
    public LambekLiteral Head;
    public LambekLiteral[] Body;

    public LambekClause(LambekLiteral head, LambekLiteral[] body)
    {
        Head = head;
        Body = body;
    }
}

// A small Datalog: facts, rules with "not", evaluated bottom-up until nothing new comes.
// It always ends (no function symbols, finitely many constants) and gives one answer (stratified negation).
public class LambekLogic
{
    // Facts by predicate: the rows, and their keys to find them again
    public Dictionary<string, List<string[]>> Rows = new Dictionary<string, List<string[]>>(StringComparer.Ordinal);
    public Dictionary<string, HashSet<string>> Seen = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
    public List<LambekClause> Rules = new List<LambekClause>();

    public static string[] Builtins = new string[] { "under", "same", "eq", "neq", "lt", "le", "gt", "ge" };

    // How each fact was first derived: the rule and the facts of its body (for "why?")
    public Dictionary<string, KeyValuePair<LambekClause, List<KeyValuePair<string, string[]>>>> Proofs = new Dictionary<string, KeyValuePair<LambekClause, List<KeyValuePair<string, string[]>>>>(StringComparer.Ordinal);

    // An aggregate term in a head: "#count:X", "#sum:X", "#min:X", "#max:X"
    public static bool IsAggregate(string term)
    {
        return term.StartsWith("#", StringComparison.Ordinal) && term.IndexOf(':') > 1;
    }

    static int Compare(string a, string b)
    {
        // Numbers as numbers, the rest as text
        double x, y;
        if (double.TryParse(a, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out x) &&
            double.TryParse(b, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out y)) return x.CompareTo(y);
        return string.CompareOrdinal(a, b);
    }

    public bool Add(string name, string[] terms)
    {
        if (!Rows.ContainsKey(name))
        {
            Rows[name] = new List<string[]>();
            Seen[name] = new HashSet<string>(StringComparer.Ordinal);
        }
        if (!Seen[name].Add(string.Join(((char)31).ToString(), terms))) { return false; }
        Rows[name].Add(terms);
        return true;
    }

    public List<string[]> Get(string name)
    {
        List<string[]> rows;
        if (Rows.TryGetValue(name, out rows)) { return rows; }
        return new List<string[]>();
    }

    public static bool IsVariable(string term)
    {
        return term.Length > 0 && (char.IsUpper(term[0]) || term[0] == '_') && term[0] != (char)0;
    }

    // A constant is kept with a leading \0, so "C:\Windows" and a variable named C never mix
    public static string Value(string term)
    {
        if (term.Length > 0 && term[0] == (char)0) { return term.Substring(1); }
        return term;
    }

    // Paths: the same folder, or one inside the other, without regard to case or the last separator
    public static string Folder(string path)
    {
        string clean = path.Replace('/', '\\').TrimEnd('\\');
        if (Regex.IsMatch(clean, "^[A-Za-z]:$")) { clean += "\\"; }
        if (clean == "") { clean = "\\"; }
        return clean.ToLowerInvariant();
    }

    static bool IsBuiltin(string name)
    {
        return Array.IndexOf(Builtins, name) >= 0;
    }

    public static bool Builtin(string name, string[] values)
    {
        switch (name)
        {
            case "eq": return string.Equals(values[0], values[1], StringComparison.Ordinal);
            case "lt": return Compare(values[0], values[1]) < 0;
            case "le": return Compare(values[0], values[1]) <= 0;
            case "gt": return Compare(values[0], values[1]) > 0;
            case "ge": return Compare(values[0], values[1]) >= 0;
            case "neq": return !string.Equals(values[0], values[1], StringComparison.Ordinal);
            case "same": return Folder(values[0]) == Folder(values[1]);
            case "under":
                string inner = Folder(values[0]);
                string outer = Folder(values[1]);
                if (inner == outer) { return true; }
                if (!outer.EndsWith("\\", StringComparison.Ordinal)) { outer += "\\"; }
                return inner.StartsWith(outer, StringComparison.Ordinal);
        }
        return false;
    }

    // Every way to satisfy the body from literal i on, with the bindings so far; delta: the only rows allowed at position d
    public void Match(object[] body, int i, Hashtable binding, int d, List<string[]> delta, List<Hashtable> found)
    {
        if (i >= body.Length)
        {
            found.Add((Hashtable)binding.Clone());
            return;
        }
        LambekLiteral literal = (LambekLiteral)body[i];
        // A term not bound yet stays null
        string[] values = new string[literal.Terms.Length];
        bool bound = true;
        for (int t = 0; t < literal.Terms.Length; t++)
        {
            string term = literal.Terms[t];
            if (IsVariable(term))
            {
                if (binding.ContainsKey(term)) { values[t] = (string)binding[term]; } else { values[t] = null; bound = false; }
            }
            else { values[t] = Value(term); }
        }

        // Built-in tests and negations need every term bound
        if (IsBuiltin(literal.Name))
        {
            if (!bound) { throw new InvalidOperationException("The test " + literal.Name + " needs its values first."); }
            if (Builtin(literal.Name, values) != literal.Negated) { Match(body, i + 1, binding, d, delta, found); }
            return;
        }
        if (literal.Negated)
        {
            if (!bound) { throw new InvalidOperationException("The negation of " + literal.Name + " needs its values first."); }
            string key = string.Join(((char)31).ToString(), values);
            bool has = Seen.ContainsKey(literal.Name) && Seen[literal.Name].Contains(key);
            if (!has) { Match(body, i + 1, binding, d, delta, found); }
            return;
        }

        List<string[]> pool = Get(literal.Name);
        if (i == d) { pool = delta; }
        foreach (string[] row in pool)
        {
            if (row.Length != values.Length) { continue; }
            Hashtable next = binding;
            bool copied = false;
            bool fits = true;
            for (int t = 0; t < values.Length; t++)
            {
                if (values[t] != null)
                {
                    if (!string.Equals(values[t], row[t], StringComparison.Ordinal)) { fits = false; break; }
                }
                else
                {
                    string name = literal.Terms[t];
                    if (name == "_") { continue; }
                    if (!copied) { next = (Hashtable)binding.Clone(); copied = true; }
                    if (next.ContainsKey(name))
                    {
                        if (!string.Equals((string)next[name], row[t], StringComparison.Ordinal)) { fits = false; break; }
                    }
                    else { next[name] = row[t]; }
                }
            }
            if (fits) { Match(body, i + 1, next, d, delta, found); }
        }
    }

    public string[] Head(LambekClause rule, Hashtable binding)
    {
        string[] terms = new string[rule.Head.Terms.Length];
        for (int t = 0; t < terms.Length; t++)
        {
            string term = rule.Head.Terms[t];
            if (IsVariable(term))
            {
                if (!binding.ContainsKey(term)) { throw new InvalidOperationException("The rule for " + rule.Head.Name + " leaves " + term + " unbound."); }
                terms[t] = (string)binding[term];
            }
            else { terms[t] = Value(term); }
        }
        return terms;
    }

    // Strata: a predicate comes after what it uses, strictly after what it negates
    public List<string[]> Strata()
    {
        Dictionary<string, int> level = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (LambekClause rule in Rules)
        {
            level[rule.Head.Name] = 0;
            foreach (LambekLiteral literal in rule.Body) { if (!level.ContainsKey(literal.Name)) { level[literal.Name] = 0; } }
        }
        bool changed = true;
        int rounds = 0;
        while (changed)
        {
            changed = false;
            rounds++;
            if (rounds > level.Count + 1) { throw new InvalidOperationException("The rules use \"not\" in a loop: they cannot be ordered."); }
            foreach (LambekClause rule in Rules)
            {
                foreach (LambekLiteral literal in rule.Body)
                {
                    if (IsBuiltin(literal.Name)) { continue; }
                    int need = level[literal.Name];
                    if (literal.Negated || rule.Head.Terms.Any(IsAggregate)) { need++; }
                    if (level[rule.Head.Name] < need)
                    {
                        level[rule.Head.Name] = need;
                        changed = true;
                    }
                }
            }
        }
        List<string[]> strata = new List<string[]>();
        int top = 0;
        foreach (int value in level.Values) { if (value > top) { top = value; } }
        for (int s = 0; s <= top; s++)
        {
            List<string> names = new List<string>();
            foreach (KeyValuePair<string, int> item in level) { if (item.Value == s) { names.Add(item.Key); } }
            names.Sort(StringComparer.Ordinal);
            strata.Add(names.ToArray());
        }
        return strata;
    }

    // Semi-naive evaluation: after the first round, each round only joins with the facts found in the round before
    public void Run()
    {
        foreach (string[] stratum in Strata())
        {
            List<LambekClause> chosen = new List<LambekClause>();
            foreach (LambekClause rule in Rules) { if (Array.IndexOf(stratum, rule.Head.Name) >= 0) { chosen.Add(rule); } }
            if (chosen.Count == 0) { continue; }

            // Aggregates: their body is complete (it sits in a lower stratum), so each group is counted once
            foreach (LambekClause rule in chosen.Where(r => r.Head.Terms.Any(IsAggregate)).ToList())
            {
                Aggregate(rule);
                chosen.Remove(rule);
            }
            if (chosen.Count == 0) { continue; }

            Dictionary<string, List<string[]>> delta = new Dictionary<string, List<string[]>>(StringComparer.Ordinal);
            foreach (LambekClause rule in chosen)
            {
                List<Hashtable> found = new List<Hashtable>();
                Match(rule.Body, 0, new Hashtable(), -1, null, found);
                foreach (Hashtable binding in found)
                {
                    string[] terms = Head(rule, binding);
                    if (Add(rule.Head.Name, terms))
                    {
                        Remember(rule, binding, terms);
                        if (!delta.ContainsKey(rule.Head.Name)) { delta[rule.Head.Name] = new List<string[]>(); }
                        delta[rule.Head.Name].Add(terms);
                    }
                }
            }

            int rounds = 0;
            while (delta.Count > 0)
            {
                // Datalog always ends; the guard only turns a mistake in this code into an error instead of a hang
                rounds++;
                if (rounds > 100000) { throw new InvalidOperationException("The rules did not settle."); }
                Dictionary<string, List<string[]>> next = new Dictionary<string, List<string[]>>(StringComparer.Ordinal);
                foreach (LambekClause rule in chosen)
                {
                    for (int d = 0; d < rule.Body.Length; d++)
                    {
                        LambekLiteral literal = rule.Body[d];
                        if (literal.Negated || !delta.ContainsKey(literal.Name)) { continue; }
                        List<Hashtable> found = new List<Hashtable>();
                        Match(rule.Body, 0, new Hashtable(), d, delta[literal.Name], found);
                        foreach (Hashtable binding in found)
                        {
                            string[] terms = Head(rule, binding);
                            if (Add(rule.Head.Name, terms))
                            {
                                Remember(rule, binding, terms);
                                if (!next.ContainsKey(rule.Head.Name)) { next[rule.Head.Name] = new List<string[]>(); }
                                next[rule.Head.Name].Add(terms);
                            }
                        }
                    }
                }
                delta = next;
            }
        }
    }

    static string Key(string name, string[] terms)
    {
        return name + (char)30 + string.Join(((char)31).ToString(), terms);
    }

    void Remember(LambekClause rule, Hashtable binding, string[] terms)
    {
        // The facts of the body, as they were bound (the tests and negations are said with them)
        List<KeyValuePair<string, string[]>> body = new List<KeyValuePair<string, string[]>>();
        foreach (LambekLiteral literal in rule.Body)
        {
            string[] values = new string[literal.Terms.Length];
            for (int t = 0; t < values.Length; t++)
            {
                string term = literal.Terms[t];
                values[t] = IsVariable(term) ? (binding.ContainsKey(term) ? (string)binding[term] : "_") : Value(term);
            }
            body.Add(new KeyValuePair<string, string[]>((literal.Negated ? "not " : "") + literal.Name, values));
        }
        string key = Key(rule.Head.Name, terms);
        if (!Proofs.ContainsKey(key)) Proofs[key] = new KeyValuePair<LambekClause, List<KeyValuePair<string, string[]>>>(rule, body);
    }

    // Aggregates over the whole body: group by the other terms of the head, then count the distinct values,
    // or sum, or take the smallest or the largest (numbers as numbers)
    void Aggregate(LambekClause rule)
    {
        List<Hashtable> found = new List<Hashtable>();
        Match(rule.Body, 0, new Hashtable(), -1, null, found);
        Dictionary<string, List<Hashtable>> groups = new Dictionary<string, List<Hashtable>>(StringComparer.Ordinal);
        Dictionary<string, string[]> firsts = new Dictionary<string, string[]>(StringComparer.Ordinal);
        foreach (Hashtable binding in found)
        {
            string[] key = rule.Head.Terms.Select(t => IsAggregate(t) ? "" : (IsVariable(t) ? (string)binding[t] : Value(t))).ToArray();
            string text = string.Join(((char)31).ToString(), key);
            if (!groups.ContainsKey(text)) { groups[text] = new List<Hashtable>(); firsts[text] = key; }
            groups[text].Add(binding);
        }
        foreach (string text in groups.Keys.OrderBy(k => k, StringComparer.Ordinal))
        {
            string[] terms = (string[])firsts[text].Clone();
            for (int t = 0; t < rule.Head.Terms.Length; t++)
            {
                string term = rule.Head.Terms[t];
                if (!IsAggregate(term)) continue;
                string operation = term.Substring(1, term.IndexOf(':') - 1);
                string variable = term.Substring(term.IndexOf(':') + 1);
                List<string> values = groups[text].Select(b => (string)b[variable]).ToList();
                List<double> numbers = new List<double>();
                foreach (string value in values)
                {
                    double number;
                    if (double.TryParse(value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out number)) numbers.Add(number);
                }
                double result = 0;
                switch (operation)
                {
                    case "count": result = values.Distinct(StringComparer.Ordinal).Count(); break;
                    case "sum": result = numbers.Sum(); break;
                    case "min": result = numbers.Count > 0 ? numbers.Min() : 0; break;
                    case "max": result = numbers.Count > 0 ? numbers.Max() : 0; break;
                    default: throw new InvalidOperationException("Unknown aggregate " + operation + ".");
                }
                terms[t] = result.ToString("R", System.Globalization.CultureInfo.InvariantCulture);
            }
            Add(rule.Head.Name, terms);
        }
    }

    // Why a fact holds: the rule that gave it, then its body, each fact explained the same way (a fact of the machine
    // or of the rules ends the chain). Lines indented by depth, so the proof reads from the conclusion down
    public List<string> Explain(string name, string[] terms, int depth)
    {
        List<string> lines = new List<string>();
        Explain(name, terms, depth, 0, lines, new HashSet<string>(StringComparer.Ordinal));
        return lines;
    }

    void Explain(string name, string[] terms, int depth, int level, List<string> lines, HashSet<string> seen)
    {
        string key = Key(name, terms);
        string text = name + "(" + string.Join(", ", terms.Select(t => "\"" + t + "\"")) + ")";
        KeyValuePair<LambekClause, List<KeyValuePair<string, string[]>>> proof;
        if (!Proofs.TryGetValue(key, out proof) || level >= depth || !seen.Add(key))
        {
            lines.Add(new string(' ', 2 * level) + text);
            return;
        }
        lines.Add(new string(' ', 2 * level) + text + " :-");
        foreach (KeyValuePair<string, string[]> item in proof.Value)
        {
            bool test = IsBuiltin(item.Key) || item.Key.StartsWith("not ", StringComparison.Ordinal);
            if (test) lines.Add(new string(' ', 2 * level + 2) + item.Key + "(" + string.Join(", ", item.Value.Select(t => "\"" + t + "\"")) + ")");
            else Explain(item.Key, item.Value, depth, level + 1, lines, seen);
        }
    }
}

// Pregroup chart: every choice of types at once, CKY over the words
public class LambekChart
{
    // Every form met: its text ("s|0 o|-1"), bases, orders and count, found again by its text
    public List<string> Keys = new List<string>();
    public List<string[]> Bases = new List<string[]>();
    public List<int[]> Orders = new List<int[]>();
    public List<long> Charges = new List<long>();
    public Dictionary<string, int> Ids = new Dictionary<string, int>(StringComparer.Ordinal);
    public Dictionary<long, int> Joined = new Dictionary<long, int>();
    public Dictionary<string, int> BaseIndex = new Dictionary<string, int>(StringComparer.Ordinal);

    // Each base is one digit of base 32, so the counts of two forms add up as plain numbers
    public long Unit(string basis)
    {
        int index;
        if (!BaseIndex.TryGetValue(basis, out index))
        {
            index = BaseIndex.Count;
            if (index >= 12) { throw new InvalidOperationException("Too many basic types to count."); }
            BaseIndex[basis] = index;
        }
        return (long)Math.Pow(32, index);
    }

    public int Id(string key)
    {
        int id;
        if (Ids.TryGetValue(key, out id)) { return id; }

        string[] items = key.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
        string[] baseList = new string[items.Length];
        int[] orderList = new int[items.Length];
        long charge = 0;
        for (int x = 0; x < items.Length; x++)
        {
            string[] pair = items[x].Split('|');
            baseList[x] = pair[0];
            orderList[x] = int.Parse(pair[1]);
            // Count: even orders minus odd orders, for each base
            int sign = Math.Abs(orderList[x]) % 2 == 1 ? -1 : 1;
            charge += sign * Unit(pair[0]);
        }

        id = Keys.Count;
        Keys.Add(key);
        Bases.Add(baseList);
        Orders.Add(orderList);
        Charges.Add(charge);
        Ids[key] = id;
        return id;
    }

    // Two irreducible halves only cancel where they meet: x^(n) x^(n+1) -> 1 at the junction, as long as it goes
    public int Join(int left, int right)
    {
        long pairKey = (long)left * 1000000 + right;
        int known;
        if (Joined.TryGetValue(pairKey, out known)) { return known; }

        string[] aBases = Bases[left];
        int[] aOrders = Orders[left];
        string[] bBases = Bases[right];
        int[] bOrders = Orders[right];
        int i = aBases.Length - 1;
        int j = 0;
        while (i >= 0 && j < bBases.Length && string.Equals(aBases[i], bBases[j], StringComparison.Ordinal) && bOrders[j] == aOrders[i] + 1)
        {
            i--;
            j++;
        }

        List<string> parts = new List<string>();
        for (int x = 0; x <= i; x++) { parts.Add(aBases[x] + "|" + aOrders[x]); }
        for (int x = j; x < bBases.Length; x++) { parts.Add(bBases[x] + "|" + bOrders[x]); }
        int id = Id(string.Join(" ", parts));
        Joined[pairKey] = id;
        return id;
    }

    // The whole chart over the forms of each word's candidates; the forms of the whole sentence by their text
    public Dictionary<string, object> Run(int[][] leaves, int keep, long fuel, bool sentenceOnly, int beam)
    {
        int n = leaves.Length;
        Dictionary<string, object> root = new Dictionary<string, object>(StringComparer.Ordinal);
        if (n == 0) { return root; }
        Dictionary<int, List<int[]>>[,] cells = new Dictionary<int, List<int[]>>[n, n];
        long spent = 0;

        // Counts the words before i and after j can reach (van Benthem: a sentence counts exactly s = 1, every other base 0)
        long target = Unit("s");
        HashSet<long>[] before = new HashSet<long>[n + 1];
        HashSet<long>[] after = new HashSet<long>[n + 1];
        before[0] = new HashSet<long> { 0 };
        for (int w = 0; w < n; w++)
        {
            before[w + 1] = new HashSet<long>();
            foreach (long sum in before[w]) { foreach (int id in leaves[w]) { before[w + 1].Add(sum + Charges[id]); } }
        }
        after[n] = new HashSet<long> { 0 };
        for (int w = n - 1; w >= 0; w--)
        {
            after[w] = new HashSet<long>();
            foreach (long sum in after[w + 1]) { foreach (int id in leaves[w]) { after[w].Add(sum + Charges[id]); } }
        }

        // Simple types the words before i and after j can offer: a form's leftovers must find a partner outside
        HashSet<string>[] leftTypes = new HashSet<string>[n + 1];
        HashSet<string>[] rightTypes = new HashSet<string>[n + 1];
        leftTypes[0] = new HashSet<string>(StringComparer.Ordinal);
        for (int w = 0; w < n; w++)
        {
            leftTypes[w + 1] = new HashSet<string>(leftTypes[w], StringComparer.Ordinal);
            foreach (int id in leaves[w]) { for (int x = 0; x < Bases[id].Length; x++) { leftTypes[w + 1].Add(Bases[id][x] + "|" + Orders[id][x]); } }
        }
        rightTypes[n] = new HashSet<string>(StringComparer.Ordinal);
        for (int w = n - 1; w >= 0; w--)
        {
            rightTypes[w] = new HashSet<string>(rightTypes[w + 1], StringComparer.Ordinal);
            foreach (int id in leaves[w]) { for (int x = 0; x < Bases[id].Length; x++) { rightTypes[w].Add(Bases[id][x] + "|" + Orders[id][x]); } }
        }

        for (int length = 1; length <= n; length++)
        {
            for (int i = 0; i <= n - length; i++)
            {
                int j = i + length - 1;
                Dictionary<int, List<int[]>> cell = new Dictionary<int, List<int[]>>();
                // A form F can end in a sentence only if some count p before and q after give p + F + q = s
                HashSet<long> prefix = before[i];
                HashSet<long> suffix = after[j + 1];

                // One word: its candidates
                if (length == 1)
                {
                    for (int c = 0; c < leaves[i].Length; c++)
                    {
                        int id = leaves[i][c];
                        if (sentenceOnly && !(Fits(prefix, suffix, target - Charges[id]) && Open(id, leftTypes[i], rightTypes[j + 1]))) { continue; }
                        Add(cell, id, new int[] { c }, keep);
                    }
                }

                // More words: every split into two halves
                for (int k = i; k < j; k++)
                {
                    Dictionary<int, List<int[]>> left = cells[i, k];
                    Dictionary<int, List<int[]>> right = cells[k + 1, j];
                    foreach (KeyValuePair<int, List<int[]>> leftForm in left)
                    {
                        foreach (KeyValuePair<int, List<int[]>> rightForm in right)
                        {
                            spent++;
                            if (spent > fuel) { throw new InvalidOperationException("The sentence has too many readings to check."); }

                            int id = Join(leftForm.Key, rightForm.Key);
                            if (sentenceOnly && !(Fits(prefix, suffix, target - Charges[id]) && Open(id, leftTypes[i], rightTypes[j + 1]))) { continue; }

                            // Joined choices come out smallest first: after keep of them, none can enter the cell any more
                            int made = 0;
                            foreach (int[] first in leftForm.Value)
                            {
                                foreach (int[] second in rightForm.Value)
                                {
                                    int[] both = new int[first.Length + second.Length];
                                    first.CopyTo(both, 0);
                                    second.CopyTo(both, first.Length);
                                    Add(cell, id, both, keep);
                                    made++;
                                    if (made >= keep) { break; }
                                }
                                if (made >= keep) { break; }
                            }
                        }
                    }
                }

                // Beam: the shortest forms only, the first made first among equals
                if (beam > 0 && cell.Count > beam)
                {
                    List<long> sizes = new List<long>();
                    foreach (int id in cell.Keys) { sizes.Add((long)Bases[id].Length * 10000000 + id); }
                    long[] sorted = sizes.ToArray();
                    Array.Sort(sorted);
                    Dictionary<int, List<int[]>> smaller = new Dictionary<int, List<int[]>>();
                    for (int x = 0; x < beam; x++)
                    {
                        int id = (int)(sorted[x] % 10000000);
                        smaller[id] = cell[id];
                    }
                    cell = smaller;
                }
                cells[i, j] = cell;
            }
        }

        foreach (KeyValuePair<int, List<int[]>> form in cells[0, n - 1]) { root[Keys[form.Key]] = form.Value; }
        return root;
    }

    // Fewest simple types left in each span i..j: i stays, or cancels with some m once everything between cancels.
    // Returns, for each span, -1 when i stays or the position i cancels with.
    public static int[,] Reduce(string[] bases, int[] orders)
    {
        int n = bases.Length;
        int[,] cost = new int[n + 1, n + 1];
        int[,] choice = new int[n + 1, n + 1];
        for (int length = 1; length <= n; length++)
        {
            for (int i = 0; i <= n - length; i++)
            {
                int j = i + length - 1;
                int best = 1;
                if (i + 1 <= j) { best = 1 + cost[i + 1, j]; }
                int bestChoice = -1;
                for (int m = i + 1; m <= j; m++)
                {
                    if (!string.Equals(bases[i], bases[m], StringComparison.Ordinal) || orders[m] != orders[i] + 1) { continue; }
                    int inside = 0;
                    if (i + 1 <= m - 1) { inside = cost[i + 1, m - 1]; }
                    if (inside != 0) { continue; }
                    int rest = 0;
                    if (m + 1 <= j) { rest = cost[m + 1, j]; }
                    if (rest < best)
                    {
                        best = rest;
                        bestChoice = m;
                    }
                }
                cost[i, j] = best;
                choice[i, j] = bestChoice;
            }
        }
        return choice;
    }

    public static bool Fits(HashSet<long> prefix, HashSet<long> suffix, long need)
    {
        foreach (long p in prefix) { if (suffix.Contains(need - p)) { return true; } }
        return false;
    }

    // Planarity: in a sentence, the types a span leaves are those that cancel to the left, then at most the s itself,
    // then those that cancel to the right; each needs its partner x^(k-1) before the span or x^(k+1) after it
    public bool Open(int id, HashSet<string> before, HashSet<string> after)
    {
        string[] kinds = Bases[id];
        int[] levels = Orders[id];
        int count = kinds.Length;
        int a = 0;
        while (a < count && before.Contains(kinds[a] + "|" + (levels[a] - 1))) { a++; }
        int b = count;
        while (b > 0 && after.Contains(kinds[b - 1] + "|" + (levels[b - 1] + 1))) { b--; }
        if (b <= a) { return true; }
        return b == a + 1 && string.Equals(kinds[a], "s", StringComparison.Ordinal) && levels[a] == 0;
    }

    // The choices of a form stay sorted (word by word, the first word first), without repeats, at most keep
    public static void Add(Dictionary<int, List<int[]>> cell, int form, int[] choice, int keep)
    {
        List<int[]> list;
        if (!cell.TryGetValue(form, out list))
        {
            list = new List<int[]>();
            cell[form] = list;
        }
        int at = list.Count;
        for (int x = 0; x < list.Count; x++)
        {
            int[] other = list[x];
            int order = 0;
            for (int y = 0; y < choice.Length; y++)
            {
                if (choice[y] != other[y])
                {
                    order = choice[y] < other[y] ? -1 : 1;
                    break;
                }
            }
            if (order == 0) { return; }
            if (order < 0) { at = x; break; }
        }
        if (at >= keep) { return; }
        list.Insert(at, choice);
        if (list.Count > keep) { list.RemoveAt(list.Count - 1); }
    }
}

// Distances and similarities between words and requests
public static class LambekMeasure
{
    // Damerau-Levenshtein (optimal string alignment)
    public static int EditDistance(string source, string target)
    {
        int n = source.Length;
        int m = target.Length;
        int[,] d = new int[n + 1, m + 1];
        for (int i = 0; i <= n; i++) { d[i, 0] = i; }
        for (int j = 0; j <= m; j++) { d[0, j] = j; }

        for (int i = 1; i <= n; i++)
        {
            for (int j = 1; j <= m; j++)
            {
                int cost = source[i - 1] == target[j - 1] ? 0 : 1;
                int best = Math.Min(Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1), d[i - 1, j - 1] + cost);
                if (i > 1 && j > 1 && source[i - 1] == target[j - 2] && source[i - 2] == target[j - 1])
                {
                    best = Math.Min(best, d[i - 2, j - 2] + 1);
                }
                d[i, j] = best;
            }
        }
        return d[n, m];
    }

    public static double EditSimilarity(string source, string target)
    {
        int longest = Math.Max(source.Length, target.Length);
        if (longest == 0) { return 1.0; }
        return 1.0 - ((double)EditDistance(source, target) / longest);
    }

    // Typing cost: a slip to a key next door, two letters swapped, or a doubled letter costs half an edit
    public static double KeyDistance(string source, string target, HashSet<string> neighbors)
    {
        int n = source.Length;
        int m = target.Length;

        // A letter typed twice ("verrs") is a small slip to add or remove, any other letter a full edit
        double[] extraSource = new double[n];
        for (int i = 0; i < n; i++) { extraSource[i] = (i > 0 && source[i] == source[i - 1]) ? 0.5 : 1.0; }
        double[] extraTarget = new double[m];
        for (int j = 0; j < m; j++) { extraTarget[j] = (j > 0 && target[j] == target[j - 1]) ? 0.5 : 1.0; }

        double[,] d = new double[n + 1, m + 1];
        for (int i = 1; i <= n; i++) { d[i, 0] = d[i - 1, 0] + extraSource[i - 1]; }
        for (int j = 1; j <= m; j++) { d[0, j] = d[0, j - 1] + extraTarget[j - 1]; }

        for (int i = 1; i <= n; i++)
        {
            char a = source[i - 1];
            for (int j = 1; j <= m; j++)
            {
                char b = target[j - 1];
                double swap = 1.0;
                if (a == b) { swap = 0.0; }
                else if (neighbors.Contains(a.ToString() + b)) { swap = 0.5; }

                double best = d[i - 1, j - 1] + swap;
                double remove = d[i - 1, j] + extraSource[i - 1];
                if (remove < best) { best = remove; }
                double add = d[i, j - 1] + extraTarget[j - 1];
                if (add < best) { best = add; }

                // Two letters typed in the wrong order
                if (i > 1 && j > 1 && a == target[j - 2] && source[i - 2] == b)
                {
                    double turn = d[i - 2, j - 2] + 0.5;
                    if (turn < best) { best = turn; }
                }
                d[i, j] = best;
            }
        }
        return d[n, m];
    }

    // |A n B| / |A u B|, 1 for two empty sets
    public static double Jaccard(string[] setA, string[] setB)
    {
        HashSet<string> a = new HashSet<string>(setA);
        HashSet<string> b = new HashSet<string>(setB);
        if (a.Count == 0 && b.Count == 0) { return 1.0; }
        int common = 0;
        foreach (string item in a) { if (b.Contains(item)) { common++; } }
        return (double)common / (a.Count + b.Count - common);
    }

    // Weight = tf * idf, terms compared without regard to case like the tables of PowerShell
    public static Dictionary<string, double> TfIdf(string[] terms, IDictionary idf, double unknownIdf)
    {
        Dictionary<string, double> vector = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
        if (terms.Length == 0) { return vector; }
        Dictionary<string, int> counts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        List<string> order = new List<string>();
        foreach (string term in terms)
        {
            int count;
            if (counts.TryGetValue(term, out count)) { counts[term] = count + 1; }
            else { counts[term] = 1; order.Add(term); }
        }
        foreach (string term in order)
        {
            double weight = unknownIdf;
            if (idf.Contains(term)) { weight = Convert.ToDouble(idf[term]); }
            vector[term] = ((double)counts[term] / terms.Length) * weight;
        }
        return vector;
    }

    public static double Cosine(Dictionary<string, double> a, Dictionary<string, double> b)
    {
        double dot = 0.0;
        foreach (KeyValuePair<string, double> item in a)
        {
            double other;
            if (b.TryGetValue(item.Key, out other)) { dot += item.Value * other; }
        }
        double sumA = 0.0;
        foreach (double weight in a.Values) { sumA += weight * weight; }
        double sumB = 0.0;
        foreach (double weight in b.Values) { sumB += weight * weight; }
        double normA = Math.Sqrt(sumA);
        double normB = Math.Sqrt(sumB);
        if (normA == 0 || normB == 0) { return 0.0; }
        return dot / (normA * normB);
    }

    // The four text scores of a request against one example: edit, word Jaccard, n-gram Jaccard, TF-IDF cosine
    public static double[] Similarity(string[] terms, string[] nGrams, string[] referenceTerms, string[] referenceNGrams, IDictionary idf, double unknownIdf)
    {
        // Edit similarity: the best match of each term, then the average
        double editTotal = 0.0;
        foreach (string term in terms)
        {
            double best = 0.0;
            foreach (string candidate in referenceTerms)
            {
                double score = EditSimilarity(term, candidate);
                if (score > best) { best = score; }
            }
            editTotal += best;
        }
        double edit = terms.Length > 0 ? editTotal / terms.Length : 0.0;

        double cosine = Cosine(TfIdf(terms, idf, unknownIdf), TfIdf(referenceTerms, idf, unknownIdf));
        return new double[] { edit, Jaccard(terms, referenceTerms), Jaccard(nGrams, referenceNGrams), cosine };
    }
}
