// Exact calculation: rational numbers on BigInteger (a float only when a root is irrational, and then it is said),
// polynomials with rational coefficients, equations solved exactly (rational roots, then the quadratic formula
// with its radical simplified), units by dimensional analysis, and dates on the proleptic Gregorian calendar.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Numerics;
using System.Text;
using System.Text.RegularExpressions;

// A fraction always in lowest terms, with a positive denominator
public struct LambekRational : IComparable<LambekRational>
{
    public readonly BigInteger Numerator;
    public readonly BigInteger Denominator;

    public LambekRational(BigInteger numerator, BigInteger denominator)
    {
        if (denominator.IsZero) throw new DivideByZeroException("Division by zero.");
        if (denominator.Sign < 0) { numerator = -numerator; denominator = -denominator; }
        BigInteger g = BigInteger.GreatestCommonDivisor(BigInteger.Abs(numerator), denominator);
        if (g.IsZero) g = BigInteger.One;
        Numerator = numerator / g;
        Denominator = denominator / g;
    }

    public static LambekRational Zero { get { return new LambekRational(0, 1); } }
    public static LambekRational One { get { return new LambekRational(1, 1); } }
    public bool IsZero { get { return Numerator.IsZero; } }
    public bool IsInteger { get { return Denominator.IsOne; } }
    public int Sign { get { return Numerator.Sign; } }

    public static LambekRational operator +(LambekRational a, LambekRational b) { return new LambekRational(a.Numerator * b.Denominator + b.Numerator * a.Denominator, a.Denominator * b.Denominator); }
    public static LambekRational operator -(LambekRational a, LambekRational b) { return new LambekRational(a.Numerator * b.Denominator - b.Numerator * a.Denominator, a.Denominator * b.Denominator); }
    public static LambekRational operator -(LambekRational a) { return new LambekRational(-a.Numerator, a.Denominator); }
    public static LambekRational operator *(LambekRational a, LambekRational b) { return new LambekRational(a.Numerator * b.Numerator, a.Denominator * b.Denominator); }
    public static LambekRational operator /(LambekRational a, LambekRational b)
    {
        if (b.IsZero) throw new DivideByZeroException("Division by zero.");
        return new LambekRational(a.Numerator * b.Denominator, a.Denominator * b.Numerator);
    }

    public LambekRational Power(int exponent)
    {
        if (exponent == 0) return One;
        if (exponent < 0) return One / Power(-exponent);
        return new LambekRational(BigInteger.Pow(Numerator, exponent), BigInteger.Pow(Denominator, exponent));
    }

    public int CompareTo(LambekRational other) { return (Numerator * other.Denominator).CompareTo(other.Numerator * Denominator); }
    public override bool Equals(object other) { return other is LambekRational && CompareTo((LambekRational)other) == 0; }
    public override int GetHashCode() { return Numerator.GetHashCode() ^ Denominator.GetHashCode(); }

    public double ToDouble() { return Math.Exp(BigInteger.Log(BigInteger.Abs(Numerator)) - BigInteger.Log(Denominator)) * Numerator.Sign; }

    // "3/7", "-2", and a decimal when the fraction ends ("0,25"), or a rounded one after "≈"
    public string Exact() { return IsInteger ? Numerator.ToString(CultureInfo.InvariantCulture) : Numerator.ToString(CultureInfo.InvariantCulture) + "/" + Denominator.ToString(CultureInfo.InvariantCulture); }

    public string Decimal(int digits, out bool exact)
    {
        // A fraction ends in base 10 when its denominator has no prime factor but 2 and 5
        BigInteger d = Denominator;
        while (d % 2 == 0) d /= 2;
        while (d % 5 == 0) d /= 5;
        exact = d.IsOne;
        BigInteger scale = BigInteger.Pow(10, digits);
        BigInteger scaled = BigInteger.Abs(Numerator) * scale;
        BigInteger whole = BigInteger.DivRem(scaled, Denominator, out BigInteger rest);
        if (rest * 2 >= Denominator) whole += 1;
        string text = whole.ToString(CultureInfo.InvariantCulture).PadLeft(digits + 1, '0');
        string result = text.Substring(0, text.Length - digits) + "." + text.Substring(text.Length - digits);
        result = result.TrimEnd('0').TrimEnd('.');
        if (Numerator.Sign < 0 && result != "0") result = "-" + result;
        return result;
    }

