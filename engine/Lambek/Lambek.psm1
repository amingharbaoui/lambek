#Requires -Version 7.4
Set-StrictMode -Version Latest

# Where Lambek keeps what it learns and logs: LAMBEK_DATA when set (tests, a portable copy), else the local app data
$dataFolder = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Lambek'
if ($env:LAMBEK_DATA) { $dataFolder = $env:LAMBEK_DATA }

# The hot loops (chart, logic, distances, memory) in C#: compiled once, then loaded from the data folder.
# The file name holds a hash of the sources and the PowerShell version, so a change compiles them again
if (-not ('LambekDictionary' -as [type])) {
    $sources = @(Get-ChildItem -Path "$PSScriptRoot/Native" -Filter '*.cs' | Sort-Object Name | ForEach-Object FullName)
    $text = ($sources | ForEach-Object { [IO.File]::ReadAllText($_) }) -join "`n"
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).Substring(0, 16)
    $assembly = Join-Path $dataFolder "native/Lambek-$hash-$($PSVersionTable.PSVersion).dll"
    if (-not (Test-Path -LiteralPath $assembly -PathType Leaf)) {
        try {
            New-Item -ItemType Directory -Path (Split-Path -Path $assembly -Parent) -Force | Out-Null
            # Written under another name first, so two sessions starting together never load half a file
            $temporary = $assembly -replace '\.dll$', ".$PID.dll"
            Add-Type -Path $sources -OutputAssembly $temporary
            Move-Item -LiteralPath $temporary -Destination $assembly -Force
        }
        catch {
            Write-Verbose "The compiled code could not be kept: $($_.Exception.Message)"
        }
    }
    if (Test-Path -LiteralPath $assembly -PathType Leaf) { Add-Type -Path $assembly }
    else { Add-Type -Path $sources }
}

# Load functions
$privateFiles = @(Get-ChildItem -Path "$PSScriptRoot/Private" -Filter '*.ps1')
$publicFiles = @(Get-ChildItem -Path "$PSScriptRoot/Public" -Filter '*.ps1')

# A file left over from an older version (a copy over the folder keeps removed files) would replace a function
$defined = @{}
foreach ($file in $privateFiles + $publicFiles) {
    foreach ($found in [regex]::Matches([IO.File]::ReadAllText($file.FullName), '(?m)^function\s+([\w-]+)')) {
        $name = $found.Groups[1].Value
        if ($defined.ContainsKey($name)) {
            throw "$name is in both $($defined[$name]) and $($file.Name): one of them is left from an older version of Lambek. Remove it."
        }
        $defined[$name] = $file.Name
    }
}

foreach ($file in $privateFiles + $publicFiles) {
    . $file.FullName
}

# Module state
$script:Packs = [ordered]@{}
$script:LexiconCache = @{}
$script:ActionIndexCache = @{}
$script:DomainSenseCache = @{}
$script:RoundTripCache = @{}
$script:GreetingPattern = $null
# The phrasings said lately, so the same question does not get the same words twice in a row
$script:SpeechRecent = @{}
$script:SpeechTurn = 0
$script:AuditPath = Join-Path $dataFolder 'audit.jsonl'
$script:HostState = @{ Plans = [ordered]@{}; Simulations = @{}; Approvals = @{} }
$script:ProgressHandler = $null
$script:HostRequestId = $null
$script:HostWriter = $null
$script:LanguageHint = $null
$script:GuardWords = $null
# The language each chat is in, as a belief over the languages (a filter over the turns)
$script:LanguageBelief = $null
$script:Incognito = $false
$script:Told = $null
# What was told in every conversation: one line each, never changed afterwards
$script:ToldPath = Join-Path $dataFolder 'told.jsonl'
$script:ToldJournal = $null
$script:ToldDoubt = 0
$script:KnowledgeRules = $null
$script:Now = $null
$script:KeyNeighbors = $null
# Read from the machine once, and the folder names they give
$script:SystemVocabulary = $null
$script:KnownFolderCache = $null
$script:KnownExtensions = $null
$script:EntityRules = $null
$script:NumberWords = $null

$script:TextExtensions = @('txt', 'md', 'csv', 'tsv', 'log', 'json', 'xml', 'yml', 'yaml', 'ini', 'cfg', 'conf', 'toml', 'ps1', 'psm1', 'psd1', 'js', 'jsx', 'ts', 'tsx', 'py', 'cs', 'rs', 'java', 'html', 'css', 'sql', 'sh', 'bat', 'cmd')

# MCP client: modern protocol first, legacy handshake as a fallback
$script:Mcp = @{
    Servers    = [ordered]@{}
    ConfigPath = Join-Path $dataFolder 'mcp.json'
    CachePath  = Join-Path $dataFolder 'mcp-tools.json'
}
# Words taught by the user
$script:LearnedPath = Join-Path $dataFolder 'words.json'
$script:LearnedWords = $null
# Turns of phrase learned from the user's rephrasings
$script:FormsPath = Join-Path $dataFolder 'forms.json'
$script:Forms = $null

# What happened to past plans: the adaptation learns from it
$script:HistoryPath = Join-Path $dataFolder 'history.jsonl'
$script:History = $null

# What Lambek knows and the rules it follows
$script:RulesPath = Join-Path $dataFolder 'rules.dl'
$script:Knowledge = $null

# Deleted files wait here, in their own folder structure, before they are gone for good
$script:TrashPath = Join-Path $dataFolder 'trash'
$script:TrashDays = 30

# The requests the user confirmed, found again by meaning, and the words learned from them
$script:MemoryPath = Join-Path $dataFolder 'memory.jsonl'
$script:Memory = $null
$script:PursuitPath = Join-Path $dataFolder 'pursuit.json'
$script:Pursuit = $null

# The free dictionaries (WordNet, WOLF, Lefff), loaded on first need
$script:DictionaryPath = Join-Path $PSScriptRoot 'Data/Dictionaries'
if ($env:LAMBEK_DICTIONARIES) { $script:DictionaryPath = $env:LAMBEK_DICTIONARIES }

# The GPS fusion of the scorers (fitted on the benchmark), and the drift of each scorer learned from the user's runs
$script:Fusion = $null
$script:DriftPath = Join-Path $dataFolder 'drift.json'
# What the current conversation believes the user wants (set by the host for each chat)
$script:Belief = $null

$script:McpVersion = '2026-07-28'
$script:McpLegacyVersion = '2025-11-25'
$manifest = Import-PowerShellDataFile -LiteralPath "$PSScriptRoot/Lambek.psd1"
$script:McpClientInfo = [ordered]@{ name = 'Lambek'; version = $manifest.ModuleVersion }

# Exports
Export-ModuleMember -Function $publicFiles.BaseName
