// Whole numbers in words, both ways, in the seven languages of Lambek. Writing follows each language's rules
// (French 21 "vingt et un", 80 "quatre-vingts"; German and Dutch in one word below a million; Italian elisions
// "ventotto"; Spanish "veintiuno"; Portuguese "e" between the parts). Reading is built from writing: every number from
// 0 to 999 written out gives the table of words, and the scales (thousand, million...) multiply, so both always agree.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Numerics;
using System.Text;

public static class LambekNumberWords
{
    public static readonly string[] Languages = new[] { "en", "fr", "es", "de", "it", "nl", "pt" };

    public static string Write(BigInteger n, string language)
    {
        if (BigInteger.Abs(n) >= BigInteger.Pow(10, 15)) throw new FormatException("Only numbers below a million billions are written in words.");
        string minus = new Dictionary<string, string> { { "en", "minus" }, { "fr", "moins" }, { "es", "menos" }, { "de", "minus" }, { "it", "meno" }, { "nl", "min" }, { "pt", "menos" } }[language];
        if (n.Sign < 0) return minus + " " + Write(-n, language);
        switch (language)
        {
            case "en": return English(n);
            case "fr": return French(n);
            case "es": return Spanish(n);
            case "de": return German(n);
            case "it": return Italian(n);
            case "nl": return Dutch(n);
            case "pt": return Portuguese(n);
        }
        throw new FormatException("No number words for " + language + ".");
    }

    // Scales: thousand, million, billion (10^9), trillion (10^12)
    static readonly BigInteger[] Scales = new[] { BigInteger.Pow(10, 12), BigInteger.Pow(10, 9), BigInteger.Pow(10, 6), new BigInteger(1000) };

    // English
    static readonly string[] EnglishSmall = { "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen" };
    static readonly string[] EnglishTens = { "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety" };

    static string English(BigInteger n)
    {
        if (n.IsZero) return "zero";
        string[] names = { "trillion", "billion", "million", "thousand" };
        List<string> parts = new List<string>();
        for (int i = 0; i < Scales.Length; i++)
        {
            if (n >= Scales[i]) { parts.Add(EnglishHundreds((int)(n / Scales[i])) + " " + names[i]); n %= Scales[i]; }
        }
        if (n > 0) parts.Add(EnglishHundreds((int)n));
        return string.Join(" ", parts);
    }

    static string EnglishHundreds(int n)
    {
        List<string> parts = new List<string>();
        if (n >= 100) { parts.Add(EnglishSmall[n / 100] + " hundred"); n %= 100; }
        if (n >= 20) parts.Add(EnglishTens[n / 10] + (n % 10 > 0 ? "-" + EnglishSmall[n % 10] : ""));
        else if (n > 0) parts.Add(EnglishSmall[n]);
        return string.Join(" ", parts);
    }

    // French (traditional spelling: hyphens under a hundred, "et" in 21 to 71)
    static readonly string[] FrenchSmall = { "zéro", "un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix", "onze", "douze", "treize", "quatorze", "quinze", "seize", "dix-sept", "dix-huit", "dix-neuf" };
    static readonly string[] FrenchTens = { "", "", "vingt", "trente", "quarante", "cinquante", "soixante", "soixante", "quatre-vingt", "quatre-vingt" };

    static string French(BigInteger n)
    {
        if (n.IsZero) return "zéro";
        string[] one = { "billion", "milliard", "million", "mille" };
        string[] many = { "billions", "milliards", "millions", "mille" };
        List<string> parts = new List<string>();
        for (int i = 0; i < Scales.Length; i++)
        {
            if (n < Scales[i]) continue;
            int count = (int)(n / Scales[i]);
            n %= Scales[i];
            if (i == 3) parts.Add(count == 1 ? "mille" : FrenchHundreds(count, true) + " mille");
            else parts.Add(FrenchHundreds(count, true) + " " + (count == 1 ? one[i] : many[i]));
        }
        if (n > 0) parts.Add(FrenchHundreds((int)n, false));
        return string.Join(" ", parts);
    }