    public static LambekRational Parse(string text)
    {
        // "12", "3.25", "3,25", "1e3"
        string clean = text.Replace(',', '.');
        int exponent = 0;
        int e = clean.IndexOfAny(new[] { 'e', 'E' });
        if (e > 0)
        {
            // A power of ten is bounded like any power: 1e99999999 would take the whole memory
            if (!int.TryParse(clean.Substring(e + 1), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out exponent) || Math.Abs(exponent) > 4096) throw new FormatException("The exponent is too large.");
            clean = clean.Substring(0, e);
        }
        int dot = clean.IndexOf('.');
        BigInteger numerator;
        BigInteger denominator = BigInteger.One;
        if (dot >= 0)
        {
            string digits = clean.Replace(".", "");
            numerator = BigInteger.Parse(digits, CultureInfo.InvariantCulture);
            denominator = BigInteger.Pow(10, clean.Length - dot - 1);
        }
        else numerator = BigInteger.Parse(clean, CultureInfo.InvariantCulture);
        LambekRational value = new LambekRational(numerator, denominator);
        return exponent == 0 ? value : value * new LambekRational(10, 1).Power(exponent);
    }
}

// A polynomial in one letter: Coefficients[k] is the coefficient of x^k
public class LambekPolynomial
{
    public List<LambekRational> Coefficients = new List<LambekRational>();

    public static LambekPolynomial Constant(LambekRational value) { LambekPolynomial p = new LambekPolynomial(); p.Coefficients.Add(value); return p.Trim(); }
    public static LambekPolynomial Variable() { LambekPolynomial p = new LambekPolynomial(); p.Coefficients.Add(LambekRational.Zero); p.Coefficients.Add(LambekRational.One); return p; }

    public int Degree { get { Trim(); return Coefficients.Count - 1; } }
    public LambekRational At(int k) { return k < Coefficients.Count ? Coefficients[k] : LambekRational.Zero; }

    public LambekPolynomial Trim()
    {
        while (Coefficients.Count > 1 && Coefficients[Coefficients.Count - 1].IsZero) Coefficients.RemoveAt(Coefficients.Count - 1);
        if (Coefficients.Count == 0) Coefficients.Add(LambekRational.Zero);
        return this;
    }

    public static LambekPolynomial operator +(LambekPolynomial a, LambekPolynomial b)
    {
        LambekPolynomial p = new LambekPolynomial();
        for (int k = 0; k < Math.Max(a.Coefficients.Count, b.Coefficients.Count); k++) p.Coefficients.Add(a.At(k) + b.At(k));
        return p.Trim();
    }
    public static LambekPolynomial operator -(LambekPolynomial a) { LambekPolynomial p = new LambekPolynomial(); foreach (LambekRational c in a.Coefficients) p.Coefficients.Add(-c); return p.Trim(); }
    public static LambekPolynomial operator -(LambekPolynomial a, LambekPolynomial b) { return a + (-b); }
    public static LambekPolynomial operator *(LambekPolynomial a, LambekPolynomial b)
    {
        LambekPolynomial p = new LambekPolynomial();
        for (int k = 0; k < a.Coefficients.Count + b.Coefficients.Count - 1; k++) p.Coefficients.Add(LambekRational.Zero);
        for (int i = 0; i < a.Coefficients.Count; i++)
            for (int j = 0; j < b.Coefficients.Count; j++) p.Coefficients[i + j] = p.Coefficients[i + j] + a.Coefficients[i] * b.Coefficients[j];
        return p.Trim();
    }
    public LambekPolynomial Divide(LambekRational value) { LambekPolynomial p = new LambekPolynomial(); foreach (LambekRational c in Coefficients) p.Coefficients.Add(c / value); return p.Trim(); }
    public LambekRational Evaluate(LambekRational x)
    {
        LambekRational result = LambekRational.Zero;
        for (int k = Coefficients.Count - 1; k >= 0; k--) result = result * x + Coefficients[k];
        return result;
    }
}

