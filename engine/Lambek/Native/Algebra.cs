// Symbolic algebra on exact rationals: expressions, a rewriting simplifier that always ends (it only folds constants
// and collects like terms), derivatives by the chain rule, primitives from a small table with linearity, rational
// functions reduced by the polynomial GCD, and the real roots of any polynomial certified by Sturm's theorem.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Numerics;
using System.Text;
using System.Text.RegularExpressions;

// An expression: a number, a letter or a constant, a sum, a product, a power, or a function of one argument
public abstract class LambekExpr
{
    public abstract string Key();
    public override string ToString() { return LambekAlgebra.Show(this); }
}

public class LambekNum : LambekExpr
{
    public LambekRational Value;
    public LambekNum(LambekRational value) { Value = value; }
    public LambekNum(long value) { Value = new LambekRational(value, 1); }
    public override string Key() { return "#" + Value.Exact(); }
}

public class LambekSym : LambekExpr
{
    public string Name;
    public LambekSym(string name) { Name = name; }
    public override string Key() { return "$" + Name; }
}

public class LambekSum : LambekExpr
{
    public List<LambekExpr> Terms;
    public LambekSum(IEnumerable<LambekExpr> terms) { Terms = terms.ToList(); }
    public override string Key() { return "+(" + string.Join(",", Terms.Select(t => t.Key())) + ")"; }
}

public class LambekProd : LambekExpr
{
    public List<LambekExpr> Factors;
    public LambekProd(IEnumerable<LambekExpr> factors) { Factors = factors.ToList(); }
    public override string Key() { return "*(" + string.Join(",", Factors.Select(t => t.Key())) + ")"; }
}

public class LambekPow : LambekExpr
{
    public LambekExpr Base;
    public LambekExpr Exponent;
    public LambekPow(LambekExpr b, LambekExpr e) { Base = b; Exponent = e; }
    public override string Key() { return "^(" + Base.Key() + "," + Exponent.Key() + ")"; }
}

public class LambekFunc : LambekExpr
{
    public string Name;
    public LambekExpr Argument;
    public LambekFunc(string name, LambekExpr argument) { Name = name; Argument = argument; }
    public override string Key() { return Name + "(" + Argument.Key() + ")"; }
}

public static class LambekAlgebra
{
    public static readonly string[] Functions = new[] { "sin", "cos", "tan", "exp", "ln", "log", "sqrt", "abs", "arctan", "arcsin", "arccos" };
    static LambekRational Q(long n) { return new LambekRational(n, 1); }
    static LambekExpr N(long n) { return new LambekNum(n); }
    static LambekExpr N(LambekRational r) { return new LambekNum(r); }
    public static bool IsNum(LambekExpr e, out LambekRational value)
    {
        LambekNum n = e as LambekNum;
        value = n != null ? n.Value : LambekRational.Zero;
        return n != null;
    }
    static bool IsNum(LambekExpr e, long value) { LambekRational r; return IsNum(e, out r) && r.Equals(Q(value)); }

    // Parse
    public static LambekExpr Parse(string text)
    {
        List<string> tokens = Tokenize(text);
        int at = 0;
        LambekExpr e = ParseSum(tokens, ref at);
        if (at != tokens.Count) throw new FormatException("Unexpected '" + tokens[at] + "'.");
        return e;
    }

    public static List<string> Tokenize(string text)
    {
        // Numbers, function names, constants (pi, e), single letters, operators; a product may lose its sign ("2x", "x(x+1)")
        string clean = text.Replace("×", "*").Replace("·", "*").Replace("÷", "/").Replace("−", "-").Replace("²", "^2").Replace("³", "^3")
            .Replace("√", "sqrt").Replace("π", "pi").Replace("**", "^").Replace("racine", "sqrt").Replace("raiz", "sqrt").Replace("wurzel", "sqrt");
        List<string> tokens = new List<string>();
        string names = string.Join("|", Functions.OrderByDescending(f => f.Length));
        Regex pattern = new Regex(@"\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|(?:" + names + @"|pi)(?![a-z])|[A-Za-z]|[-+*/^()=!,]", RegexOptions.IgnoreCase);
        int last = 0;
        foreach (Match m in pattern.Matches(clean))
        {
            string between = clean.Substring(last, m.Index - last);
            if (between.Trim().Length > 0) throw new FormatException("Cannot read '" + between.Trim() + "'.");
            last = m.Index + m.Length;
            string token = m.Value.Length > 1 && char.IsLetter(m.Value[0]) ? m.Value.ToLowerInvariant() : m.Value;
            if (tokens.Count > 0)
            {
                string before = tokens[tokens.Count - 1];
                bool closes = char.IsDigit(before[0]) || before == ")" || before == "!" || (char.IsLetter(before[0]) && !Functions.Contains(before));
                bool opens = token == "(" || char.IsLetter(token[0]);
                if (closes && opens) tokens.Add("*");
            }
            tokens.Add(token);
        }
        if (clean.Substring(last).Trim().Length > 0) throw new FormatException("Cannot read '" + clean.Substring(last).Trim() + "'.");
        return tokens;
    }

    static LambekExpr ParseSum(List<string> t, ref int at)
    {
        LambekExpr value = ParseProduct(t, ref at);
        while (at < t.Count && (t[at] == "+" || t[at] == "-"))
        {
            string sign = t[at++];
            LambekExpr next = ParseProduct(t, ref at);
            value = sign == "+" ? Add(value, next) : Add(value, Neg(next));
        }
        return value;
    }

    static LambekExpr ParseProduct(List<string> t, ref int at)
    {
        LambekExpr value = ParseUnary(t, ref at);
        while (at < t.Count && (t[at] == "*" || t[at] == "/"))
        {
            string sign = t[at++];
            LambekExpr next = ParseUnary(t, ref at);
            value = sign == "*" ? Mul(value, next) : Div(value, next);
        }
        return value;
    }

    static LambekExpr ParseUnary(List<string> t, ref int at)
    {
        if (at < t.Count && t[at] == "-") { at++; return Neg(ParseUnary(t, ref at)); }
        if (at < t.Count && t[at] == "+") { at++; return ParseUnary(t, ref at); }
        return ParsePower(t, ref at);
    }

    static LambekExpr ParsePower(List<string> t, ref int at)
    {
        LambekExpr value = ParsePostfix(t, ref at);
        if (at < t.Count && t[at] == "^")
        {
            at++;
            // Right associative: 2^3^2 = 2^9
            LambekExpr exponent = ParseUnary(t, ref at);
            return new LambekPow(value, exponent);
        }
        return value;
    }

    static LambekExpr ParsePostfix(List<string> t, ref int at)
    {
        LambekExpr value = ParseAtom(t, ref at);
        while (at < t.Count && t[at] == "!")
        {
            LambekRational n;
            if (!IsNum(Simplify(value), out n) || !n.IsInteger || n.Sign < 0 || n.Numerator > 1000) throw new FormatException("A factorial needs a whole number from 0 to 1000.");
            value = N(new LambekRational(LambekNumbers.Factorial((int)n.Numerator), 1));
            at++;
        }
        return value;
    }

    static LambekExpr ParseAtom(List<string> t, ref int at)
    {
        if (at >= t.Count) throw new FormatException("The expression ends too early.");
        string token = t[at++];
        if (token == "(")
        {
            LambekExpr inside = ParseSum(t, ref at);
            if (at >= t.Count || t[at] != ")") throw new FormatException("A parenthesis is not closed.");
            at++;
            return inside;
        }
        if (char.IsDigit(token[0])) return N(LambekRational.Parse(token));
        if (token == "pi") return new LambekSym("pi");
        if (Functions.Contains(token))
        {
            LambekExpr argument = ParsePostfix(t, ref at);
            string name = token == "log" ? "ln" : token;
            if (name == "sqrt") return new LambekPow(argument, N(new LambekRational(1, 2)));
            return new LambekFunc(name, argument);
        }
        if (token.Length == 1 && char.IsLetter(token[0])) return new LambekSym(token == "E" ? "e" : token);
        throw new FormatException("Unexpected '" + token + "'.");
    }

    // Builders
    public static LambekExpr Add(params LambekExpr[] terms) { return new LambekSum(terms); }
    public static LambekExpr Mul(params LambekExpr[] factors) { return new LambekProd(factors); }
    public static LambekExpr Neg(LambekExpr e) { return new LambekProd(new[] { N(-1), e }); }
    public static LambekExpr Div(LambekExpr a, LambekExpr b) { return new LambekProd(new[] { a, new LambekPow(b, N(-1)) }); }
    public static LambekExpr Pow(LambekExpr a, LambekExpr b) { return new LambekPow(a, b); }

    // The letters of an expression (pi and e are constants)
    public static SortedSet<string> Letters(LambekExpr e)
    {
        SortedSet<string> found = new SortedSet<string>(StringComparer.Ordinal);
        Walk(e, x => { LambekSym s = x as LambekSym; if (s != null && s.Name != "pi" && s.Name != "e") found.Add(s.Name); });
        return found;
    }