    static string FrenchHundreds(int n, bool beforeScale)
    {
        List<string> parts = new List<string>();
        int hundreds = n / 100, rest = n % 100;
        if (hundreds > 0)
        {
            // "deux cents" takes an s only at the end of the number
            string word = hundreds == 1 ? "cent" : FrenchSmall[hundreds] + " cent" + (rest == 0 && !beforeScale ? "s" : "");
            parts.Add(word);
        }
        if (rest > 0) parts.Add(FrenchTwoDigits(rest, beforeScale));
        return string.Join(" ", parts);
    }

    static string FrenchTwoDigits(int n, bool beforeScale)
    {
        if (n < 20) return FrenchSmall[n];
        int tens = n / 10, units = n % 10;
        if (tens == 7 || tens == 9)
        {
            // 70-79 and 90-99 count on from 60 and 80: "soixante et onze", "quatre-vingt-onze"
            int teen = 10 + units;
            if (tens == 7 && units == 1) return "soixante et onze";
            return FrenchTens[tens] + "-" + FrenchSmall[teen];
        }
        if (units == 0) return tens == 8 ? (beforeScale ? "quatre-vingt" : "quatre-vingts") : FrenchTens[tens];
        if (units == 1 && tens != 8) return FrenchTens[tens] + " et un";
        return FrenchTens[tens] + "-" + FrenchSmall[units];
    }