public class LambekMathResult
{
    public string Kind;
    public string Exact;
    public string Decimal;
    public bool DecimalIsExact;
    public string[] Roots = new string[0];
    public string Note;
}

public static class LambekMath
{
    // Calculation: + - * / ^, parentheses, percent, square root, factorial; a letter makes it a polynomial
    public static LambekMathResult Evaluate(string expression)
    {
        // A lone square root that is not rational: its simplest radical and a value to ten digits
        Match lone = Regex.Match(expression.Trim(), @"^(?:sqrt|racine|√)\s*\(?\s*(\d+(?:[.,]\d+)?(?:\s*/\s*\d+)?)\s*\)?$");
        if (lone.Success)
        {
            string[] parts = lone.Groups[1].Value.Split('/');
            LambekRational inside = LambekRational.Parse(parts[0].Trim());
            if (parts.Length > 1) inside = inside / LambekRational.Parse(parts[1].Trim());
            LambekRational root;
            if (!ExactRoot(inside, out root))
            {
                double approximate = Math.Sqrt(inside.ToDouble());
                return new LambekMathResult { Kind = "value", Exact = Radical(inside), Decimal = approximate.ToString("0.##########", CultureInfo.InvariantCulture), DecimalIsExact = false };
            }
        }
        List<string> tokens = Tokenize(expression);
        int at = 0;
        string letter = null;
        LambekPolynomial left = Sum(tokens, ref at, ref letter);
        if (at < tokens.Count && tokens[at] == "=")
        {
            // An equation: everything on the left, then its roots
            at++;
            LambekPolynomial right = Sum(tokens, ref at, ref letter);
            if (at != tokens.Count) throw new FormatException("Unexpected '" + tokens[at] + "'.");
            return Solve(left - right, letter ?? "x");
        }
        if (at != tokens.Count) throw new FormatException("Unexpected '" + tokens[at] + "'.");
        if (left.Degree > 0) throw new FormatException("An expression with " + letter + " needs an equation.");
        LambekRational value = left.At(0);
        bool exact;
        string decimalText = value.Decimal(10, out exact);
        return new LambekMathResult { Kind = "value", Exact = value.Exact(), Decimal = decimalText, DecimalIsExact = exact };
    }

    static List<string> Tokenize(string text)
    {
        // Numbers (a comma between digits is a decimal comma), letters, operators; x between numbers is a product
        string clean = text.Replace("×", "*").Replace("÷", "/").Replace("−", "-").Replace("²", "^2").Replace("³", "^3").Replace("√", "sqrt").Replace("**", "^");
        List<string> tokens = new List<string>();
        Regex pattern = new Regex(@"\d+(?:[.,]\d+)?(?:[eE][+-]?\d+)?|sqrt|racine|[A-Za-z]|[-+*/^()=%!]");
        int last = 0;
        foreach (Match m in pattern.Matches(clean))
        {
            string between = clean.Substring(last, m.Index - last);
            if (between.Trim().Length > 0) throw new FormatException("Cannot read '" + between.Trim() + "'.");
            last = m.Index + m.Length;
            string token = m.Value == "racine" ? "sqrt" : m.Value;
            // "2x", "3(x+1)", ")(": a product without its sign
            if (tokens.Count > 0)
            {
                string before = tokens[tokens.Count - 1];
                bool closes = char.IsDigit(before[0]) || before == ")" || (before.Length == 1 && char.IsLetter(before[0]));
                bool opens = token == "(" || token == "sqrt" || (token.Length == 1 && char.IsLetter(token[0]));
                if (closes && opens) tokens.Add("*");
            }
            tokens.Add(token);
        }
        if (clean.Substring(last).Trim().Length > 0) throw new FormatException("Cannot read '" + clean.Substring(last).Trim() + "'.");
        return tokens;
    }