    static void Walk(LambekExpr e, Action<LambekExpr> visit)
    {
        visit(e);
        if (e is LambekSum) foreach (LambekExpr t in ((LambekSum)e).Terms) Walk(t, visit);
        else if (e is LambekProd) foreach (LambekExpr f in ((LambekProd)e).Factors) Walk(f, visit);
        else if (e is LambekPow) { Walk(((LambekPow)e).Base, visit); Walk(((LambekPow)e).Exponent, visit); }
        else if (e is LambekFunc) Walk(((LambekFunc)e).Argument, visit);
    }

    public static bool Contains(LambekExpr e, string letter)
    {
        bool found = false;
        Walk(e, x => { LambekSym s = x as LambekSym; if (s != null && s.Name == letter) found = true; });
        return found;
    }

    // Simplify: bottom up, each rule makes the expression smaller or folds numbers, so it always ends
    public static LambekExpr Simplify(LambekExpr e)
    {
        if (e is LambekNum || e is LambekSym) return e;
        if (e is LambekSum) return SimplifySum(((LambekSum)e).Terms.Select(Simplify));
        if (e is LambekProd) return SimplifyProduct(((LambekProd)e).Factors.Select(Simplify));
        if (e is LambekPow) return SimplifyPower(Simplify(((LambekPow)e).Base), Simplify(((LambekPow)e).Exponent));
        LambekFunc f = (LambekFunc)e;
        return SimplifyFunction(f.Name, Simplify(f.Argument));
    }

    // A term as coefficient times the rest: 3x^2 is (3, x^2)
    static void Split(LambekExpr term, out LambekRational coefficient, out LambekExpr rest)
    {
        coefficient = LambekRational.One;
        rest = term;
        LambekRational value;
        if (IsNum(term, out value)) { coefficient = value; rest = null; return; }
        LambekProd p = term as LambekProd;
        if (p == null) return;
        List<LambekExpr> others = new List<LambekExpr>();
        foreach (LambekExpr f in p.Factors)
        {
            if (IsNum(f, out value)) coefficient = coefficient * value;
            else others.Add(f);
        }
        rest = others.Count == 0 ? null : (others.Count == 1 ? others[0] : new LambekProd(others));
    }

    static LambekExpr SimplifySum(IEnumerable<LambekExpr> terms)
    {
        // Flatten, then collect like terms by the key of their non-numeric part
        List<LambekExpr> flat = new List<LambekExpr>();
        foreach (LambekExpr t in terms) { if (t is LambekSum) flat.AddRange(((LambekSum)t).Terms); else flat.Add(t); }
        LambekRational constant = LambekRational.Zero;
        Dictionary<string, LambekRational> coefficients = new Dictionary<string, LambekRational>(StringComparer.Ordinal);
        Dictionary<string, LambekExpr> rests = new Dictionary<string, LambekExpr>(StringComparer.Ordinal);
        List<string> order = new List<string>();
        foreach (LambekExpr t in flat)
        {
            LambekRational c; LambekExpr rest;
            Split(t, out c, out rest);
            if (rest == null) { constant = constant + c; continue; }
            string key = rest.Key();
            if (!coefficients.ContainsKey(key)) { coefficients[key] = LambekRational.Zero; rests[key] = rest; order.Add(key); }
            coefficients[key] = coefficients[key] + c;
        }
        List<LambekExpr> result = new List<LambekExpr>();
        foreach (string key in order)
        {
            if (coefficients[key].IsZero) continue;
            result.Add(coefficients[key].Equals(LambekRational.One) ? rests[key] : SimplifyProduct(new[] { N(coefficients[key]), rests[key] }));
        }
        // Highest degree first, then by name: the usual way to write a polynomial
        result = result.OrderByDescending(Degree).ThenBy(x => x.Key(), StringComparer.Ordinal).ToList();
        if (!constant.IsZero) result.Add(N(constant));
        if (result.Count == 0) return N(0);
        if (result.Count == 1) return result[0];
        return new LambekSum(result);
    }

    static double Degree(LambekExpr e)
    {
        // Total degree in the letters, to order the terms
        if (e is LambekSym) return ((LambekSym)e).Name == "pi" || ((LambekSym)e).Name == "e" ? 0 : 1;
        if (e is LambekProd) return ((LambekProd)e).Factors.Sum(f => Degree(f));
        LambekPow p = e as LambekPow;
        LambekRational n;
        if (p != null && IsNum(p.Exponent, out n)) return Degree(p.Base) * n.ToDouble();
        if (e is LambekFunc) return 0.5;
        return 0;
    }

    static LambekExpr SimplifyProduct(IEnumerable<LambekExpr> factors)
    {
        List<LambekExpr> flat = new List<LambekExpr>();
        foreach (LambekExpr f in factors) { if (f is LambekProd) flat.AddRange(((LambekProd)f).Factors); else flat.Add(f); }
        LambekRational coefficient = LambekRational.One;
        Dictionary<string, LambekExpr> bases = new Dictionary<string, LambekExpr>(StringComparer.Ordinal);
        Dictionary<string, List<LambekExpr>> exponents = new Dictionary<string, List<LambekExpr>>(StringComparer.Ordinal);
        List<string> order = new List<string>();
        foreach (LambekExpr f in flat)
        {
            LambekRational value;
            if (IsNum(f, out value)) { coefficient = coefficient * value; continue; }
            LambekExpr b = f, e = N(1);
            LambekPow p = f as LambekPow;
            if (p != null) { b = p.Base; e = p.Exponent; }
            string key = b.Key();
            if (!bases.ContainsKey(key)) { bases[key] = b; exponents[key] = new List<LambekExpr>(); order.Add(key); }
            exponents[key].Add(e);
        }
        if (coefficient.IsZero) return N(0);
        List<LambekExpr> result = new List<LambekExpr>();
        foreach (string key in order)
        {
            LambekExpr power = SimplifyPower(bases[key], SimplifySum(exponents[key]));
            LambekRational value;
            if (IsNum(power, out value)) { coefficient = coefficient * value; continue; }
            if (power is LambekProd)
            {
                foreach (LambekExpr f in ((LambekProd)power).Factors)
                {
                    if (IsNum(f, out value)) coefficient = coefficient * value; else result.Add(f);
                }
                continue;
            }
            result.Add(power);
        }
        if (coefficient.IsZero) return N(0);
        result = result.OrderBy(x => x is LambekFunc ? 1 : 0).ThenBy(x => x.Key(), StringComparer.Ordinal).ToList();
        if (!coefficient.Equals(LambekRational.One) || result.Count == 0) result.Insert(0, N(coefficient));
        if (result.Count == 1) return result[0];
        // A number times a sum is distributed, so like terms can meet: 2(x+1) - 2x = 2
        LambekRational c;
        if (result.Count == 2 && IsNum(result[0], out c) && result[1] is LambekSum)
            return SimplifySum(((LambekSum)result[1]).Terms.Select(t => SimplifyProduct(new[] { result[0], t })));
        return new LambekProd(result);
    }

    static LambekExpr SimplifyPower(LambekExpr b, LambekExpr e)
    {
        LambekRational n, x;
        if (IsNum(e, out n))
        {
            if (n.IsZero) return N(1);
            if (n.Equals(LambekRational.One)) return b;
            if (IsNum(b, out x))
            {
                if (n.IsInteger && BigInteger.Abs(n.Numerator) <= 4096)
                {
                    if (x.IsZero && n.Sign < 0) throw new DivideByZeroException("Division by zero.");
                    return N(x.Power((int)n.Numerator));
                }
                // A rational power of a rational: exact when the root is ("8^(1/3)" is 2)
                if (BigInteger.Abs(n.Denominator) <= 12 && BigInteger.Abs(n.Numerator) <= 4096 && x.Sign > 0)
                {
                    LambekRational root;
                    if (LambekNumbers.ExactNthRoot(x, (int)n.Denominator, out root)) return N(root.Power((int)n.Numerator));
                }
                if (x.IsZero) return N(0);
                if (x.Equals(LambekRational.One)) return N(1);
                // A square root: the square factors come out, sqrt(8) = 2 sqrt(2); x^(3/2) = x sqrt(x)
                if (n.Denominator == 2 && x.Sign > 0 && x.IsInteger && x.Numerator < BigInteger.Pow(10, 12))
                {
                    BigInteger inside = x.Numerator, outside = BigInteger.One;
                    for (BigInteger f = 2; f * f <= inside; f += 1) while (inside % (f * f) == 0) { inside /= f * f; outside *= f; }
                    LambekRational whole = new LambekRational(x.Numerator, 1).Power((int)((n.Numerator - 1) / 2));
                    if (n.Numerator < 0) whole = new LambekRational(x.Numerator, 1).Power((int)((n.Numerator - 1) / 2));
                    if (!outside.IsOne || !whole.Equals(LambekRational.One))
                    {
                        LambekRational factor = n.Sign > 0 ? whole * new LambekRational(outside, 1) : whole * new LambekRational(outside, 1);
                        return new LambekProd(new LambekExpr[] { N(factor), new LambekPow(N(new LambekRational(inside, 1)), N(new LambekRational(1, 2))) });
                    }
                }
            }
            // (a^b)^n = a^(bn) for a whole n; (ab)^n = a^n b^n
            LambekPow inner = b as LambekPow;
            if (inner != null && n.IsInteger) return SimplifyPower(inner.Base, SimplifyProduct(new[] { inner.Exponent, e }));
            LambekProd product = b as LambekProd;
            if (product != null && n.IsInteger) return SimplifyProduct(product.Factors.Select(f => SimplifyPower(f, e)));
        }
        if (IsNum(b, 1)) return N(1);
        // e^(ln u) = u
        LambekSym symbol = b as LambekSym;
        LambekFunc log = e as LambekFunc;
        if (symbol != null && symbol.Name == "e" && log != null && log.Name == "ln") return log.Argument;
        return new LambekPow(b, e);
    }

