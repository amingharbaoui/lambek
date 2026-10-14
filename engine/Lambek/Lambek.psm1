#Requires -Version 7.4
Set-StrictMode -Version Latest

# Where Lambek keeps what it learns and logs: LAMBEK_DATA when set (tests, a portable copy), else the local app data
$dataFolder = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Lambek'
if ($env:LAMBEK_DATA) { $dataFolder = $env:LAMBEK_DATA }

# The hot loops (chart, logic, distances, memory) in C#.
# Built by build.ps1 -Task Build into bin, with the hash of the sources it was built from: loaded as it is when that hash is
# still the hash of the sources. Else compiled once here, then loaded from the data folder; that file name holds the hash of the
# sources and the PowerShell version, so a change compiles them again
if (-not ('LambekDictionary' -as [type])) {
    $sources = @(Get-ChildItem -Path "$PSScriptRoot/Native" -Filter '*.cs' | Sort-Object Name | ForEach-Object FullName)
    $text = ($sources | ForEach-Object { [IO.File]::ReadAllText($_) }) -join "`n"
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).Substring(0, 16)
    $built = Join-Path $PSScriptRoot 'bin/Lambek.Native.dll'
    $builtFrom = Join-Path $PSScriptRoot 'bin/Lambek.Native.sources'
    $assembly = Join-Path $dataFolder "native/Lambek-$hash-$($PSVersionTable.PSVersion).dll"
    if ((Test-Path -LiteralPath $built -PathType Leaf) -and (Test-Path -LiteralPath $builtFrom -PathType Leaf) -and
        [IO.File]::ReadAllText($builtFrom).Trim() -eq $hash) {
        $assembly = $built
    }
    elseif (-not (Test-Path -LiteralPath $assembly -PathType Leaf)) {
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
    # Read into memory, never opened from its file: a session that loaded Lambek never keeps the file locked, and
    # building it again ("./build.ps1" in the same window, or with the app running) can replace it. Loaded once a session
    if ($null -ne ('LambekRational' -as [type])) { Write-Verbose 'The compiled code is already loaded in this session.' }
    elseif (Test-Path -LiteralPath $assembly -PathType Leaf) { [void] [System.Reflection.Assembly]::Load([IO.File]::ReadAllBytes($assembly)) }
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
# The scoring file, read again only when it changes, and the languages Lambek has a file for
$script:ScoringCache = $null
$script:AvailableLanguages = $null
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
# The blackboard: every thing told, here or in the journal, once, with its status, source, day and key
$script:Board = $null
# What was told in every conversation: one line each, never changed afterwards
$script:ToldPath = Join-Path $dataFolder 'told.jsonl'
$script:ToldJournal = $null
$script:ToldDoubt = 0
# What the last answer of each conversation rested on, for "pourquoi ?"
$script:LastProofs = $null
# The words of condition ("si", "if") and of the questions read before the grammar ("combien", "pourquoi ?")
$script:ConditionWords = $null
$script:ToldQuestionWords = $null
# What was told of a problem in each conversation, and the words that make a message one
$script:ProblemStores = $null
$script:ProblemTrigger = $null
# The shapes of general rules in each language, the base forms of their words, and the sentences told read as them
$script:CategoryWords = $null
$script:CategoryLemmas = $null
$script:CategoryReadings = $null
# The question Lambek asked in each conversation when it could not conclude, waiting for its answer
$script:CategoryPending = $null
$script:KnowledgeRules = $null
# How each language sounds, the fusion of the satellites that choose how an answer is said, and the frame said last
# in each conversation
$script:Fluency = $null
$script:SpeechFusion = $null
$script:SpeechFrames = $null
$script:SpeechReadings = $null
$script:SpeechCapture = $null
# A woman, a man, a person or a thing, by noun (WordNet)
$script:NounKinds = $null
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