    static LambekPolynomial Sum(List<string> tokens, ref int at, ref string letter)
    {
        LambekPolynomial value = Product(tokens, ref at, ref letter);
        while (at < tokens.Count && (tokens[at] == "+" || tokens[at] == "-"))
        {
            string sign = tokens[at++];
            LambekPolynomial next = Product(tokens, ref at, ref letter);
            value = sign == "+" ? value + next : value - next;
        }
        return value;
    }

    static LambekPolynomial Product(List<string> tokens, ref int at, ref string letter)
    {
        LambekPolynomial value = Unary(tokens, ref at, ref letter);
        while (at < tokens.Count && (tokens[at] == "*" || tokens[at] == "/"))
        {
            string sign = tokens[at++];
            LambekPolynomial next = Unary(tokens, ref at, ref letter);
            if (sign == "*") value = value * next;
            else
            {
                if (next.Degree > 0) throw new FormatException("Dividing by " + letter + " is not a polynomial.");
                value = value.Divide(next.At(0));
            }
        }
        return value;
    }

    static LambekPolynomial Unary(List<string> tokens, ref int at, ref string letter)
    {
        if (at < tokens.Count && tokens[at] == "-") { at++; return -Unary(tokens, ref at, ref letter); }
        if (at < tokens.Count && tokens[at] == "+") { at++; return Unary(tokens, ref at, ref letter); }
        return Power(tokens, ref at, ref letter);
    }

    static LambekPolynomial Power(List<string> tokens, ref int at, ref string letter)
    {
        LambekPolynomial value = Postfix(tokens, ref at, ref letter);
        if (at < tokens.Count && tokens[at] == "^")
        {
            at++;
            LambekPolynomial exponent = Unary(tokens, ref at, ref letter);
            if (exponent.Degree > 0 || !exponent.At(0).IsInteger || BigInteger.Abs(exponent.At(0).Numerator) > 4096) throw new FormatException("The exponent must be a whole number.");
            int n = (int)exponent.At(0).Numerator;
            if (value.Degree > 0)
            {
                if (n < 0) throw new FormatException("A negative power of " + letter + " is not a polynomial.");
                LambekPolynomial result = LambekPolynomial.Constant(LambekRational.One);
                for (int k = 0; k < n; k++) result = result * value;
                return result;
            }
            return LambekPolynomial.Constant(value.At(0).Power(n));
        }
        return value;
    }

    static LambekPolynomial Postfix(List<string> tokens, ref int at, ref string letter)
    {
        LambekPolynomial value = Atom(tokens, ref at, ref letter);
        while (at < tokens.Count && (tokens[at] == "%" || tokens[at] == "!"))
        {
            if (value.Degree > 0) throw new FormatException("'" + tokens[at] + "' needs a number.");
            LambekRational number = value.At(0);
            if (tokens[at] == "%") value = LambekPolynomial.Constant(number / new LambekRational(100, 1));
            else
            {
                if (!number.IsInteger || number.Sign < 0 || number.Numerator > 1000) throw new FormatException("A factorial needs a whole number from 0 to 1000.");
                BigInteger product = BigInteger.One;
                for (int k = 2; k <= (int)number.Numerator; k++) product *= k;
                value = LambekPolynomial.Constant(new LambekRational(product, 1));
            }
            at++;
        }
        return value;
    }

