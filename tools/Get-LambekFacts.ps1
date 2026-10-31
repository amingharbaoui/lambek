#Requires -Version 7.6
<#
.SYNOPSIS
    Reads in Wikidata what Lambek knows of the world: countries, cities, people, books, films, paintings, albums,
    video games, rivers, mountains, oceans and planets, with their names in French and English and the facts of
    tools/facts.json, into
    engine/Lambek/Data/Knowledge/wikidata.facts.gz.
.DESCRIPTION
    Every kind of tools/facts.json is asked to the SPARQL endpoint written there (QLever, which answers large questions
    on all of Wikidata): the things of that kind, their labels, other names and descriptions in French and English, and
    the values of each property with their rank. Only the values Wikidata prefers are kept (a deprecated value never);
    a date keeps its precision, so that a year is never said as a day; a population keeps the year it was counted; a
    measure (a length, a height, an area) is kept in the unit the manifest gives, converted from the units it lists.
    The things the facts point at (a language, a currency, a place of birth, an author) are written too, with their
    names. The file is plain text (gzip), one line a thing: K the kinds of a thing and how many Wikipedias have a page
    on it, L a label, A another name, D a description, F a fact. Its first line names the endpoint and the day.
    Wikidata is CC0.
.EXAMPLE
    ./tools/Get-LambekFacts.ps1
#>
param(
    [string] $OutFile = (Join-Path $PSScriptRoot '../engine/Lambek/Data/Knowledge/wikidata.facts.gz'),

    # The answers of the endpoint are kept here, so that a question asked again is not asked twice
    [string] $Cache = (Join-Path $PSScriptRoot '../../lambek-corpus/wikidata')
)

$ErrorActionPreference = 'Stop'
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'facts.json') -Raw -Encoding utf8 | ConvertFrom-Json
$cacheFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Cache)
New-Item -ItemType Directory -Path $cacheFolder -Force | Out-Null
$version = (Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '../engine/Lambek/Lambek.psd1')).ModuleVersion

$prefixes = @(
    'PREFIX wd: <http://www.wikidata.org/entity/>'
    'PREFIX wdt: <http://www.wikidata.org/prop/direct/>'
    'PREFIX p: <http://www.wikidata.org/prop/>'
    'PREFIX ps: <http://www.wikidata.org/prop/statement/>'
    'PREFIX psv: <http://www.wikidata.org/prop/statement/value/>'
    'PREFIX pq: <http://www.wikidata.org/prop/qualifier/>'
    'PREFIX wikibase: <http://wikiba.se/ontology#>'
    'PREFIX schema: <http://schema.org/>'
    'PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>'
    'PREFIX skos: <http://www.w3.org/2004/02/skos/core#>'
) -join "`n"