    // Spanish
    static readonly string[] SpanishSmall = { "cero", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce", "trece", "catorce", "quince", "dieciséis", "diecisiete", "dieciocho", "diecinueve", "veinte", "veintiuno", "veintidós", "veintitrés", "veinticuatro", "veinticinco", "veintiséis", "veintisiete", "veintiocho", "veintinueve" };
    static readonly string[] SpanishTens = { "", "", "veinte", "treinta", "cuarenta", "cincuenta", "sesenta", "setenta", "ochenta", "noventa" };
    static readonly string[] SpanishHundreds = { "", "ciento", "doscientos", "trescientos", "cuatrocientos", "quinientos", "seiscientos", "setecientos", "ochocientos", "novecientos" };

    static string Spanish(BigInteger n)
    {
        if (n.IsZero) return "cero";
        List<string> parts = new List<string>();
        // Long scale: a billón is 10^12, a thousand millions is "mil millones"
        BigInteger billion = BigInteger.Pow(10, 12), million = BigInteger.Pow(10, 6);
        if (n >= billion) { int c = (int)(n / billion); parts.Add(c == 1 ? "un billón" : SpanishApocope(SpanishBelowMillion(c)) + " billones"); n %= billion; }
        if (n >= million) { int c = (int)(n / million); parts.Add(c == 1 ? "un millón" : SpanishApocope(SpanishBelowMillion(c)) + " millones"); n %= million; }
        if (n > 0) parts.Add(SpanishBelowMillion((int)n));
        return string.Join(" ", parts);
    }

    static string SpanishApocope(string text)
    {
        // "uno" before a noun is "un", "veintiuno" is "veintiún"
        if (text.EndsWith("veintiuno", StringComparison.Ordinal)) return text.Substring(0, text.Length - 9) + "veintiún";
        if (text.EndsWith("uno", StringComparison.Ordinal)) return text.Substring(0, text.Length - 1);
        return text;
    }

    static string SpanishBelowMillion(int n)
    {
        List<string> parts = new List<string>();
        if (n >= 1000) { int c = n / 1000; parts.Add(c == 1 ? "mil" : SpanishApocope(SpanishHundredsWord(c)) + " mil"); n %= 1000; }
        if (n > 0) parts.Add(SpanishHundredsWord(n));
        return string.Join(" ", parts);
    }

    static string SpanishHundredsWord(int n)
    {
        if (n == 100) return "cien";
        List<string> parts = new List<string>();
        if (n >= 100) { parts.Add(SpanishHundreds[n / 100]); n %= 100; }
        if (n >= 30) parts.Add(SpanishTens[n / 10] + (n % 10 > 0 ? " y " + SpanishSmall[n % 10] : ""));
        else if (n > 0) parts.Add(SpanishSmall[n]);
        return string.Join(" ", parts);
    }

    // German: one word below a million ("dreihundertvierundzwanzig")
    static readonly string[] GermanSmall = { "null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf", "dreizehn", "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn" };
    static readonly string[] GermanTens = { "", "", "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig", "achtzig", "neunzig" };

    static string German(BigInteger n)
    {
        if (n.IsZero) return "null";
        string[] one = { "eine Billion", "eine Milliarde", "eine Million" };
        string[] many = { "Billionen", "Milliarden", "Millionen" };
        List<string> parts = new List<string>();
        for (int i = 0; i < 3; i++)
        {
            if (n < Scales[i]) continue;
            int c = (int)(n / Scales[i]);
            n %= Scales[i];
            parts.Add(c == 1 ? one[i] : GermanBelowMillion(c, true) + " " + many[i]);
        }
        if (n > 0) parts.Add(GermanBelowMillion((int)n, false));
        return string.Join(" ", parts);
    }

    static string GermanBelowMillion(int n, bool attributive)
    {
        StringBuilder b = new StringBuilder();
        if (n >= 1000) { int c = n / 1000; b.Append(c == 1 ? "eintausend" : GermanHundreds(c, true) + "tausend"); n %= 1000; }
        if (n > 0) b.Append(GermanHundreds(n, attributive));
        return b.ToString();
    }

    static string GermanHundreds(int n, bool attributive)
    {
        StringBuilder b = new StringBuilder();
        if (n >= 100) { b.Append(n / 100 == 1 ? "einhundert" : GermanSmall[n / 100] + "hundert"); n %= 100; }
        if (n == 0) return b.ToString();
        if (n == 1) { b.Append(attributive ? "ein" : "eins"); return b.ToString(); }
        if (n < 20) { b.Append(GermanSmall[n]); return b.ToString(); }
        int units = n % 10;
        if (units > 0) b.Append(units == 1 ? "ein" : GermanSmall[units]).Append("und");
        b.Append(GermanTens[n / 10]);
        return b.ToString();
    }

    // Italian: one word below a million, the vowel of the tens dropped before "uno" and "otto", "tré" at the end
    static readonly string[] ItalianSmall = { "zero", "uno", "due", "tre", "quattro", "cinque", "sei", "sette", "otto", "nove", "dieci", "undici", "dodici", "tredici", "quattordici", "quindici", "sedici", "diciassette", "diciotto", "diciannove" };
    static readonly string[] ItalianTens = { "", "", "venti", "trenta", "quaranta", "cinquanta", "sessanta", "settanta", "ottanta", "novanta" };

    static string Italian(BigInteger n)
    {
        if (n.IsZero) return "zero";
        string[] one = { "un bilione", "un miliardo", "un milione" };
        string[] many = { "bilioni", "miliardi", "milioni" };
        List<string> parts = new List<string>();
        for (int i = 0; i < 3; i++)
        {
            if (n < Scales[i]) continue;
            int c = (int)(n / Scales[i]);
            n %= Scales[i];
            parts.Add(c == 1 ? one[i] : ItalianBelowMillion(c) + " " + many[i]);
        }
        if (n > 0) parts.Add(ItalianBelowMillion((int)n));
        return string.Join(" ", parts);
    }

    static string ItalianBelowMillion(int n)
    {
        StringBuilder b = new StringBuilder();
        if (n >= 1000) { int c = n / 1000; b.Append(c == 1 ? "mille" : ItalianHundreds(c) + "mila"); n %= 1000; }
        if (n > 0) b.Append(ItalianHundreds(n));
        string text = b.ToString();
        if (text.EndsWith("tre", StringComparison.Ordinal) && text.Length > 3) text = text.Substring(0, text.Length - 3) + "tré";
        return text;
    }

    static string ItalianHundreds(int n)
    {
        StringBuilder b = new StringBuilder();
        if (n >= 100) { b.Append(n / 100 == 1 ? "cento" : ItalianSmall[n / 100] + "cento"); n %= 100; }
        if (n == 0) return b.ToString();
        if (n < 20) { b.Append(ItalianSmall[n]); return b.ToString(); }
        string tens = ItalianTens[n / 10];
        int units = n % 10;
        if (units == 1 || units == 8) tens = tens.Substring(0, tens.Length - 1);
        b.Append(tens);
        if (units > 0) b.Append(ItalianSmall[units]);
        return b.ToString();
    }

    // Dutch: one word below a million, units before tens with "en" ("ën" after an e: "tweeëntwintig")
    static readonly string[] DutchSmall = { "nul", "een", "twee", "drie", "vier", "vijf", "zes", "zeven", "acht", "negen", "tien", "elf", "twaalf", "dertien", "veertien", "vijftien", "zestien", "zeventien", "achttien", "negentien" };
    static readonly string[] DutchTens = { "", "", "twintig", "dertig", "veertig", "vijftig", "zestig", "zeventig", "tachtig", "negentig" };

    static string Dutch(BigInteger n)
    {
        if (n.IsZero) return "nul";
        string[] names = { "biljoen", "miljard", "miljoen" };
        List<string> parts = new List<string>();
        for (int i = 0; i < 3; i++)
        {
            if (n < Scales[i]) continue;
            int c = (int)(n / Scales[i]);
            n %= Scales[i];
            parts.Add(DutchBelowMillion(c) + " " + names[i]);
        }
        if (n > 0) parts.Add(DutchBelowMillion((int)n));
        return string.Join(" ", parts);
    }

    static string DutchBelowMillion(int n)
    {
        StringBuilder b = new StringBuilder();
        if (n >= 1000) { int c = n / 1000; b.Append(c == 1 ? "duizend" : DutchHundreds(c) + "duizend"); n %= 1000; }
        if (n > 0) b.Append(DutchHundreds(n));
        return b.ToString();
    }

    static string DutchHundreds(int n)
    {
        StringBuilder b = new StringBuilder();
        if (n >= 100) { b.Append(n / 100 == 1 ? "honderd" : DutchSmall[n / 100] + "honderd"); n %= 100; }
        if (n == 0) return b.ToString();
        if (n < 20) { b.Append(DutchSmall[n]); return b.ToString(); }
        int units = n % 10;
        if (units > 0)
        {
            string unit = DutchSmall[units];
            b.Append(unit).Append(unit.EndsWith("e", StringComparison.Ordinal) ? "ën" : "en");
        }
        b.Append(DutchTens[n / 10]);
        return b.ToString();
    }

    // Portuguese (European): "e" joins the hundreds, the tens and the units, and a thousand to a small rest
    static readonly string[] PortugueseSmall = { "zero", "um", "dois", "três", "quatro", "cinco", "seis", "sete", "oito", "nove", "dez", "onze", "doze", "treze", "catorze", "quinze", "dezasseis", "dezassete", "dezoito", "dezanove" };
    static readonly string[] PortugueseTens = { "", "", "vinte", "trinta", "quarenta", "cinquenta", "sessenta", "setenta", "oitenta", "noventa" };
    static readonly string[] PortugueseHundredWords = { "", "cento", "duzentos", "trezentos", "quatrocentos", "quinhentos", "seiscentos", "setecentos", "oitocentos", "novecentos" };

    static string Portuguese(BigInteger n)
    {
        if (n.IsZero) return "zero";
        BigInteger billion = BigInteger.Pow(10, 12), million = BigInteger.Pow(10, 6);
        List<string> parts = new List<string>();
        if (n >= billion) { int c = (int)(n / billion); parts.Add(c == 1 ? "um bilião" : PortugueseBelowMillion(c) + " biliões"); n %= billion; }
        if (n >= million) { int c = (int)(n / million); parts.Add(c == 1 ? "um milhão" : PortugueseBelowMillion(c) + " milhões"); n %= million; }
        if (n > 0) parts.Add((parts.Count > 0 && (n < 100 || n % 100 == 0) ? "e " : "") + PortugueseBelowMillion((int)n));
        return string.Join(" ", parts);
    }

    static string PortugueseBelowMillion(int n)
    {
        List<string> parts = new List<string>();
        if (n >= 1000) { int c = n / 1000; parts.Add(c == 1 ? "mil" : PortugueseHundreds(c) + " mil"); n %= 1000; }
        if (n > 0) parts.Add((parts.Count > 0 && (n < 100 || n % 100 == 0) ? "e " : "") + PortugueseHundreds(n));
        return string.Join(" ", parts);
    }

    static string PortugueseHundreds(int n)
    {
        if (n == 100) return "cem";
        List<string> parts = new List<string>();
        if (n >= 100) { parts.Add(PortugueseHundredWords[n / 100]); n %= 100; }
        if (n >= 20) { parts.Add(PortugueseTens[n / 10]); if (n % 10 > 0) parts.Add(PortugueseSmall[n % 10]); }
        else if (n > 0) parts.Add(PortugueseSmall[n]);
        return string.Join(" e ", parts);
    }

    // Reading: the words of 0 to 999 as the writer gives them (spaces and hyphens gone, no accents), and the scales
    static Dictionary<string, Dictionary<string, int>> tables = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
    static Dictionary<string, Dictionary<string, BigInteger>> scaleWords = new Dictionary<string, Dictionary<string, BigInteger>>(StringComparer.Ordinal);
    static object gate = new object();

    static string Plain(string text)
    {
        string decomposed = text.Normalize(NormalizationForm.FormD);
        StringBuilder b = new StringBuilder();
        foreach (char c in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
            b.Append(c == 'ß' ? "ss" : char.ToLowerInvariant(c).ToString());
        }
        return b.ToString();
    }

    static void Build(string language)
    {
        lock (gate)
        {
            if (tables.ContainsKey(language)) return;
            Dictionary<string, int> table = new Dictionary<string, int>(StringComparer.Ordinal);
            for (int k = 0; k < 1000; k++)
            {
                string key = Plain(Write(k, language)).Replace(" ", "").Replace("-", "");
                if (!table.ContainsKey(key)) table[key] = k;
            }
            // Common other spellings: "un" and "une", "ein", "uno", "una", "um", "uma", "cent" alone, "hundred" alone
            Dictionary<string, int> extra = new Dictionary<string, int>
            {
                { "une", 1 }, { "ein", 1 }, { "eine", 1 }, { "einen", 1 }, { "una", 1 }, { "un", 1 }, { "uma", 1 }, { "duas", 2 }, { "hundred", 100 }, { "hundert", 100 },
                { "a", 1 }, { "one", 1 }, { "veintiun", 21 }, { "dozen", 12 }, { "cents", 100 }, { "cientos", 100 }, { "ciento", 100 }, { "cento", 100 }
            };
            foreach (KeyValuePair<string, int> e in extra) if (!table.ContainsKey(e.Key)) table[e.Key] = e.Value;
            Dictionary<string, BigInteger> scales = new Dictionary<string, BigInteger>(StringComparer.Ordinal);
            foreach (string w in new[] { "thousand", "mille", "mil", "tausend", "mila", "duizend" }) scales[w] = 1000;
            foreach (string w in new[] { "million", "millions", "millon", "millones", "million", "millionen", "milione", "milioni", "miljoen", "miljoenen", "milhao", "milhoes" }) scales[w] = BigInteger.Pow(10, 6);
            foreach (string w in new[] { "milliard", "milliards", "milliarde", "milliarden", "miliardo", "miliardi", "miljard", "miljarden" }) scales[w] = BigInteger.Pow(10, 9);
            if (language == "en") { scales["billion"] = BigInteger.Pow(10, 9); scales["billions"] = BigInteger.Pow(10, 9); scales["trillion"] = BigInteger.Pow(10, 12); }
            else foreach (string w in new[] { "billion", "billions", "billon", "billones", "billion", "billionen", "bilione", "bilioni", "biljoen", "biliao", "bilioes" }) scales[w] = BigInteger.Pow(10, 12);
            tables[language] = table;
            scaleWords[language] = scales;
        }
    }

    // Numbers written in words inside a text become digits ("trois cent vingt et un" is 321); everything else stays
    public static string Digitize(string text, string language)
    {
        if (!Languages.Contains(language)) return text;
        Build(language);
        Dictionary<string, int> table = tables[language];
        Dictionary<string, BigInteger> scales = scaleWords[language];
        string[] minus = { "moins", "minus", "menos", "meno", "min" };
        List<string> tokens = System.Text.RegularExpressions.Regex.Split(text, @"(\s+)").ToList();
        StringBuilder output = new StringBuilder();
        int i = 0;
        while (i < tokens.Count)
        {
            string word = tokens[i];
            if (string.IsNullOrWhiteSpace(word)) { output.Append(word); i++; continue; }
            // The longest run of number words from here
            BigInteger total = 0, current = 0;
            int end = i, j = i;
            bool any = false;
            while (j < tokens.Count)
            {
                if (string.IsNullOrWhiteSpace(tokens[j])) { j++; continue; }
                string plain = Plain(tokens[j]).Trim('.', ',', '?', '!', ';', ':').Replace("-", "");
                // "et" and "y", "e", "und", "en", "and" only between two number words
                bool joiner = plain == "et" || plain == "y" || plain == "e" || plain == "und" || plain == "en" || plain == "and";
                int value;
                BigInteger scale;
                BigInteger compound = Compound(plain, table, language);
                if (table.TryGetValue(plain, out value) && !(plain == "a" && language != "en") && !(plain == "un" && language == "en"))
                {
                    // "a" alone is a word, not one: only before a scale or "hundred"
                    if (plain == "a" && !NextIsScale(tokens, j, scales)) break;
                    // "deux cent": a hundred multiplies what comes before it
                    if (value == 100 && current > 0 && current < 100) current *= 100;
                    else current += value;
                    any = true; end = j; j++;
                }
                else if (compound.Sign > 0)
                {
                    current += compound; any = true; end = j; j++;
                }
                else if (scales.TryGetValue(plain, out scale) && (any || plain == "mille" || plain == "mil" || plain == "tausend" || plain == "duizend" || plain == "hundred"))
                {
                    if (current.IsZero) current = 1;
                    total += current * scale; current = 0; any = true; end = j; j++;
                }
                else if (plain == "hundred" || plain == "hundert")
                {
                    if (current.IsZero) current = 1;
                    current *= 100; any = true; end = j; j++;
                }
                else if (joiner && any && j + 2 < tokens.Count && IsNumberWord(Plain(tokens[j + 2]).Trim('.', ',', '?', '!').Replace("-", ""), table, scales)) { j++; }
                else break;
            }
            if (!any) { output.Append(word); i++; continue; }
            // A lone "un", "une", "a" is an article, not a number
            string first = Plain(tokens[i]).Trim('.', ',', '?', '!');
            if (end == i && (first == "un" || first == "une" || first == "a" || first == "ein" || first == "eine" || first == "una" || first == "uno" || first == "um" || first == "uma" || first == "een"))
            {
                output.Append(word); i++; continue;
            }
            BigInteger number = total + current;
            // A minus word right before
            string last = tokens[end];
            string trailing = System.Text.RegularExpressions.Regex.Match(last, @"[.,?!;:]+$").Value;
            output.Append(number.ToString(CultureInfo.InvariantCulture)).Append(trailing);
            i = end + 1;
        }
        return output.ToString();
    }

    // One word with a thousand inside ("zweitausenddreihundert", "duemilaventi", "tweeduizendvijf")
    static BigInteger Compound(string plain, Dictionary<string, int> table, string language)
    {
        foreach (string thousand in new[] { "tausend", "duizend", "mila", "mille" })
        {
            int at = plain.IndexOf(thousand, StringComparison.Ordinal);
            if (at < 0) continue;
            string left = plain.Substring(0, at), right = plain.Substring(at + thousand.Length);
            int high = 1, low = 0;
            if (left.Length > 0 && !table.TryGetValue(left, out high)) continue;
            if (right.Length > 0 && !table.TryGetValue(right, out low)) continue;
            if (left.Length == 0 && right.Length == 0) continue;
            return (BigInteger)high * 1000 + low;
        }
        return BigInteger.Zero;
    }

    static bool NextIsScale(List<string> tokens, int j, Dictionary<string, BigInteger> scales)
    {
        for (int k = j + 1; k < tokens.Count; k++)
        {
            if (string.IsNullOrWhiteSpace(tokens[k])) continue;
            string plain = Plain(tokens[k]);
            return scales.ContainsKey(plain) || plain == "hundred";
        }
        return false;
    }

    static bool IsNumberWord(string plain, Dictionary<string, int> table, Dictionary<string, BigInteger> scales)
    {
        return table.ContainsKey(plain) || scales.ContainsKey(plain);
    }
}