    static LambekPolynomial Atom(List<string> tokens, ref int at, ref string letter)
    {
        if (at >= tokens.Count) throw new FormatException("The expression ends too early.");
        string token = tokens[at++];
        if (token == "(")
        {
            LambekPolynomial inside = Sum(tokens, ref at, ref letter);
            if (at >= tokens.Count || tokens[at] != ")") throw new FormatException("A parenthesis is not closed.");
            at++;
            return inside;
        }
        if (token == "sqrt")
        {
            LambekPolynomial inside = Atom(tokens, ref at, ref letter);
            if (inside.Degree > 0) throw new FormatException("A square root needs a number.");
            if (inside.At(0).Sign < 0) throw new FormatException("A negative number has no real square root.");
            LambekRational root;
            if (!ExactRoot(inside.At(0), out root)) throw new FormatException("irrational:" + Radical(inside.At(0)));
            return LambekPolynomial.Constant(root);
        }
        if (char.IsDigit(token[0])) return LambekPolynomial.Constant(LambekRational.Parse(token));
        if (token.Length == 1 && char.IsLetter(token[0]))
        {
            if (letter != null && letter != token) throw new FormatException("Only one unknown at a time (" + letter + " and " + token + ").");
            letter = token;
            return LambekPolynomial.Variable();
        }
        throw new FormatException("Unexpected '" + token + "'.");
    }

    // Square roots of rationals: exact when both terms are squares
    public static bool ExactRoot(LambekRational value, out LambekRational root)
    {
        root = LambekRational.Zero;
        if (value.Sign < 0) return false;
        BigInteger a = IntegerRoot(value.Numerator), b = IntegerRoot(value.Denominator);
        if (a * a != value.Numerator || b * b != value.Denominator) return false;
        root = new LambekRational(a, b);
        return true;
    }

    static BigInteger IntegerRoot(BigInteger n)
    {
        if (n.Sign <= 0) return BigInteger.Zero;
        BigInteger x = (BigInteger)Math.Sqrt((double)n);
        while (x * x > n) x -= 1;
        while ((x + 1) * (x + 1) <= n) x += 1;
        return x;
    }

    // sqrt(a/b) written k*sqrt(m)/d with m free of squares
    public static string Radical(LambekRational value)
    {
        BigInteger inside = value.Numerator * value.Denominator;
        BigInteger outside = BigInteger.One;
        for (BigInteger f = 2; f * f <= inside && f < 100000; f += 1)
        {
            while (inside % (f * f) == 0) { inside /= f * f; outside *= f; }
        }
        LambekRational factor = new LambekRational(outside, value.Denominator);
        string coefficient = factor.Equals(LambekRational.One) ? "" : (factor.IsInteger ? factor.Exact() : "(" + factor.Exact() + ")");
        return coefficient + "√" + inside.ToString(CultureInfo.InvariantCulture);
    }