    static LambekExpr SimplifyFunction(string name, LambekExpr a)
    {
        LambekRational v;
        bool number = IsNum(a, out v);
        LambekSym s = a as LambekSym;
        switch (name)
        {
            case "sin": if (number && v.IsZero) return N(0); if (s != null && s.Name == "pi") return N(0); break;
            case "cos": if (number && v.IsZero) return N(1); if (s != null && s.Name == "pi") return N(-1); break;
            case "tan": if (number && v.IsZero) return N(0); break;
            case "exp": if (number && v.IsZero) return N(1); if (a is LambekFunc && ((LambekFunc)a).Name == "ln") return ((LambekFunc)a).Argument; return new LambekPow(new LambekSym("e"), a);
            case "ln":
                if (number && v.Equals(LambekRational.One)) return N(0);
                if (s != null && s.Name == "e") return N(1);
                LambekPow p = a as LambekPow;
                if (p != null && p.Base is LambekSym && ((LambekSym)p.Base).Name == "e") return p.Exponent;
                if (number && v.Sign <= 0) throw new FormatException("The logarithm needs a positive number.");
                break;
            case "abs": if (number) return N(v.Sign < 0 ? -v : v); break;
            case "arctan": if (number && v.IsZero) return N(0); break;
            case "arcsin": if (number && v.IsZero) return N(0); break;
        }
        return new LambekFunc(name, a);
    }

    // Expand products of sums and whole powers of sums (bounded, so it ends): the terms are multiplied as lists,
    // never rebuilt into a product the simplifier would fold back into a power
    public static LambekExpr Expand(LambekExpr e)
    {
        return Simplify(new LambekSum(ExpandTerms(Simplify(e))));
    }

    static List<LambekExpr> ExpandTerms(LambekExpr e)
    {
        if (e is LambekSum) return ((LambekSum)e).Terms.SelectMany(ExpandTerms).ToList();
        if (e is LambekProd)
        {
            List<LambekExpr> terms = new List<LambekExpr> { N(1) };
            foreach (LambekExpr f in ((LambekProd)e).Factors) terms = Cross(terms, ExpandTerms(f));
            return terms;
        }
        LambekPow p = e as LambekPow;
        LambekRational n;
        if (p != null && p.Base is LambekSum && IsNum(p.Exponent, out n) && n.IsInteger && n.Sign > 0 && n.Numerator <= 64)
        {
            List<LambekExpr> parts = ExpandTerms(p.Base);
            List<LambekExpr> terms = new List<LambekExpr> { N(1) };
            for (int k = 0; k < (int)n.Numerator; k++) terms = Cross(terms, parts);
            return terms;
        }
        return new List<LambekExpr> { e };
    }

    static List<LambekExpr> Cross(List<LambekExpr> a, List<LambekExpr> b)
    {
        List<LambekExpr> result = new List<LambekExpr>();
        foreach (LambekExpr t in a) foreach (LambekExpr u in b) result.Add(SimplifyProduct(new[] { t, u }));
        if (result.Count > 20000) throw new FormatException("The expansion is too large.");
        // Like terms met at once keep the lists small
        LambekExpr sum = SimplifySum(result);
        return sum is LambekSum ? ((LambekSum)sum).Terms : new List<LambekExpr> { sum };
    }

    // Derivative by the rules of sums, products, powers and the chain rule
    public static LambekExpr Derive(LambekExpr e, string x)
    {
        return Simplify(D(Simplify(e), x));
    }

    static LambekExpr D(LambekExpr e, string x)
    {
        if (!Contains(e, x)) return N(0);
        if (e is LambekSym) return N(1);
        if (e is LambekSum) return new LambekSum(((LambekSum)e).Terms.Select(t => D(t, x)));
        if (e is LambekProd)
        {
            List<LambekExpr> f = ((LambekProd)e).Factors;
            List<LambekExpr> terms = new List<LambekExpr>();
            for (int i = 0; i < f.Count; i++)
            {
                List<LambekExpr> product = new List<LambekExpr>();
                for (int j = 0; j < f.Count; j++) product.Add(i == j ? D(f[j], x) : f[j]);
                terms.Add(new LambekProd(product));
            }
            return new LambekSum(terms);
        }
        if (e is LambekPow)
        {
            LambekPow p = (LambekPow)e;
            if (!Contains(p.Exponent, x))
                return Mul(p.Exponent, Pow(p.Base, Add(p.Exponent, N(-1))), D(p.Base, x));
            // a^u = e^(u ln a): d = a^u (u' ln a + u a'/a)
            return Mul(e, Add(Mul(D(p.Exponent, x), new LambekFunc("ln", p.Base)), Mul(p.Exponent, D(p.Base, x), Pow(p.Base, N(-1)))));
        }
        LambekFunc fn = (LambekFunc)e;
        LambekExpr u = fn.Argument, du = D(u, x);
        switch (fn.Name)
        {
            case "sin": return Mul(new LambekFunc("cos", u), du);
            case "cos": return Mul(N(-1), new LambekFunc("sin", u), du);
            case "tan": return Mul(Add(N(1), Pow(new LambekFunc("tan", u), N(2))), du);
            case "ln": return Mul(du, Pow(u, N(-1)));
            case "abs": return Mul(u, Pow(new LambekFunc("abs", u), N(-1)), du);
            case "arctan": return Mul(du, Pow(Add(N(1), Pow(u, N(2))), N(-1)));
            case "arcsin": return Mul(du, Pow(Add(N(1), Neg(Pow(u, N(2)))), new LambekNum(new LambekRational(-1, 2))));
            case "arccos": return Mul(N(-1), du, Pow(Add(N(1), Neg(Pow(u, N(2)))), new LambekNum(new LambekRational(-1, 2))));
        }
        throw new FormatException("No rule to derive " + fn.Name + ".");
    }

    // A primitive: linearity, then a table for u = a x + b (powers, 1/u, e^u, sin, cos); null when none is found
    public static LambekExpr Integrate(LambekExpr e, string x)
    {
        e = Simplify(e);
        LambekExpr found = I(e, x);
        if (found == null)
        {
            // A product of sums may become a polynomial
            LambekExpr expanded = Expand(e);
            if (expanded.Key() != e.Key()) found = I(expanded, x);
        }
        return found == null ? null : Simplify(found);
    }

    static bool Linear(LambekExpr u, string x, out LambekRational a)
    {
        // u = a x + b with a a nonzero number
        a = LambekRational.Zero;
        LambekExpr derivative = Derive(u, x);
        return IsNum(derivative, out a) && !a.IsZero;
    }