# One question to the endpoint, its answer kept in the cache (the file is returned); asked again after a wait when the
# endpoint is busy
function Invoke-LambekSparql {
    param([string] $Query)
    $text = "$prefixes`n$Query"
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).Substring(0, 24).ToLowerInvariant()
    $file = Join-Path $cacheFolder "$hash.json"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        # (a busy endpoint answers 429 at once: asked again a little later, many times if need be)
        for ($try = 1; ; $try++) {
            try {
                Invoke-WebRequest -Uri $manifest.Endpoint -Method Post -Body @{ query = $text } -OutFile $file -UseBasicParsing -TimeoutSec 900 `
                    -Headers @{ Accept = 'application/sparql-results+json'; 'User-Agent' = "Lambek/$version (tools/Get-LambekFacts.ps1)" } | Out-Null
                break
            }
            catch {
                if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
                if ($try -ge 60) { throw }
                Write-Host "  the endpoint is busy ($($_.Exception.Message)), asking again"
                Start-Sleep -Seconds (5 + 5 * [math]::Min(6, $try))
            }
        }
        Start-Sleep -Seconds 3
    }
    return $file
}

# What is kept of the answers, built in C#: hundreds of thousands of rows are read in seconds. Every value is read as
# the text it is: a date stays "1802-02-26T00:00:00Z" (read as a date, it would be one of this machine's time zone, a
# day earlier west of Greenwich)
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.Json;

public sealed class LambekWorldThing
{
    public string Id;
    public SortedSet<string> Kinds = new SortedSet<string>(StringComparer.Ordinal);
    public int Links;
    public List<KeyValuePair<string, string>> Labels = new List<KeyValuePair<string, string>>();
    public List<string> Aliases = new List<string>();
    public List<KeyValuePair<string, string>> Descriptions = new List<KeyValuePair<string, string>>();
    public List<string> Facts = new List<string>();
}

public sealed class LambekWorld
{
    readonly Dictionary<string, LambekWorldThing> things = new Dictionary<string, LambekWorldThing>(StringComparer.Ordinal);
    readonly HashSet<string> languages;

    public LambekWorld(string[] languages) { this.languages = new HashSet<string>(languages, StringComparer.Ordinal); }

    public int Count { get { return things.Count; } }

    // The rows of an answer: each column by its name, as text ("@lang" after a name gives its language)
    static IEnumerable<Dictionary<string, string>> Rows(string path)
    {
        using (JsonDocument document = JsonDocument.Parse(File.ReadAllBytes(path)))
        {
            foreach (JsonElement binding in document.RootElement.GetProperty("results").GetProperty("bindings").EnumerateArray())
            {
                Dictionary<string, string> row = new Dictionary<string, string>(StringComparer.Ordinal);
                foreach (JsonProperty cell in binding.EnumerateObject())
                {
                    row[cell.Name] = cell.Value.GetProperty("value").GetString();
                    JsonElement language;
                    if (cell.Value.TryGetProperty("xml:lang", out language)) { row[cell.Name + "@lang"] = language.GetString(); }
                }
                yield return row;
            }
        }
    }

    // Q142 for http://www.wikidata.org/entity/Q142
    static string Item(string uri)
    {
        const string prefix = "http://www.wikidata.org/entity/Q";
        if (uri == null || !uri.StartsWith(prefix, StringComparison.Ordinal)) { return null; }
        string number = uri.Substring(prefix.Length);
        foreach (char c in number) { if (c < '0' || c > '9') { return null; } }
        return number.Length > 0 ? "Q" + number : null;
    }

    LambekWorldThing Thing(string id)
    {
        LambekWorldThing thing;
        if (!things.TryGetValue(id, out thing)) { thing = new LambekWorldThing { Id = id }; things[id] = thing; }
        return thing;
    }

    static string Get(Dictionary<string, string> row, string name)
    {
        string value;
        return row.TryGetValue(name, out value) ? value : null;
    }

    // The things of a kind, and how many Wikipedias have a page on each
    public int Members(string path, string kind)
    {
        int count = 0;
        foreach (Dictionary<string, string> row in Rows(path))
        {
            string id = Item(Get(row, "e"));
            if (id == null) { continue; }
            LambekWorldThing thing = Thing(id);
            thing.Kinds.Add(kind);
            int links;
            if (int.TryParse(Get(row, "links"), NumberStyles.Integer, CultureInfo.InvariantCulture, out links) && links > thing.Links) { thing.Links = links; }
            count++;
        }
        return count;
    }

    // Labels, other names and descriptions: the thing in column "thing", what in "what" (or always a label)
    public void Names(string path, string column)
    {
        foreach (Dictionary<string, string> row in Rows(path))
        {
            string id = Item(Get(row, column));
            string language = Get(row, "name@lang");
            string name = Get(row, "name");
            if (id == null || language == null || name == null || !languages.Contains(language)) { continue; }
            name = name.Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ').Trim();
            if (name.Length == 0) { continue; }
            LambekWorldThing thing = Thing(id);
            string what = Get(row, "what") ?? "http://www.w3.org/2000/01/rdf-schema#label";
            if (what.EndsWith("#label", StringComparison.Ordinal))
            {
                if (!thing.Labels.Any(p => p.Key == language)) { thing.Labels.Add(new KeyValuePair<string, string>(language, name)); }
            }
            else if (what.EndsWith("#altLabel", StringComparison.Ordinal))
            {
                string line = language + "\t" + name;
                if (!thing.Aliases.Contains(line)) { thing.Aliases.Add(line); }
            }
            else if (what.EndsWith("/description", StringComparison.Ordinal))
            {
                if (!thing.Descriptions.Any(p => p.Key == language)) { thing.Descriptions.Add(new KeyValuePair<string, string>(language, name)); }
            }
        }
    }

    sealed class Value { public string Text; public string Extra; public int Rank; }

    // The facts of an answer of one shape (item, time, quantity): only the values of the best rank, then the one the
    // property keeps (keep: "latest" the latest count, "earliest" the first release). Counted by property
    public Dictionary<string, int> Facts(string path, string shape, Dictionary<string, string> keep)
    {
        return Facts(path, shape, keep, new Dictionary<string, decimal>(StringComparer.Ordinal));
    }

    // (a measure is kept in the unit the manifest gives: units holds "property|unit" and what one of that unit is
    // worth in it; a measure in another unit is not kept)
    public Dictionary<string, int> Facts(string path, string shape, Dictionary<string, string> keep, Dictionary<string, decimal> units)
    {
        Dictionary<string, List<Value>> found = new Dictionary<string, List<Value>>(StringComparer.Ordinal);
        List<string> order = new List<string>();
        foreach (Dictionary<string, string> row in Rows(path))
        {
            string id = Item(Get(row, "e"));
            string rankText = Get(row, "rank") ?? "";
            int rank = rankText.EndsWith("#PreferredRank", StringComparison.Ordinal) ? 2 : rankText.EndsWith("#NormalRank", StringComparison.Ordinal) ? 1 : 0;
            string property = Get(row, "property");
            if (id == null || rank == 0 || property == null) { continue; }
            string text = Get(row, "v");
            string value = null;
            string extra = "";
            if (shape == "item") { value = Item(text); }
            else if (shape == "time")
            {
                // +1802-02-26T00:00:00Z: the year (negative before our era), the month and the day as far as the precision goes
                System.Text.RegularExpressions.Match m = System.Text.RegularExpressions.Regex.Match(text ?? "", @"^([+-]?\d+)-(\d\d)-(\d\d)");
                if (m.Success) { value = long.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture) + "-" + m.Groups[2].Value + "-" + m.Groups[3].Value; }
                extra = Get(row, "precision") ?? "";
            }
            else if (shape == "measure")
            {
                decimal number;
                decimal factor;
                string unit = Item(Get(row, "unit"));
                if (unit != null && units.TryGetValue(property + "|" + unit, out factor) && decimal.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out number))
                {
                    value = Math.Round(number * factor, 1).ToString(CultureInfo.InvariantCulture);
                }
            }
            else if (shape == "quantity")
            {
                decimal number;
                if (decimal.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out number)) { value = number.ToString(CultureInfo.InvariantCulture); }
                System.Text.RegularExpressions.Match m = System.Text.RegularExpressions.Regex.Match(Get(row, "time") ?? "", @"^([+-]?\d+)");
                if (m.Success) { extra = long.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture); }
            }
            if (value == null) { continue; }
            string key = id + "|" + property;
            List<Value> values;
            if (!found.TryGetValue(key, out values)) { values = new List<Value>(); found[key] = values; order.Add(key); }
            values.Add(new Value { Text = value, Extra = extra, Rank = rank });
        }
        Dictionary<string, int> counts = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (string key in order)
        {
            string[] parts = key.Split('|');
            string property = parts[1];
            int top = found[key].Max(v => v.Rank);
            List<Value> best = found[key].Where(v => v.Rank == top).ToList();
            string how;
            keep.TryGetValue(property, out how);
            if (how == "latest")
            {
                best = best.OrderByDescending(v => YearOf(v.Extra)).ThenBy(v => v.Text, StringComparer.Ordinal).Take(1).ToList();
            }
            else if (how == "earliest")
            {
                best = best.Where(v => !v.Text.StartsWith("-", StringComparison.Ordinal)).OrderBy(v => v.Text, StringComparer.Ordinal).Take(1).ToList();
            }
            LambekWorldThing thing = Thing(parts[0]);
            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (Value v in best)
            {
                if (!seen.Add(v.Text + "\t" + v.Extra)) { continue; }
                string line = property + "\t" + v.Text + "\t" + v.Extra;
                if (thing.Facts.Contains(line)) { continue; }
                thing.Facts.Add(line);
                int count;
                counts.TryGetValue(property, out count);
                counts[property] = count + 1;
            }
        }
        return counts;
    }

    static long YearOf(string extra)
    {
        long year;
        return long.TryParse(extra, NumberStyles.Integer, CultureInfo.InvariantCulture, out year) ? Math.Abs(year) : 0;
    }

    // Written in the order of the ids, the same on every machine; a thing with no name is left out
    public string Write(string path, string header)
    {
        int lines = 1;
        SortedDictionary<string, int> kinds = new SortedDictionary<string, int>(StringComparer.Ordinal);
        int written = 0;
        using (FileStream file = File.Create(path))
        using (GZipStream zip = new GZipStream(file, CompressionLevel.SmallestSize))
        using (StreamWriter writer = new StreamWriter(zip, new UTF8Encoding(false)))
        {
            writer.NewLine = "\n";
            writer.WriteLine(header);
            foreach (LambekWorldThing thing in things.Values.OrderBy(t => long.Parse(t.Id.Substring(1), CultureInfo.InvariantCulture)))
            {
                if (thing.Labels.Count == 0) { continue; }
                written++;
                string kind = thing.Kinds.Count > 0 ? string.Join(",", thing.Kinds) : "value";
                foreach (string k in kind.Split(',')) { int n; kinds.TryGetValue(k, out n); kinds[k] = n + 1; }
                writer.WriteLine("K\t" + thing.Id + "\t" + kind + "\t" + thing.Links.ToString(CultureInfo.InvariantCulture)); lines++;
                foreach (KeyValuePair<string, string> label in thing.Labels) { writer.WriteLine("L\t" + thing.Id + "\t" + label.Key + "\t" + label.Value); lines++; }
                foreach (string alias in thing.Aliases) { writer.WriteLine("A\t" + thing.Id + "\t" + alias); lines++; }
                foreach (KeyValuePair<string, string> description in thing.Descriptions) { writer.WriteLine("D\t" + thing.Id + "\t" + description.Key + "\t" + description.Value); lines++; }
                foreach (string fact in thing.Facts) { writer.WriteLine("F\t" + thing.Id + "\t" + fact); lines++; }
            }
        }
        return written + " things (" + string.Join(", ", kinds.Select(p => p.Value + " " + p.Key)) + "), " + lines + " lines";
    }
}
'@

$filter = '(' + (@($manifest.Languages | ForEach-Object { "LANG(?name) = `"$_`"" }) -join ' || ') + ')'
$world = [LambekWorld]::new([string[]] @($manifest.Languages))
$keep = [System.Collections.Generic.Dictionary[string, string]]::new()
foreach ($property in $manifest.Properties.PSObject.Properties) { if ($property.Value.PSObject.Properties['Keep']) { $keep[$property.Name] = $property.Value.Keep } }
# A measure in the unit of the manifest: for each unit Wikidata may give, what it is worth in it ("km": 1 for a length
# in km, "mile": 1.609344)
$units = [System.Collections.Generic.Dictionary[string, decimal]]::new()
foreach ($property in $manifest.Properties.PSObject.Properties) {
    if (-not $property.Value.PSObject.Properties['Units']) { continue }
    foreach ($unit in $property.Value.Units.PSObject.Properties) { $units["$($property.Name)|$($unit.Name)"] = [decimal] $unit.Value }
}
# (a value kept only when it is itself what the manifest asks: an actor of a film only when known enough, Where)
function Get-LambekFactWhere {
    param([string] $Property)
    if ($manifest.Properties.$Property.PSObject.Properties['Where']) { return " $($manifest.Properties.$Property.Where)" }
    return ''
}
# (a fact that is true today only, Current: a statement with an end is left out, the United Kingdom is no longer a
# member of the European Union)
function Get-LambekFactNow {
    param([string] $Property)
    if ($manifest.Properties.$Property.PSObject.Properties['Current'] -and $manifest.Properties.$Property.Current) { return ' FILTER NOT EXISTS { ?st pq:P582 ?ended }' }
    return ''
}

foreach ($kind in @($manifest.Kinds)) {
    $members = "{ SELECT DISTINCT ?e ?links WHERE { $($kind.Pattern) } }"
    $count = $world.Members((Invoke-LambekSparql -Query "SELECT ?e ?links WHERE { $members }"), $kind.Kind)
    Write-Host ("{0,-10} {1,7:N0} things" -f $kind.Kind, $count)
    # Their labels, other names and descriptions, in one question
    $world.Names((Invoke-LambekSparql -Query "SELECT ?e ?what ?name WHERE { $members VALUES ?what { rdfs:label skos:altLabel schema:description } ?e ?what ?name . FILTER $filter }"), 'e')

    # The facts, one question for each shape of value: every property of the kind at once, with the rank of each value
    # (a property with a Where of its own, in a question of its own)
    foreach ($group in @($kind.Facts | Group-Object { "$($manifest.Properties.$_.Value)|$(Get-LambekFactWhere -Property $_)|$(Get-LambekFactNow -Property $_)" })) {
        $shape = "$($manifest.Properties.($group.Group[0]).Value)"
        $where = (Get-LambekFactWhere -Property $group.Group[0]) + (Get-LambekFactNow -Property $group.Group[0])
        $pairs = @($group.Group | ForEach-Object { "(`"$_`" p:$_ $(if ($shape -in 'time', 'measure') { 'psv' } else { 'ps' }):$_)" }) -join ' '
        $query = switch ($shape) {
            'time' { "SELECT ?e ?property ?v ?precision ?rank WHERE { $members VALUES (?property ?claim ?statement) { $pairs } ?e ?claim ?st . ?st ?statement ?node ; wikibase:rank ?rank . ?node wikibase:timeValue ?v ; wikibase:timePrecision ?precision . }" }
            'quantity' { "SELECT ?e ?property ?v ?time ?rank WHERE { $members VALUES (?property ?claim ?statement) { $pairs } ?e ?claim ?st . ?st ?statement ?v ; wikibase:rank ?rank . OPTIONAL { ?st pq:P585 ?time } }" }
            'measure' { "SELECT ?e ?property ?v ?unit ?rank WHERE { $members VALUES (?property ?claim ?statement) { $pairs } ?e ?claim ?st . ?st ?statement ?node ; wikibase:rank ?rank . ?node wikibase:quantityAmount ?v ; wikibase:quantityUnit ?unit . }" }
            default { "SELECT ?e ?property ?v ?rank WHERE { $members VALUES (?property ?claim ?statement) { $pairs } ?e ?claim ?st . ?st ?statement ?v ; wikibase:rank ?rank .$where }" }
        }
        $counts = $world.Facts((Invoke-LambekSparql -Query $query), $shape, $keep, $units)
        foreach ($property in @($group.Group)) {
            $count = 0
            if ($counts.ContainsKey($property)) { $count = $counts[$property] }
            Write-Host ("  {0,-6} {1,-24} {2,7:N0} facts" -f $property, $manifest.Properties.$property.Name, $count)
        }
    }

    # The names of the things these facts point at (a language, a place of birth, an author), a question for each
    # property: the values of the best rank are the direct ones (wdt:)
    foreach ($property in @($kind.Facts | Where-Object { $manifest.Properties.$_.Value -eq 'item' })) {
        $world.Names((Invoke-LambekSparql -Query "SELECT ?v ?name WHERE { { SELECT DISTINCT ?v WHERE { $members ?e wdt:$property ?v .$(Get-LambekFactWhere -Property $property) } } ?v rdfs:label ?name . FILTER $filter }"), 'v')
    }
}

$out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
New-Item -ItemType Directory -Path (Split-Path -Path $out -Parent) -Force | Out-Null
$day = [datetime]::UtcNow.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
$said = $world.Write($out, "# lambek-facts-1`tWikidata (CC0)`t$($manifest.Endpoint)`t$day")
Write-Host "Wrote $out ($([math]::Round((Get-Item -LiteralPath $out).Length / 1MB, 1)) MB): $said."