    // Roots: first the rational ones (p/q, p dividing the constant, q the leading coefficient), then degree 2 by its formula
    public static LambekMathResult Solve(LambekPolynomial polynomial, string letter)
    {
        polynomial.Trim();
        int degree = polynomial.Degree;
        if (degree == 0)
        {
            string note = polynomial.At(0).IsZero ? "always" : "never";
            return new LambekMathResult { Kind = "equation", Note = note };
        }
        // Integer coefficients: multiply by the lowest common denominator
        BigInteger lcm = BigInteger.One;
        foreach (LambekRational c in polynomial.Coefficients) lcm = lcm / BigInteger.GreatestCommonDivisor(lcm, c.Denominator) * c.Denominator;
        List<BigInteger> integers = polynomial.Coefficients.Select(c => c.Numerator * (lcm / c.Denominator)).ToList();

        List<string> roots = new List<string>();
        LambekPolynomial rest = polynomial;
        // x = 0 as long as the constant term is 0
        while (rest.Degree > 0 && rest.At(0).IsZero)
        {
            roots.Add("0");
            LambekPolynomial shifted = new LambekPolynomial();
            for (int k = 1; k < rest.Coefficients.Count; k++) shifted.Coefficients.Add(rest.Coefficients[k]);
            rest = shifted.Trim();
        }
        if (rest.Degree > 2)
        {
            foreach (LambekRational candidate in Candidates(rest))
            {
                while (rest.Degree > 0 && rest.Evaluate(candidate).IsZero)
                {
                    roots.Add(candidate.Exact());
                    rest = Deflate(rest, candidate);
                }
                if (rest.Degree <= 2) break;
            }
        }
        string remark = null;
        if (rest.Degree == 1) roots.Add((-rest.At(0) / rest.At(1)).Exact());
        else if (rest.Degree == 2)
        {
            LambekRational a = rest.At(2), b = rest.At(1), c = rest.At(0);
            LambekRational delta = b * b - new LambekRational(4, 1) * a * c;
            LambekRational root;
            if (delta.Sign < 0) remark = "complex";
            else if (ExactRoot(delta, out root))
            {
                LambekRational first = (-b - root) / (new LambekRational(2, 1) * a);
                LambekRational second = (-b + root) / (new LambekRational(2, 1) * a);
                roots.Add(first.Exact());
                if (!delta.IsZero) roots.Add(second.Exact());
            }
            else
            {
                LambekRational middle = -b / (new LambekRational(2, 1) * a);
                LambekRational spread = delta / (new LambekRational(4, 1) * a * a);
                roots.Add(middle.IsZero ? "±" + Radical(spread) : middle.Exact() + " ± " + Radical(spread));
                double d = Math.Sqrt(delta.ToDouble());
                double x1 = (-b.ToDouble() - d) / (2 * a.ToDouble()), x2 = (-b.ToDouble() + d) / (2 * a.ToDouble());
                remark = "≈ " + Math.Min(x1, x2).ToString("0.######", CultureInfo.InvariantCulture) + ", " + Math.Max(x1, x2).ToString("0.######", CultureInfo.InvariantCulture);
            }
        }
        else if (rest.Degree > 2)
        {
            // No rational root left: every real root isolated by Sturm's theorem, narrowed to 10^-12, said with "~"
            List<LambekRational[]> intervals = LambekPolynomials.RealRoots(rest, new LambekRational(1, BigInteger.Pow(10, 12)));
            foreach (LambekRational[] interval in intervals)
            {
                bool exactDecimal;
                roots.Add("~" + ((interval[0] + interval[1]) / new LambekRational(2, 1)).Decimal(10, out exactDecimal));
            }
            if (roots.Count == 0) remark = "complex";
        }
        // Sorted numerically, each once
        List<string> sorted = roots.Distinct().OrderBy(Number).ThenBy(r => r, StringComparer.Ordinal).ToList();
        return new LambekMathResult { Kind = "equation", Roots = sorted.ToArray(), Note = remark, Exact = letter };
    }

    static double Number(string root)
    {
        // A root with a radical comes last
        if (root.Contains("±")) return double.MaxValue;
        if (root.StartsWith("~", StringComparison.Ordinal)) return double.Parse(root.Substring(1), CultureInfo.InvariantCulture);
        string[] parts = root.Split('/');
        double value = double.Parse(parts[0], CultureInfo.InvariantCulture);
        return parts.Length > 1 ? value / double.Parse(parts[1], CultureInfo.InvariantCulture) : value;
    }