    static LambekExpr I(LambekExpr e, string x)
    {
        if (!Contains(e, x)) return Mul(e, new LambekSym(x));
        if (e is LambekSum)
        {
            List<LambekExpr> parts = new List<LambekExpr>();
            foreach (LambekExpr t in ((LambekSum)e).Terms)
            {
                LambekExpr p = I(t, x);
                if (p == null) return null;
                parts.Add(p);
            }
            return new LambekSum(parts);
        }
        if (e is LambekProd)
        {
            // Constant factors out
            List<LambekExpr> constant = new List<LambekExpr>(), variable = new List<LambekExpr>();
            foreach (LambekExpr f in ((LambekProd)e).Factors) (Contains(f, x) ? variable : constant).Add(f);
            if (constant.Count > 0)
            {
                LambekExpr inner = I(variable.Count == 1 ? variable[0] : new LambekProd(variable), x);
                return inner == null ? null : Mul(new LambekProd(constant), inner);
            }
            return null;
        }
        LambekRational a;
        if (e is LambekSym) return Mul(new LambekNum(new LambekRational(1, 2)), Pow(e, N(2)));
        if (e is LambekPow)
        {
            LambekPow p = (LambekPow)e;
            LambekRational n;
            if (IsNum(p.Exponent, out n) && Linear(p.Base, x, out a))
            {
                if (n.Equals(Q(-1))) return Mul(N(LambekRational.One / a), new LambekFunc("ln", new LambekFunc("abs", p.Base)));
                LambekRational up = n + LambekRational.One;
                return Mul(N(LambekRational.One / (a * up)), Pow(p.Base, N(up)));
            }
            // e^(a x + b)
            LambekSym b = p.Base as LambekSym;
            if (b != null && b.Name == "e" && Linear(p.Exponent, x, out a)) return Mul(N(LambekRational.One / a), e);
            // c^(a x + b) = c^u / (a ln c)
            LambekRational c;
            if (IsNum(p.Base, out c) && c.Sign > 0 && Linear(p.Exponent, x, out a)) return Mul(e, Pow(Mul(N(a), new LambekFunc("ln", p.Base)), N(-1)));
            return null;
        }
        LambekFunc fn = (LambekFunc)e;
        if (!Linear(fn.Argument, x, out a)) return null;
        LambekExpr k = N(LambekRational.One / a);
        switch (fn.Name)
        {
            case "sin": return Mul(N(-1), k, new LambekFunc("cos", fn.Argument));
            case "cos": return Mul(k, new LambekFunc("sin", fn.Argument));
            case "tan": return Mul(N(-1), k, new LambekFunc("ln", new LambekFunc("abs", new LambekFunc("cos", fn.Argument))));
            case "ln": return Mul(k, Add(Mul(fn.Argument, fn), Neg(fn.Argument)));
        }
        return null;
    }

    // Substitute a value for a letter
    public static LambekExpr Substitute(LambekExpr e, string x, LambekExpr value)
    {
        if (e is LambekSym) return ((LambekSym)e).Name == x ? value : e;
        if (e is LambekSum) return new LambekSum(((LambekSum)e).Terms.Select(t => Substitute(t, x, value)));
        if (e is LambekProd) return new LambekProd(((LambekProd)e).Factors.Select(t => Substitute(t, x, value)));
        if (e is LambekPow) return new LambekPow(Substitute(((LambekPow)e).Base, x, value), Substitute(((LambekPow)e).Exponent, x, value));
        if (e is LambekFunc) return new LambekFunc(((LambekFunc)e).Name, Substitute(((LambekFunc)e).Argument, x, value));
        return e;
    }

    // A value in floating point, for what cannot be exact (pi, e, sin 1)
    public static double Numeric(LambekExpr e, Dictionary<string, double> values)
    {
        LambekRational r;
        if (IsNum(e, out r)) return r.ToDouble();
        if (e is LambekSym)
        {
            string name = ((LambekSym)e).Name;
            if (name == "pi") return Math.PI;
            if (name == "e") return Math.E;
            double v;
            if (values != null && values.TryGetValue(name, out v)) return v;
            throw new FormatException("No value for " + name + ".");
        }
        if (e is LambekSum) return ((LambekSum)e).Terms.Sum(t => Numeric(t, values));
        if (e is LambekProd) { double p = 1; foreach (LambekExpr f in ((LambekProd)e).Factors) p *= Numeric(f, values); return p; }
        if (e is LambekPow) return Math.Pow(Numeric(((LambekPow)e).Base, values), Numeric(((LambekPow)e).Exponent, values));
        LambekFunc fn = (LambekFunc)e;
        double a = Numeric(fn.Argument, values);
        switch (fn.Name)
        {
            case "exp": return Math.Exp(a);
            case "sqrt": return Math.Sqrt(a);
            case "sin": return Math.Sin(a);
            case "cos": return Math.Cos(a);
            case "tan": return Math.Tan(a);
            case "ln": return Math.Log(a);
            case "abs": return Math.Abs(a);
            case "arctan": return Math.Atan(a);
            case "arcsin": return Math.Asin(a);
            case "arccos": return Math.Acos(a);
        }
        throw new FormatException("Unknown function " + fn.Name + ".");
    }

    // Integral from a to b: exact by the primitive when it has one, else Simpson's rule, adaptive, said as an approximation
    public static string Definite(LambekExpr e, string x, LambekExpr from, LambekExpr to, out bool exact)
    {
        LambekExpr primitive = Integrate(e, x);
        exact = false;
        if (primitive != null)
        {
            LambekExpr value = Simplify(Add(Substitute(primitive, x, to), Neg(Substitute(primitive, x, from))));
            LambekRational r;
            if (IsNum(value, out r)) { exact = true; return r.Exact(); }
            try { double v = Numeric(value, null); if (!double.IsNaN(v)) return Show(value) + " ≈ " + Format(v); } catch (FormatException) { }
        }
        e = Simplify(e);
        double a = Numeric(from, null), b = Numeric(to, null);
        Func<double, double> f = t => Numeric(e, new Dictionary<string, double> { { x, t } });
        double result = Simpson(f, a, b, 1e-12, 30);
        if (double.IsNaN(result) || double.IsInfinity(result)) throw new FormatException("The integral does not converge on this interval.");
        return "≈ " + Format(result);
    }

    static double Simpson(Func<double, double> f, double a, double b, double tolerance, int depth)
    {
        double c = (a + b) / 2, fa = f(a), fb = f(b), fc = f(c);
        double whole = (b - a) / 6 * (fa + 4 * fc + fb);
        return Refine(f, a, b, fa, fb, fc, whole, tolerance, depth);
    }

    static double Refine(Func<double, double> f, double a, double b, double fa, double fb, double fc, double whole, double tolerance, int depth)
    {
        double c = (a + b) / 2, d = (a + c) / 2, g = (c + b) / 2;
        double fd = f(d), fg = f(g);
        double left = (c - a) / 6 * (fa + 4 * fd + fc), right = (b - c) / 6 * (fc + 4 * fg + fb);
        if (depth <= 0 || Math.Abs(left + right - whole) <= 15 * tolerance) return left + right + (left + right - whole) / 15;
        return Refine(f, a, c, fa, fc, fd, left, tolerance / 2, depth - 1) + Refine(f, c, b, fc, fb, fg, right, tolerance / 2, depth - 1);
    }

    public static string Format(double value)
    {
        if (Math.Abs(value) < 1e-12) return "0";
        return value.ToString("0.##########", CultureInfo.InvariantCulture);
    }

    // A polynomial in x, when the expression is one (after expansion); null otherwise
    public static LambekPolynomial ToPolynomial(LambekExpr e, string x)
    {
        LambekExpr expanded = Expand(e);
        List<LambekExpr> terms = expanded is LambekSum ? ((LambekSum)expanded).Terms : new List<LambekExpr> { expanded };
        LambekPolynomial p = LambekPolynomial.Constant(LambekRational.Zero);
        foreach (LambekExpr term in terms)
        {
            LambekRational c; LambekExpr rest;
            Split(term, out c, out rest);
            int degree = 0;
            if (rest != null)
            {
                if (rest is LambekSym && ((LambekSym)rest).Name == x) degree = 1;
                else if (rest is LambekPow && ((LambekPow)rest).Base is LambekSym && ((LambekSym)((LambekPow)rest).Base).Name == x)
                {
                    LambekRational n;
                    if (!IsNum(((LambekPow)rest).Exponent, out n) || !n.IsInteger || n.Sign < 0 || n.Numerator > 4096) return null;
                    degree = (int)n.Numerator;
                }
                else return null;
            }
            while (p.Coefficients.Count <= degree) p.Coefficients.Add(LambekRational.Zero);
            p.Coefficients[degree] = p.Coefficients[degree] + c;
        }
        return p.Trim();
    }

    public static LambekExpr FromPolynomial(LambekPolynomial p, string x)
    {
        List<LambekExpr> terms = new List<LambekExpr>();
        for (int k = p.Coefficients.Count - 1; k >= 0; k--)
        {
            if (p.Coefficients[k].IsZero) continue;
            terms.Add(Mul(N(p.Coefficients[k]), Pow(new LambekSym(x), N(k))));
        }
        return Simplify(new LambekSum(terms));
    }