    // A polynomial as a number times its factors over the rationals: the rational roots (b x - a) with their
    // multiplicity, then what has no rational root left, written with integer coefficients
    public static string FactorPolynomial(LambekPolynomial polynomial, string letter)
    {
        LambekPolynomial p = polynomial.Trim();
        if (p.Degree < 1) return p.At(0).Exact();
        // Content: the rational that makes the coefficients coprime integers with a positive leading one
        BigInteger lcm = BigInteger.One;
        foreach (LambekRational c in p.Coefficients) lcm = lcm / BigInteger.GreatestCommonDivisor(lcm, c.Denominator) * c.Denominator;
        BigInteger gcd = BigInteger.Zero;
        foreach (LambekRational c in p.Coefficients) gcd = BigInteger.GreatestCommonDivisor(gcd, c.Numerator * (lcm / c.Denominator));
        LambekRational content = new LambekRational(gcd * p.At(p.Degree).Sign, lcm);
        LambekPolynomial rest = p.Divide(content);
        List<string> factors = new List<string>();
        int zeros = 0;
        while (rest.Degree > 0 && rest.At(0).IsZero)
        {
            zeros++;
            LambekPolynomial shifted = new LambekPolynomial();
            for (int k = 1; k < rest.Coefficients.Count; k++) shifted.Coefficients.Add(rest.Coefficients[k]);
            rest = shifted.Trim();
        }
        if (zeros > 0) factors.Add(letter + (zeros > 1 ? "^" + zeros : ""));
        foreach (LambekRational root in Candidates(rest).ToList())
        {
            int times = 0;
            while (rest.Degree > 0 && rest.Evaluate(root).IsZero) { rest = Deflate(rest, root); times++; }
            if (times == 0) continue;
            // (b x - a) with b > 0, the content adjusted so the product stays equal
            LambekAlgebraFactor(root, letter, times, factors);
            rest = rest.Divide(new LambekRational(root.Denominator, 1).Power(times));
        }
        if (rest.Degree > 0)
        {
            string inner = LambekPolynomials.Show(rest, letter);
            factors.Add("(" + inner + ")");
            content = content * rest.At(rest.Degree) / rest.At(rest.Degree);
        }
        else content = content * rest.At(0);
        string head = content.Equals(LambekRational.One) ? "" : (content.Equals(-LambekRational.One) ? "-" : (content.IsInteger ? content.Exact() : "(" + content.Exact() + ")"));
        return head + string.Join("", factors);
    }

    static void LambekAlgebraFactor(LambekRational root, string letter, int times, List<string> factors)
    {
        BigInteger a = root.Numerator, b = root.Denominator;
        string term = (b.IsOne ? "" : b.ToString(CultureInfo.InvariantCulture)) + letter;
        string text = a.IsZero ? letter : "(" + term + (a.Sign > 0 ? " - " + a.ToString(CultureInfo.InvariantCulture) : " + " + BigInteger.Abs(a).ToString(CultureInfo.InvariantCulture)) + ")";
        factors.Add(text + (times > 1 ? "^" + times : ""));
    }

    static IEnumerable<LambekRational> Candidates(LambekPolynomial p)
    {
        BigInteger lcm = BigInteger.One;
        foreach (LambekRational c in p.Coefficients) lcm = lcm / BigInteger.GreatestCommonDivisor(lcm, c.Denominator) * c.Denominator;
        BigInteger constant = BigInteger.Abs(p.At(0).Numerator * (lcm / p.At(0).Denominator));
        BigInteger leading = BigInteger.Abs(p.At(p.Degree).Numerator * (lcm / p.At(p.Degree).Denominator));
        List<LambekRational> found = new List<LambekRational>();
        foreach (BigInteger a in Divisors(constant))
            foreach (BigInteger b in Divisors(leading))
            {
                found.Add(new LambekRational(a, b));
                found.Add(new LambekRational(-a, b));
            }
        return found.Distinct().OrderBy(r => r);
    }

    static IEnumerable<BigInteger> Divisors(BigInteger n)
    {
        List<BigInteger> list = new List<BigInteger>();
        if (n.IsZero) return list;
        for (BigInteger d = 1; d * d <= n && d < 1000000; d += 1)
        {
            if (n % d != 0) continue;
            list.Add(d);
            if (d * d != n) list.Add(n / d);
        }
        return list;
    }

    static LambekPolynomial Deflate(LambekPolynomial p, LambekRational root)
    {
        // Synthetic division by (x - root)
        int n = p.Degree;
        LambekPolynomial q = new LambekPolynomial();
        LambekRational[] c = new LambekRational[n];
        LambekRational carry = LambekRational.Zero;
        for (int k = n; k >= 1; k--)
        {
            carry = p.At(k) + carry * root;
            c[k - 1] = carry;
        }
        q.Coefficients.AddRange(c);
        return q.Trim();
    }

    // Units: each one a factor to its base unit and its dimension; temperatures add an offset
    static readonly Dictionary<string, Tuple<string, double, double>> units = new Dictionary<string, Tuple<string, double, double>>(StringComparer.Ordinal)
    {
        { "mm", Tuple.Create("length", 0.001, 0.0) }, { "cm", Tuple.Create("length", 0.01, 0.0) }, { "m", Tuple.Create("length", 1.0, 0.0) },
        { "km", Tuple.Create("length", 1000.0, 0.0) }, { "in", Tuple.Create("length", 0.0254, 0.0) }, { "ft", Tuple.Create("length", 0.3048, 0.0) },
        { "yd", Tuple.Create("length", 0.9144, 0.0) }, { "mi", Tuple.Create("length", 1609.344, 0.0) },
        { "mg", Tuple.Create("mass", 0.000001, 0.0) }, { "g", Tuple.Create("mass", 0.001, 0.0) }, { "kg", Tuple.Create("mass", 1.0, 0.0) },
        { "t", Tuple.Create("mass", 1000.0, 0.0) }, { "oz", Tuple.Create("mass", 0.028349523125, 0.0) }, { "lb", Tuple.Create("mass", 0.45359237, 0.0) },
        { "ms", Tuple.Create("time", 0.001, 0.0) }, { "s", Tuple.Create("time", 1.0, 0.0) }, { "min", Tuple.Create("time", 60.0, 0.0) },
        { "h", Tuple.Create("time", 3600.0, 0.0) }, { "d", Tuple.Create("time", 86400.0, 0.0) }, { "wk", Tuple.Create("time", 604800.0, 0.0) },
        { "ml", Tuple.Create("volume", 0.001, 0.0) }, { "cl", Tuple.Create("volume", 0.01, 0.0) }, { "l", Tuple.Create("volume", 1.0, 0.0) },
        { "gal", Tuple.Create("volume", 3.785411784, 0.0) },
        { "b", Tuple.Create("data", 1.0, 0.0) }, { "kb", Tuple.Create("data", 1024.0, 0.0) }, { "mb", Tuple.Create("data", 1048576.0, 0.0) },
        { "gb", Tuple.Create("data", 1073741824.0, 0.0) }, { "tb", Tuple.Create("data", 1099511627776.0, 0.0) },
        { "kmh", Tuple.Create("speed", 1 / 3.6, 0.0) }, { "ms1", Tuple.Create("speed", 1.0, 0.0) }, { "mph", Tuple.Create("speed", 0.44704, 0.0) },
        { "c", Tuple.Create("temperature", 1.0, 273.15) }, { "k", Tuple.Create("temperature", 1.0, 0.0) }, { "f", Tuple.Create("temperature", 5.0 / 9.0, 459.67 * 5.0 / 9.0) }
    };

    public static bool IsUnit(string unit) { return units.ContainsKey(unit); }
    public static string Dimension(string unit) { return units.ContainsKey(unit) ? units[unit].Item1 : null; }

    // Convert: to the base unit (factor, offset), then back; only between the same dimensions
    public static double Convert(double amount, string from, string to)
    {
        Tuple<string, double, double> a, b;
        if (!units.TryGetValue(from, out a) || !units.TryGetValue(to, out b)) throw new FormatException("Unknown unit.");
        if (a.Item1 != b.Item1) throw new FormatException("A " + a.Item1 + " cannot become a " + b.Item1 + ".");
        double baseValue = amount * a.Item2 + a.Item3;
        return (baseValue - b.Item3) / b.Item2;
    }

    // Days between two dates, and the day of the week (no time zone: dates only)
    public static int DaysBetween(DateTime first, DateTime second) { return (int)(second.Date - first.Date).TotalDays; }
}