    // A quotient of two polynomials, reduced by their GCD: (x^2 - 1)/(x - 1) is x + 1
    public static LambekExpr ReduceFraction(LambekExpr e, string x)
    {
        e = Simplify(e);
        List<LambekExpr> numerator = new List<LambekExpr>(), denominator = new List<LambekExpr>();
        List<LambekExpr> factors = e is LambekProd ? ((LambekProd)e).Factors : new List<LambekExpr> { e };
        foreach (LambekExpr f in factors)
        {
            LambekPow p = f as LambekPow;
            LambekRational n;
            if (p != null && IsNum(p.Exponent, out n) && n.IsInteger && n.Sign < 0) denominator.Add(Pow(p.Base, N(-n)));
            else numerator.Add(f);
        }
        if (denominator.Count == 0) return null;
        LambekPolynomial top = ToPolynomial(numerator.Count == 0 ? N(1) : new LambekProd(numerator), x);
        LambekPolynomial bottom = ToPolynomial(new LambekProd(denominator), x);
        if (top == null || bottom == null) return null;
        LambekPolynomial g = LambekPolynomials.Gcd(top, bottom);
        if (g.Degree == 0) return null;
        LambekPolynomial q1 = LambekPolynomials.DivideExact(top, g), q2 = LambekPolynomials.DivideExact(bottom, g);
        // The denominator made monic, its leading coefficient moved up
        LambekRational lead = q2.At(q2.Degree);
        q1 = q1.Divide(lead);
        q2 = q2.Divide(lead);
        LambekExpr up = FromPolynomial(q1, x);
        if (q2.Degree == 0) return up;
        return new LambekProd(new[] { up, new LambekPow(FromPolynomial(q2, x), N(-1)) });
    }

    // Show: the usual notation, fewest parentheses, a minus sign instead of "+ -1"
    public static string Show(LambekExpr e)
    {
        return Show(e, 0);
    }

    static string Show(LambekExpr e, int outer)
    {
        LambekRational value;
        if (IsNum(e, out value))
        {
            string text = value.Exact();
            bool wrap = (value.Sign < 0 && outer > 0) || (!value.IsInteger && outer >= 2);
            return wrap ? "(" + text + ")" : text;
        }
        if (e is LambekSym) return ((LambekSym)e).Name == "pi" ? "π" : ((LambekSym)e).Name;
        if (e is LambekSum)
        {
            StringBuilder b = new StringBuilder();
            List<LambekExpr> terms = ((LambekSum)e).Terms;
            for (int i = 0; i < terms.Count; i++)
            {
                LambekRational c; LambekExpr rest;
                Split(terms[i], out c, out rest);
                bool negative = c.Sign < 0;
                LambekExpr shown = negative ? (rest == null ? N(-c) : (c.Equals(Q(-1)) ? rest : new LambekProd(new[] { N(-c), rest }))) : terms[i];
                if (i == 0) b.Append(negative ? "-" : "");
                else b.Append(negative ? " - " : " + ");
                b.Append(Show(shown, 1));
            }
            string text = b.ToString();
            return outer >= 1 ? "(" + text + ")" : text;
        }
        if (e is LambekProd)
        {
            List<LambekExpr> f = ((LambekProd)e).Factors;
            List<string> up = new List<string>(), down = new List<string>();
            string sign = "";
            foreach (LambekExpr factor in f)
            {
                LambekPow p = factor as LambekPow;
                LambekRational n;
                if (IsNum(factor, out n) && n.Equals(Q(-1)) && f.Count > 1) { sign = "-"; continue; }
                if (IsNum(factor, out n) && !n.IsInteger)
                {
                    // 2/3 x is written 2x/3
                    if (!(n.Numerator.IsOne && f.Count > 1)) up.Add((n.Sign < 0 && up.Count == 0 && sign == "" ? "-" : "") + BigInteger.Abs(n.Numerator).ToString(CultureInfo.InvariantCulture));
                    else if (n.Sign < 0) sign = "-";
                    down.Add(n.Denominator.ToString(CultureInfo.InvariantCulture));
                    continue;
                }
                if (p != null && IsNum(p.Exponent, out n) && n.Sign < 0)
                {
                    LambekExpr inverse = n.Equals(Q(-1)) ? p.Base : new LambekPow(p.Base, N(-n));
                    down.Add(Show(inverse, 2));
                    continue;
                }
                up.Add(Show(factor, 2));
            }
            string top = up.Count == 0 ? "1" : Join(up);
            string text = sign + top + (down.Count > 0 ? "/" + (down.Count == 1 ? down[0] : "(" + string.Join(" × ", down) + ")") : "");
            return outer >= 3 || (outer == 2 && (down.Count > 0 || sign != "")) ? "(" + text + ")" : text;
        }
        if (e is LambekPow)
        {
            LambekPow p = (LambekPow)e;
            LambekRational n;
            if (IsNum(p.Exponent, out n) && n.Equals(new LambekRational(1, 2))) return "√" + Show(p.Base, 3);
            if (IsNum(p.Exponent, out n) && n.Sign < 0)
            {
                string text = "1/" + Show(n.Equals(Q(-1)) ? p.Base : new LambekPow(p.Base, N(-n)), 3);
                return outer >= 2 ? "(" + text + ")" : text;
            }
            if (p.Base is LambekSym && ((LambekSym)p.Base).Name == "e") return "e^" + Show(p.Exponent, 3);
            return Show(p.Base, 3) + "^" + Show(p.Exponent, 3);
        }
        LambekFunc fn = (LambekFunc)e;
        if (fn.Name == "abs") return "|" + Show(fn.Argument, 0) + "|";
        return fn.Name + "(" + Show(fn.Argument, 0) + ")";
    }

    static string Join(List<string> parts)
    {
        // "3x", "2 sin(x)", "x y": a number glued to a letter, a space elsewhere
        StringBuilder b = new StringBuilder(parts[0]);
        for (int i = 1; i < parts.Count; i++)
        {
            string before = parts[i - 1], next = parts[i];
            bool glue = before.Length > 0 && char.IsDigit(before[before.Length - 1]) && next.Length > 0 && (char.IsLetter(next[0]) || next[0] == '(' || next[0] == '√');
            if (!glue && char.IsLetter(before[before.Length - 1]) && next.Length == 1 && char.IsLetter(next[0])) glue = true;
            b.Append(glue ? "" : " × ").Append(next);
        }
        return b.ToString();
    }
}

// Polynomials over the rationals: GCD by Euclid, the square-free part, and real roots isolated by Sturm's theorem
public static class LambekPolynomials
{
    public static LambekPolynomial Derivative(LambekPolynomial p)
    {
        LambekPolynomial d = new LambekPolynomial();
        for (int k = 1; k < p.Coefficients.Count; k++) d.Coefficients.Add(p.Coefficients[k] * new LambekRational(k, 1));
        return d.Trim();
    }

    public static void DivRem(LambekPolynomial a, LambekPolynomial b, out LambekPolynomial quotient, out LambekPolynomial remainder)
    {
        if (b.Degree == 0 && b.At(0).IsZero) throw new DivideByZeroException("Division by the zero polynomial.");
        remainder = LambekPolynomial.Constant(LambekRational.Zero);
        remainder.Coefficients.Clear();
        remainder.Coefficients.AddRange(a.Coefficients);
        remainder.Trim();
        quotient = LambekPolynomial.Constant(LambekRational.Zero);
        int db = b.Degree;
        LambekRational lead = b.At(db);
        while (!(remainder.Degree == 0 && remainder.At(0).IsZero) && remainder.Degree >= db)
        {
            int shift = remainder.Degree - db;
            LambekRational factor = remainder.At(remainder.Degree) / lead;
            while (quotient.Coefficients.Count <= shift) quotient.Coefficients.Add(LambekRational.Zero);
            quotient.Coefficients[shift] = quotient.Coefficients[shift] + factor;
            for (int k = 0; k <= db; k++) remainder.Coefficients[k + shift] = remainder.Coefficients[k + shift] - factor * b.At(k);
            remainder.Trim();
        }
        quotient.Trim();
    }

    public static LambekPolynomial DivideExact(LambekPolynomial a, LambekPolynomial b)
    {
        LambekPolynomial q, r;
        DivRem(a, b, out q, out r);
        return q;
    }

    // The monic GCD by Euclid's algorithm
    public static LambekPolynomial Gcd(LambekPolynomial a, LambekPolynomial b)
    {
        LambekPolynomial x = Copy(a), y = Copy(b);
        while (!(y.Degree == 0 && y.At(0).IsZero))
        {
            LambekPolynomial q, r;
            DivRem(x, y, out q, out r);
            x = y;
            y = r;
        }
        if (x.Degree == 0 && x.At(0).IsZero) return x;
        return x.Divide(x.At(x.Degree));
    }

    static LambekPolynomial Copy(LambekPolynomial p) { LambekPolynomial c = new LambekPolynomial(); c.Coefficients.AddRange(p.Coefficients); return c.Trim(); }

    // f / gcd(f, f'): the same roots, each once
    public static LambekPolynomial SquareFree(LambekPolynomial p)
    {
        LambekPolynomial g = Gcd(p, Derivative(p));
        if (g.Degree == 0) return Copy(p);
        return DivideExact(p, g);
    }

    // Sturm: p0 = p, p1 = p', p(k+1) = -rem(p(k-1), p(k)); the roots in (a, b] are V(a) - V(b), V the sign changes
    public static List<LambekPolynomial> Sturm(LambekPolynomial p)
    {
        List<LambekPolynomial> chain = new List<LambekPolynomial> { Copy(p), Derivative(p) };
        while (!(chain[chain.Count - 1].Degree == 0 && chain[chain.Count - 1].At(0).IsZero))
        {
            LambekPolynomial q, r;
            DivRem(chain[chain.Count - 2], chain[chain.Count - 1], out q, out r);
            if (r.Degree == 0 && r.At(0).IsZero) break;
            chain.Add(-r);
        }
        return chain;
    }

    static int Changes(List<LambekPolynomial> chain, LambekRational x)
    {
        int changes = 0, last = 0;
        foreach (LambekPolynomial p in chain)
        {
            int sign = p.Evaluate(x).Sign;
            if (sign == 0) continue;
            if (last != 0 && sign != last) changes++;
            last = sign;
        }
        return changes;
    }

    // Every real root, each in an interval of rationals certified to hold exactly one, narrowed below the given width
    public static List<LambekRational[]> RealRoots(LambekPolynomial p, LambekRational width)
    {
        LambekPolynomial f = SquareFree(p);
        List<LambekRational[]> found = new List<LambekRational[]>();
        if (f.Degree < 1) return found;
        // Cauchy's bound: every root is within 1 + max |a_k / a_n|
        LambekRational bound = LambekRational.Zero;
        LambekRational lead = f.At(f.Degree);
        for (int k = 0; k < f.Degree; k++)
        {
            LambekRational r = f.At(k) / lead;
            if (r.Sign < 0) r = -r;
            if (r.CompareTo(bound) > 0) bound = r;
        }
        bound = bound + LambekRational.One;
        List<LambekPolynomial> chain = Sturm(f);
        Stack<LambekRational[]> work = new Stack<LambekRational[]>();
        work.Push(new[] { -bound, bound });
        int steps = 0;
        while (work.Count > 0)
        {
            if (++steps > 20000) throw new FormatException("The roots are too close to separate.");
            LambekRational[] interval = work.Pop();
            int count = Changes(chain, interval[0]) - Changes(chain, interval[1]);
            if (count == 0) continue;
            if (count == 1)
            {
                // Bisection on the sign of f, exact: the interval (a, b] keeps its one root
                LambekRational a = interval[0], b = interval[1];
                if (f.Evaluate(b).IsZero) { found.Add(new[] { b, b }); continue; }
                int guard = 0;
                while ((b - a).CompareTo(width) > 0 && guard++ < 400)
                {
                    LambekRational m = (a + b) / new LambekRational(2, 1);
                    LambekRational fm = f.Evaluate(m);
                    if (fm.IsZero) { a = m; b = m; break; }
                    if (fm.Sign == f.Evaluate(b).Sign) b = m; else a = m;
                }
                found.Add(new[] { a, b });
                continue;
            }
            LambekRational middle = (interval[0] + interval[1]) / new LambekRational(2, 1);
            work.Push(new[] { middle, interval[1] });
            work.Push(new[] { interval[0], middle });
        }
        return found.OrderBy(r => r[0]).ToList();
    }

    public static string Show(LambekPolynomial p, string x) { return LambekAlgebra.Show(LambekAlgebra.FromPolynomial(p, x)); }
}

// Exact linear algebra: matrices of rationals, determinants by Bareiss, inverses by Gauss-Jordan, the rank, linear
// systems in reduced row echelon form, and the characteristic polynomial by Faddeev-LeVerrier
public class LambekMatrix
{
    public LambekRational[,] Cells;
    public int Rows { get { return Cells.GetLength(0); } }
    public int Columns { get { return Cells.GetLength(1); } }

    public LambekMatrix(int rows, int columns)
    {
        Cells = new LambekRational[rows, columns];
        for (int i = 0; i < rows; i++) for (int j = 0; j < columns; j++) Cells[i, j] = LambekRational.Zero;
    }

    public static LambekMatrix Identity(int n) { LambekMatrix m = new LambekMatrix(n, n); for (int i = 0; i < n; i++) m.Cells[i, i] = LambekRational.One; return m; }

    // "[[1, 2], [3, 4]]", "[1 2; 3 4]", "1 2; 3 4"
    public static LambekMatrix Parse(string text)
    {
        string clean = text.Trim();
        List<List<LambekRational>> rows = new List<List<LambekRational>>();
        string[] parts;
        if (clean.StartsWith("[[", StringComparison.Ordinal) || clean.StartsWith("((", StringComparison.Ordinal))
            parts = Regex.Matches(clean.Substring(1, clean.Length - 2), @"[\[(]([^\])]*)[\])]").Cast<Match>().Select(m => m.Groups[1].Value).ToArray();
        else parts = clean.Trim('[', ']', '(', ')').Split(new[] { ';', '|' }, StringSplitOptions.RemoveEmptyEntries);
        foreach (string row in parts)
        {
            List<LambekRational> values = new List<LambekRational>();
            foreach (Match m in Regex.Matches(row, @"-?\d+(?:\.\d+)?(?:/\d+)?"))
            {
                string[] q = m.Value.Split('/');
                LambekRational v = LambekRational.Parse(q[0]);
                if (q.Length > 1) v = v / LambekRational.Parse(q[1]);
                values.Add(v);
            }
            if (values.Count > 0) rows.Add(values);
        }
        if (rows.Count == 0) throw new FormatException("No matrix found: write it like [[1, 2], [3, 4]].");
        int columns = rows[0].Count;
        if (rows.Any(r => r.Count != columns)) throw new FormatException("Every row of a matrix needs as many numbers.");
        if (rows.Count > 12 || columns > 12) throw new FormatException("At most 12 rows and 12 columns.");
        LambekMatrix matrix = new LambekMatrix(rows.Count, columns);
        for (int i = 0; i < rows.Count; i++) for (int j = 0; j < columns; j++) matrix.Cells[i, j] = rows[i][j];
        return matrix;
    }

    public LambekMatrix Copy() { LambekMatrix m = new LambekMatrix(Rows, Columns); Array.Copy(Cells, m.Cells, Cells.Length); return m; }

    public LambekMatrix Transpose()
    {
        LambekMatrix t = new LambekMatrix(Columns, Rows);
        for (int i = 0; i < Rows; i++) for (int j = 0; j < Columns; j++) t.Cells[j, i] = Cells[i, j];
        return t;
    }

    public static LambekMatrix operator *(LambekMatrix a, LambekMatrix b)
    {
        if (a.Columns != b.Rows) throw new FormatException("The columns of the first matrix must match the rows of the second.");
        LambekMatrix c = new LambekMatrix(a.Rows, b.Columns);
        for (int i = 0; i < a.Rows; i++)
            for (int j = 0; j < b.Columns; j++)
            {
                LambekRational sum = LambekRational.Zero;
                for (int k = 0; k < a.Columns; k++) sum = sum + a.Cells[i, k] * b.Cells[k, j];
                c.Cells[i, j] = sum;
            }
        return c;
    }

    public LambekRational Trace() { LambekRational t = LambekRational.Zero; for (int i = 0; i < Math.Min(Rows, Columns); i++) t = t + Cells[i, i]; return t; }

    // Bareiss: integer entries (scaled by the common denominator), a(k)ij = (a(k-1)kk a(k-1)ij - a(k-1)ik a(k-1)kj) / a(k-2)(k-1)(k-1),
    // every division exact, so no fraction ever grows; det(sA) = s^n det(A)
    public LambekRational Determinant()
    {
        if (Rows != Columns) throw new FormatException("Only a square matrix has a determinant.");
        int n = Rows;
        BigInteger scale = BigInteger.One;
        for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) scale = scale / BigInteger.GreatestCommonDivisor(scale, Cells[i, j].Denominator) * Cells[i, j].Denominator;
        BigInteger[,] a = new BigInteger[n, n];
        for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) a[i, j] = Cells[i, j].Numerator * (scale / Cells[i, j].Denominator);
        BigInteger previous = BigInteger.One;
        int sign = 1;
        for (int k = 0; k < n - 1; k++)
        {
            if (a[k, k].IsZero)
            {
                int swap = -1;
                for (int r = k + 1; r < n; r++) if (!a[r, k].IsZero) { swap = r; break; }
                if (swap < 0) return LambekRational.Zero;
                for (int j = 0; j < n; j++) { BigInteger t = a[k, j]; a[k, j] = a[swap, j]; a[swap, j] = t; }
                sign = -sign;
            }
            for (int i = k + 1; i < n; i++)
                for (int j = k + 1; j < n; j++)
                    a[i, j] = (a[k, k] * a[i, j] - a[i, k] * a[k, j]) / previous;
            previous = a[k, k];
        }
        return new LambekRational(sign * a[n - 1, n - 1], BigInteger.Pow(scale, n));
    }

    // Reduced row echelon form by exact Gauss-Jordan; the pivot columns come back
    public List<int> Reduce()
    {
        List<int> pivots = new List<int>();
        int row = 0;
        for (int column = 0; column < Columns && row < Rows; column++)
        {
            int found = -1;
            for (int r = row; r < Rows; r++) if (!Cells[r, column].IsZero) { found = r; break; }
            if (found < 0) continue;
            for (int j = 0; j < Columns; j++) { LambekRational t = Cells[row, j]; Cells[row, j] = Cells[found, j]; Cells[found, j] = t; }
            LambekRational pivot = Cells[row, column];
            for (int j = 0; j < Columns; j++) Cells[row, j] = Cells[row, j] / pivot;
            for (int r = 0; r < Rows; r++)
            {
                if (r == row || Cells[r, column].IsZero) continue;
                LambekRational factor = Cells[r, column];
                for (int j = 0; j < Columns; j++) Cells[r, j] = Cells[r, j] - factor * Cells[row, j];
            }
            pivots.Add(column);
            row++;
        }
        return pivots;
    }

    public int Rank() { return Copy().Reduce().Count; }

    public LambekMatrix Inverse()
    {
        if (Rows != Columns) throw new FormatException("Only a square matrix has an inverse.");
        int n = Rows;
        LambekMatrix work = new LambekMatrix(n, 2 * n);
        for (int i = 0; i < n; i++) { for (int j = 0; j < n; j++) work.Cells[i, j] = Cells[i, j]; work.Cells[i, n + i] = LambekRational.One; }
        List<int> pivots = work.Reduce();
        if (pivots.Count < n || pivots[n - 1] >= n) throw new FormatException("The matrix is singular: its determinant is 0, it has no inverse.");
        LambekMatrix inverse = new LambekMatrix(n, n);
        for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) inverse.Cells[i, j] = work.Cells[i, n + j];
        return inverse;
    }

    // Faddeev-LeVerrier: M1 = I, c(n-1) = -tr(A); M(k) = A M(k-1) + c(n-k+1) I, c(n-k) = -tr(A M(k)) / k; exact on rationals
    public LambekPolynomial Characteristic()
    {
        if (Rows != Columns) throw new FormatException("Only a square matrix has eigenvalues.");
        int n = Rows;
        LambekRational[] c = new LambekRational[n + 1];
        c[n] = LambekRational.One;
        LambekMatrix m = new LambekMatrix(n, n);
        for (int k = 1; k <= n; k++)
        {
            LambekMatrix am = this * m;
            m = am;
            for (int i = 0; i < n; i++) m.Cells[i, i] = m.Cells[i, i] + c[n - k + 1];
            c[n - k] = -(this * m).Trace() / new LambekRational(k, 1);
        }
        LambekPolynomial p = new LambekPolynomial();
        p.Coefficients.AddRange(c);
        return p.Trim();
    }

    public string Show()
    {
        List<string> rows = new List<string>();
        for (int i = 0; i < Rows; i++)
        {
            List<string> cells = new List<string>();
            for (int j = 0; j < Columns; j++) cells.Add(Cells[i, j].Exact());
            rows.Add("[" + string.Join(", ", cells) + "]");
        }
        return "[" + string.Join(", ", rows) + "]";
    }
}

public class LambekSystemResult
{
    public string Kind;           // unique, none, many
    public string[] Letters = new string[0];
    public string[] Values = new string[0];
    public string[] Free = new string[0];
}

public static class LambekLinear
{
    // A linear system: each equation reduced to sum(a_i x_i) = b, then Gauss-Jordan on the augmented matrix.
    // Rank of A below rank of [A|b]: no solution; equal to the number of letters: one; else a family, the free letters kept
    public static LambekSystemResult Solve(string[] equations)
    {
        List<LambekExpr> sides = new List<LambekExpr>();
        SortedSet<string> letters = new SortedSet<string>(StringComparer.Ordinal);
        foreach (string equation in equations)
        {
            string[] halves = equation.Split('=');
            if (halves.Length != 2) throw new FormatException("Each equation needs one '=': " + equation.Trim());
            LambekExpr difference = LambekAlgebra.Expand(LambekAlgebra.Add(LambekAlgebra.Parse(halves[0]), LambekAlgebra.Neg(LambekAlgebra.Parse(halves[1]))));
            sides.Add(difference);
            letters.UnionWith(LambekAlgebra.Letters(difference));
        }
        if (letters.Count == 0) throw new FormatException("The equations have no unknown.");
        if (letters.Count > 12 || sides.Count > 12) throw new FormatException("At most 12 equations and 12 unknowns.");
        List<string> names = letters.ToList();
        LambekMatrix m = new LambekMatrix(sides.Count, names.Count + 1);
        for (int i = 0; i < sides.Count; i++)
        {
            // Each coefficient is the derivative by its letter, a number when the equation is linear
            LambekExpr rest = sides[i];
            for (int j = 0; j < names.Count; j++)
            {
                LambekExpr d = LambekAlgebra.Derive(sides[i], names[j]);
                LambekRational a;
                if (!LambekAlgebra.IsNum(d, out a)) throw new FormatException("The system is not linear in " + names[j] + ".");
                m.Cells[i, j] = a;
                rest = LambekAlgebra.Substitute(rest, names[j], new LambekNum(0));
            }
            LambekRational constant;
            if (!LambekAlgebra.IsNum(LambekAlgebra.Simplify(rest), out constant)) throw new FormatException("The system is not linear.");
            m.Cells[i, names.Count] = -constant;
        }
        List<int> pivots = m.Reduce();
        LambekSystemResult result = new LambekSystemResult { Letters = names.ToArray() };
        if (pivots.Contains(names.Count)) { result.Kind = "none"; return result; }
        List<string> free = names.Where((n, j) => !pivots.Contains(j)).ToList();
        List<string> values = new List<string>();
        for (int j = 0; j < names.Count; j++)
        {
            int row = pivots.IndexOf(j);
            if (row < 0) { values.Add(names[j]); continue; }
            List<LambekExpr> terms = new List<LambekExpr> { new LambekNum(m.Cells[row, names.Count]) };
            for (int k = 0; k < names.Count; k++)
            {
                if (k == j || pivots.Contains(k) || m.Cells[row, k].IsZero) continue;
                terms.Add(LambekAlgebra.Mul(new LambekNum(-m.Cells[row, k]), new LambekSym(names[k])));
            }
            values.Add(LambekAlgebra.Show(LambekAlgebra.Simplify(new LambekSum(terms))));
        }
        result.Kind = free.Count == 0 ? "unique" : "many";
        result.Values = values.ToArray();
        result.Free = free.ToArray();
        return result;
    }
}

// Whole numbers: primes by Miller-Rabin, factors by trial division then Pollard's rho (Brent), GCD, LCM, modular
// arithmetic, bases, combinatorics, and exact statistics
public static class LambekNumbers
{
    static readonly int[] SmallPrimes = new[] { 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41 };

    public static BigInteger Factorial(int n) { BigInteger p = BigInteger.One; for (int k = 2; k <= n; k++) p *= k; return p; }

    // Miller-Rabin with the first 13 primes as witnesses: deterministic below 3.3 * 10^24 (Sorenson and Webster, 2015)
    public static bool IsPrime(BigInteger n, out bool certain)
    {
        certain = true;
        if (n < 2) return false;
        foreach (int p in SmallPrimes) { if (n == p) return true; if (n % p == 0) return false; }
        BigInteger d = n - 1;
        int s = 0;
        while (d.IsEven) { d >>= 1; s++; }
        foreach (int a in SmallPrimes)
        {
            BigInteger x = BigInteger.ModPow(a, d, n);
            if (x.IsOne || x == n - 1) continue;
            bool composite = true;
            for (int r = 1; r < s; r++)
            {
                x = BigInteger.ModPow(x, 2, n);
                if (x == n - 1) { composite = false; break; }
            }
            if (composite) return false;
        }
        certain = n < BigInteger.Parse("3317044064679887385961981");
        return true;
    }

    public static bool IsPrime(BigInteger n) { bool certain; return IsPrime(n, out certain); }

    // Prime factors with their powers, smallest first; "p^k" strings
    public static string[] Factor(BigInteger n)
    {
        if (n < 2) throw new FormatException("Only a whole number of at least 2 has prime factors.");
        SortedDictionary<BigInteger, int> factors = new SortedDictionary<BigInteger, int>();
        BigInteger rest = n;
        for (int p = 2; p < 100000 && (BigInteger)p * p <= rest; p++)
        {
            while (rest % p == 0) { Add(factors, p); rest /= p; }
        }
        Stack<BigInteger> work = new Stack<BigInteger>();
        if (rest > 1) work.Push(rest);
        int budget = 0;
        while (work.Count > 0)
        {
            BigInteger m = work.Pop();
            if (IsPrime(m)) { Add(factors, m); continue; }
            BigInteger d = Rho(m);
            if (d.IsOne || d == m || ++budget > 200) throw new FormatException("This number is too large to factor here.");
            work.Push(d);
            work.Push(m / d);
        }
        return factors.Select(f => f.Value == 1 ? f.Key.ToString() : f.Key + "^" + f.Value).ToArray();
    }

    static void Add(SortedDictionary<BigInteger, int> factors, BigInteger p) { factors[p] = factors.ContainsKey(p) ? factors[p] + 1 : 1; }

    // Pollard's rho with Brent's cycle detection and batched GCDs
    static BigInteger Rho(BigInteger n)
    {
        if (n.IsEven) return 2;
        for (int c = 1; c < 50; c++)
        {
            BigInteger y = 2, x = 2, g = 1, q = 1, ys = 2;
            int r = 1, m = 128;
            Func<BigInteger, BigInteger> f = v => (v * v + c) % n;
            long steps = 0;
            do
            {
                x = y;
                for (int i = 0; i < r; i++) y = f(y);
                int k = 0;
                do
                {
                    ys = y;
                    for (int i = 0; i < Math.Min(m, r - k); i++) { y = f(y); q = q * BigInteger.Abs(x - y) % n; }
                    g = BigInteger.GreatestCommonDivisor(q, n);
                    k += m;
                    steps += m;
                } while (k < r && g.IsOne);
                r *= 2;
                if (steps > 4000000) break;
            } while (g.IsOne);
            if (g == n)
            {
                do { ys = f(ys); g = BigInteger.GreatestCommonDivisor(BigInteger.Abs(x - ys), n); } while (g.IsOne);
            }
            if (g != n && !g.IsOne) return g;
        }
        return BigInteger.One;
    }

    public static BigInteger Gcd(BigInteger[] values) { BigInteger g = 0; foreach (BigInteger v in values) g = BigInteger.GreatestCommonDivisor(g, v); return g; }
    public static BigInteger Lcm(BigInteger[] values)
    {
        BigInteger l = 1;
        foreach (BigInteger v in values)
        {
            if (v.IsZero) return 0;
            l = BigInteger.Abs(l / BigInteger.GreatestCommonDivisor(l, v) * v);
        }
        return l;
    }

    // The remainder always between 0 and n - 1, even for a negative number
    public static BigInteger Mod(BigInteger a, BigInteger n)
    {
        if (n.IsZero) throw new DivideByZeroException("Modulo zero.");
        BigInteger r = a % n;
        return r.Sign < 0 ? r + BigInteger.Abs(n) : r;
    }

    public static BigInteger ModPow(BigInteger a, BigInteger e, BigInteger n)
    {
        if (e.Sign < 0) return ModPow(ModInverse(a, n), -e, n);
        return BigInteger.ModPow(Mod(a, n), e, n);
    }

    // Extended Euclid: a u + n v = gcd(a, n); the inverse exists when the gcd is 1
    public static BigInteger ModInverse(BigInteger a, BigInteger n)
    {
        BigInteger oldR = Mod(a, n), r = n, oldS = 1, s = 0;
        while (!r.IsZero)
        {
            BigInteger q = oldR / r;
            BigInteger t = r; r = oldR - q * r; oldR = t;
            t = s; s = oldS - q * s; oldS = t;
        }
        if (!oldR.IsOne) throw new FormatException(a + " has no inverse modulo " + n + ": they share the factor " + oldR + ".");
        return Mod(oldS, n);
    }

    const string Digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";

    public static string ToBase(BigInteger n, int b)
    {
        if (b < 2 || b > 36) throw new FormatException("A base goes from 2 to 36.");
        if (n.IsZero) return "0";
        bool negative = n.Sign < 0;
        n = BigInteger.Abs(n);
        StringBuilder text = new StringBuilder();
        while (!n.IsZero) { text.Insert(0, Digits[(int)(n % b)]); n /= b; }
        return (negative ? "-" : "") + text;
    }

    public static BigInteger FromBase(string text, int b)
    {
        if (b < 2 || b > 36) throw new FormatException("A base goes from 2 to 36.");
        BigInteger n = 0;
        string clean = text.Trim().ToUpperInvariant();
        bool negative = clean.StartsWith("-", StringComparison.Ordinal);
        foreach (char c in clean.TrimStart('-'))
        {
            int d = Digits.IndexOf(c);
            if (d < 0 || d >= b) throw new FormatException("'" + c + "' is not a digit in base " + b + ".");
            n = n * b + d;
        }
        return negative ? -n : n;
    }

    public static BigInteger Choose(BigInteger n, BigInteger k)
    {
        if (k.Sign < 0 || k > n || n.Sign < 0) return 0;
        if (n > 100000) throw new FormatException("n must be at most 100000.");
        if (k > n - k) k = n - k;
        BigInteger result = 1;
        for (BigInteger i = 1; i <= k; i++) result = result * (n - k + i) / i;
        return result;
    }

    public static BigInteger Arrangements(BigInteger n, BigInteger k)
    {
        if (k.Sign < 0 || k > n || n.Sign < 0) return 0;
        if (n > 100000) throw new FormatException("n must be at most 100000.");
        BigInteger result = 1;
        for (BigInteger i = n - k + 1; i <= n; i++) result *= i;
        return result;
    }

    public static BigInteger Fibonacci(int n)
    {
        if (n < 0 || n > 100000) throw new FormatException("n must be from 0 to 100000.");
        BigInteger a = 0, b = 1;
        for (int i = 0; i < n; i++) { BigInteger t = a + b; a = b; b = t; }
        return a;
    }

    public static BigInteger Totient(BigInteger n)
    {
        if (n < 1) throw new FormatException("Euler's totient needs a positive whole number.");
        if (n.IsOne) return 1;
        BigInteger result = n;
        foreach (string f in Factor(n)) { BigInteger p = BigInteger.Parse(f.Split('^')[0]); result = result / p * (p - 1); }
        return result;
    }

    public static bool ExactNthRoot(LambekRational x, int n, out LambekRational root)
    {
        root = LambekRational.Zero;
        BigInteger a, b;
        if (!IntegerNthRoot(x.Numerator, n, out a) || !IntegerNthRoot(x.Denominator, n, out b)) return false;
        root = new LambekRational(a, b);
        return true;
    }

    static bool IntegerNthRoot(BigInteger v, int n, out BigInteger root)
    {
        root = 0;
        if (v.Sign < 0) return false;
        if (v.IsZero || v.IsOne) { root = v; return true; }
        BigInteger guess = new BigInteger(Math.Round(Math.Exp(BigInteger.Log(v) / n)));
        for (BigInteger g = BigInteger.Max(0, guess - 2); g <= guess + 2; g++)
        {
            if (BigInteger.Pow(g, n) == v) { root = g; return true; }
        }
        return false;
    }

    // Statistics on exact numbers: mean, median, modes, variance (population and sample), standard deviation
    public static Dictionary<string, string> Statistics(LambekRational[] values)
    {
        if (values.Length == 0) throw new FormatException("No numbers to describe.");
        Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.Ordinal);
        LambekRational sum = LambekRational.Zero;
        foreach (LambekRational v in values) sum = sum + v;
        LambekRational n = new LambekRational(values.Length, 1);
        LambekRational mean = sum / n;
        LambekRational[] sorted = values.OrderBy(v => v).ToArray();
        LambekRational median = values.Length % 2 == 1 ? sorted[values.Length / 2] : (sorted[values.Length / 2 - 1] + sorted[values.Length / 2]) / new LambekRational(2, 1);
        LambekRational squares = LambekRational.Zero;
        foreach (LambekRational v in values) squares = squares + (v - mean) * (v - mean);
        LambekRational population = squares / n;
        result["count"] = values.Length.ToString(CultureInfo.InvariantCulture);
        result["sum"] = sum.Exact();
        result["mean"] = mean.Exact();
        result["median"] = median.Exact();
        result["min"] = sorted[0].Exact();
        result["max"] = sorted[sorted.Length - 1].Exact();
        result["range"] = (sorted[sorted.Length - 1] - sorted[0]).Exact();
        result["variance"] = population.Exact();
        result["stddev"] = Root(population);
        if (values.Length > 1)
        {
            LambekRational sample = squares / new LambekRational(values.Length - 1, 1);
            result["samplevariance"] = sample.Exact();
            result["samplestddev"] = Root(sample);
        }
        // The values seen most often, when some value is seen more than once
        var groups = sorted.GroupBy(v => v.Exact()).Select(g => new { Value = g.Key, Count = g.Count() }).ToList();
        int top = groups.Max(g => g.Count);
        if (top > 1) result["mode"] = string.Join(", ", groups.Where(g => g.Count == top).Select(g => g.Value));
        return result;
    }

    static string Root(LambekRational value)
    {
        LambekRational root;
        if (LambekMath.ExactRoot(value, out root)) return root.Exact();
        return LambekMath.Radical(value) + " ≈ " + LambekAlgebra.Format(Math.Sqrt(value.ToDouble()));
    }
}
