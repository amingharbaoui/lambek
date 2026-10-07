function Format-LambekCodeCSharp {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Model
    )

    $need = Get-LambekCodeNeed -Model $Model
    $lines = [System.Collections.Generic.List[string]]::new()

    # Header comment and namespaces
    foreach ($line in Get-LambekCodeHeader -Model $Model -Switch '--apply' -Needs 'Needs .NET 8 or later, base class library only (dotnet new console, then replace Program.cs).') {
        $lines.Add(("// $line").TrimEnd())
    }
    $lines.Add('#nullable enable')
    $lines.Add('using System;')
    if ($need.Select) { $lines.Add('using System.Collections.Generic;') }
    if ($need.List) { $lines.Add('using System.Globalization;') }
    $lines.Add('using System.IO;')
    $lines.Add('')
    $lines.Add(@'
// A step that cannot go on
class StepException : Exception
{
    public StepException(string message) : base(message)
    {
    }
}
'@)

    # Finding and choosing the files
    if ($need.Select) {
        $lines.Add('')
        $lines.Add(@'
// One file that was found: its path, its size in bytes and its last change (UTC)
class FoundFile
{
    public string Path = "";
    public long Size;
    public DateTime Changed;
}

// The filters of one step: the ones left at null are not asked. Ages are in seconds, sizes in bytes
class Filter
{
    public bool Recurse { get; set; }
    public string? Name { get; set; }
    public string[]? Extensions { get; set; }
    public string[] ExceptExtensions { get; set; } = new string[0];
    public string? ExceptName { get; set; }
    public long? OlderThan { get; set; }
    public long? NewerThan { get; set; }
    public long? MinSize { get; set; }
    public long? MaxSize { get; set; }
    public string? Order { get; set; }
    public int? Count { get; set; }
    public long? FreeBytes { get; set; }
}
'@)
    }

    $lines.Add('')
    $lines.Add('class Program')
    $lines.Add('{')
    $lines.Add(@'
    static bool Exists(string path)
    {
        return File.Exists(path) || Directory.Exists(path);
    }
'@)

    if ($need.Select) {
        $lines.Add('')
        $lines.Add(@'
    static FoundFile Describe(string path, FileSystemInfo entry)
    {
        // A link that leads nowhere has no size to read
        FoundFile file = new FoundFile();
        file.Path = path;
        file.Changed = entry.LastWriteTimeUtc;
        try
        {
            file.Size = ((FileInfo)entry).Length;
        }
        catch (IOException)
        {
            file.Size = 0;
        }
        return file;
    }

    static List<FoundFile> FindFiles(string root, bool recurse)
    {
        // Every file below the root; a path to one file gives that file
        List<FoundFile> found = new List<FoundFile>();
        if (!Directory.Exists(root))
        {
            FileInfo single = new FileInfo(root);
            if (!single.Exists)
            {
                throw new StepException(root + " does not exist");
            }
            found.Add(Describe(root, single));
            return found;
        }
        Stack<string> folders = new Stack<string>();
        folders.Push(root);
        while (folders.Count > 0)
        {
            string folder = folders.Pop();
            foreach (FileSystemInfo entry in new DirectoryInfo(folder).EnumerateFileSystemInfos())
            {
                // Hidden: the attribute on Windows, a leading dot on the other systems (.NET sets the attribute for both)
                if ((entry.Attributes & FileAttributes.Hidden) != 0)
                {
                    continue;
                }
                string path = Path.Combine(folder, entry.Name);
                if (entry is DirectoryInfo)
                {
                    // A link to a folder is not followed
                    if (recurse && entry.LinkTarget == null)
                    {
                        folders.Push(path);
                    }
                    continue;
                }
                found.Add(Describe(path, entry));
            }
        }
        return found;
    }

    static string ExtensionOf(string name)
    {
        // ".txt" for "Notes.TXT", "" for a name without a dot
        int dot = name.LastIndexOf('.');
        if (dot < 0)
        {
            return "";
        }
        return name.Substring(dot).ToLowerInvariant();
    }

    static int CompareFiles(FoundFile first, FoundFile second, string? order)
    {
        // What was asked, then the path, so that files of the same size or date always come in the same order
        int difference = 0;
        if (order == "newest")
        {
            difference = second.Changed.CompareTo(first.Changed);
        }
        else if (order == "oldest")
        {
            difference = first.Changed.CompareTo(second.Changed);
        }
        else if (order == "largest")
        {
            difference = second.Size.CompareTo(first.Size);
        }
        else if (order == "smallest")
        {
            difference = first.Size.CompareTo(second.Size);
        }
        if (difference != 0)
        {
            return difference;
        }
        return string.CompareOrdinal(first.Path, second.Path);
    }

    static List<FoundFile> SelectFiles(string root, Filter filter)
    {
        // Filters: every one that is given must hold
        DateTime now = DateTime.UtcNow;
        List<FoundFile> kept = new List<FoundFile>();
        foreach (FoundFile file in FindFiles(root, filter.Recurse))
        {
            string name = Path.GetFileName(file.Path);
            string extension = ExtensionOf(name);
            if (filter.Name != null && !string.Equals(name, filter.Name, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            if (filter.ExceptName != null && string.Equals(name, filter.ExceptName, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            if (filter.Extensions != null && Array.IndexOf(filter.Extensions, extension) < 0)
            {
                continue;
            }
            if (Array.IndexOf(filter.ExceptExtensions, extension) >= 0)
            {
                continue;
            }
            if (filter.OlderThan != null && !(file.Changed < now.AddSeconds(-(double)filter.OlderThan.Value)))
            {
                continue;
            }
            if (filter.NewerThan != null && !(file.Changed >= now.AddSeconds(-(double)filter.NewerThan.Value)))
            {
                continue;
            }
            if (filter.MinSize != null && !(file.Size > filter.MinSize.Value))
            {
                continue;
            }
            if (filter.MaxSize != null && !(file.Size < filter.MaxSize.Value))
            {
                continue;
            }
            kept.Add(file);
        }
        kept.Sort((first, second) => CompareFiles(first, second, filter.Order));

        // The first ones only, or as many as it takes to free the bytes asked
        if (filter.Count != null && kept.Count > filter.Count.Value)
        {
            kept = kept.GetRange(0, filter.Count.Value);
        }
        if (filter.FreeBytes != null)
        {
            List<FoundFile> chosen = new List<FoundFile>();
            long freed = 0;
            foreach (FoundFile file in kept)
            {
                if (freed >= filter.FreeBytes.Value)
                {
                    break;
                }
                freed += file.Size;
                chosen.Add(file);
            }
            kept = chosen;
        }
        return kept;
    }
'@)
    }

    if ($need.List) {
        $lines.Add('')
        $lines.Add(@'
    static void ListFiles(List<FoundFile> files)
    {
        // One line per file: path, size in bytes, last change (UTC)
        foreach (FoundFile file in files)
        {
            string moment = file.Changed.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);
            Console.WriteLine(file.Path + "\t" + file.Size.ToString(CultureInfo.InvariantCulture) + "\t" + moment);
        }
    }
'@)
    }

    if ($need.Delete) {
        $lines.Add('')
        $lines.Add(@'
    static void DeleteFiles(List<FoundFile> files, bool apply)
    {
        // A real deletion: the file does not go to any trash
        foreach (FoundFile file in files)
        {
            if (!apply)
            {
                Console.WriteLine("would delete: " + file.Path);
                continue;
            }
            File.Delete(file.Path);
            Console.WriteLine("deleted: " + file.Path);
        }
    }
'@)
    }

    if ($need.Transfer) {
        $lines.Add('')
        $lines.Add(@'
    static void TransferFiles(List<FoundFile> files, string destination, bool move, bool apply)
    {
        // Into the destination when it is a folder; one file alone may also go to a new name
        string verb = move ? "move" : "copy";
        string done = move ? "moved" : "copied";
        bool intoFolder = Directory.Exists(destination);
        if (!intoFolder && files.Count > 1)
        {
            if (apply)
            {
                throw new StepException(destination + " is not an existing folder");
            }
            Console.Error.WriteLine("warning: " + destination + " is not an existing folder yet");
            intoFolder = true;
        }
        foreach (FoundFile file in files)
        {
            string target = destination;
            if (intoFolder)
            {
                target = Path.Combine(destination, Path.GetFileName(file.Path));
            }
            if (!apply)
            {
                Console.WriteLine("would " + verb + ": " + file.Path + " -> " + target);
                continue;
            }
            if (move)
            {
                // A move never replaces a file that is already there
                if (Exists(target))
                {
                    throw new StepException(target + " already exists");
                }
                File.Move(file.Path, target);
            }
            else
            {
                // A copy replaces a file of the same name, and keeps the date of the original
                File.Copy(file.Path, target, true);
                File.SetLastWriteTimeUtc(target, file.Changed);
            }
            Console.WriteLine(done + ": " + file.Path + " -> " + target);
        }
    }
'@)
    }

    if ($need.Rename) {
        $lines.Add('')
        $lines.Add(@'
    static void RenameItem(string source, string newName, bool apply)
    {
        // A file or a folder gets a new name in the folder it is in
        string target = Path.Combine(Path.GetDirectoryName(source) ?? "", newName);
        if (!apply)
        {
            Console.WriteLine("would rename: " + source + " -> " + target);
            return;
        }
        if (!Exists(source))
        {
            throw new StepException(source + " does not exist");
        }
        if (Exists(target))
        {
            throw new StepException(target + " already exists");
        }
        if (Directory.Exists(source))
        {
            Directory.Move(source, target);
        }
        else
        {
            File.Move(source, target);
        }
        Console.WriteLine("renamed: " + source + " -> " + target);
    }
'@)
    }

    if ($need.Create) {
        $lines.Add('')
        $lines.Add(@'
    static void CreateItem(string path, bool folder, bool apply)
    {
        // A new empty file (its folder must exist) or a new folder (with the folders above it)
        string kind = folder ? "folder" : "file";
        if (!apply)
        {
            Console.WriteLine("would create " + kind + ": " + path);
            return;
        }
        if (Exists(path))
        {
            throw new StepException(path + " already exists");
        }
        if (folder)
        {
            Directory.CreateDirectory(path);
        }
        else
        {
            new FileStream(path, FileMode.CreateNew).Dispose();
        }
        Console.WriteLine("created " + kind + ": " + path);
    }
'@)
    }

    # The steps of the plan
    $lines.Add('')
    $lines.Add('    static void Run(bool apply)')
    $lines.Add('    {')
    if ($need.Select) {
        $lines.Add('        Filter filter;')
        $lines.Add('        List<FoundFile> files;')
    }
    foreach ($step in $Model.Steps) {
        $lines.Add('')
        $lines.Add("        // Step $($step.Step): " + (ConvertTo-LambekCodeComment -Text $step.Sentence))
        foreach ($line in Format-LambekCodeCSharpStep -Step $step) { $lines.Add("        $line") }
    }
    if ($need.Changes) {
        $lines.Add('')
        $lines.Add('        if (!apply)')
        $lines.Add('        {')
        $lines.Add('            Console.WriteLine("Dry run: nothing was changed. Add --apply to really do it.");')
        $lines.Add('        }')
    }
    $lines.Add('    }')
    $lines.Add('')
    $lines.Add(@'
    static int Main(string[] args)
    {
        try
        {
            bool apply = false;
            foreach (string argument in args)
            {
                if (argument != "--apply")
                {
                    throw new StepException("unknown argument " + argument + " (the only one is --apply)");
                }
                apply = true;
            }
            Run(apply);
            return 0;
        }
        catch (Exception error) when (error is StepException || error is IOException || error is UnauthorizedAccessException)
        {
            Console.Error.WriteLine("error: " + error.Message);
            return 1;
        }
    }
}
'@)

    return (($lines -join "`n") -replace "`r", '') + "`n"
}

function Format-LambekCodeCSharpStep {
    param([pscustomobject] $Step)

    $quote = { param($text) ConvertTo-LambekCodeLiteral -Value $text -Language CSharp }

    if ($Step.Operation -eq 'rename') {
        return "RenameItem($(& $quote $Step.Source), $(& $quote $Step.NewName), apply);"
    }
    if ($Step.Operation -eq 'create') {
        $folder = 'false'
        if ($Step.Kind -eq 'Directory') { $folder = 'true' }
        return "CreateItem($(& $quote $Step.Path), $folder, apply);"
    }

    # The filters that were asked, one per line
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('filter = new Filter();')
    if ($Step.Recurse) { $lines.Add('filter.Recurse = true;') }
    if ($null -ne $Step.Name) { $lines.Add("filter.Name = $(& $quote $Step.Name);") }
    if ($null -ne $Step.Extensions) { $lines.Add("filter.Extensions = new string[] { $(@($Step.Extensions | ForEach-Object { & $quote $_ }) -join ', ') };") }
    if ($Step.ExceptExtensions.Count -gt 0) { $lines.Add("filter.ExceptExtensions = new string[] { $(@($Step.ExceptExtensions | ForEach-Object { & $quote $_ }) -join ', ') };") }
    if ($null -ne $Step.ExceptName) { $lines.Add("filter.ExceptName = $(& $quote $Step.ExceptName);") }
    if ($null -ne $Step.OlderThanSeconds) { $lines.Add("filter.OlderThan = $($Step.OlderThanSeconds)L;") }
    if ($null -ne $Step.NewerThanSeconds) { $lines.Add("filter.NewerThan = $($Step.NewerThanSeconds)L;") }
    if ($null -ne $Step.MinSize) { $lines.Add("filter.MinSize = $($Step.MinSize)L;") }
    if ($null -ne $Step.MaxSize) { $lines.Add("filter.MaxSize = $($Step.MaxSize)L;") }
    if ($null -ne $Step.Order) { $lines.Add("filter.Order = $(& $quote $Step.Order);") }
    if ($null -ne $Step.Count) { $lines.Add("filter.Count = $($Step.Count);") }
    if ($null -ne $Step.FreeBytes) { $lines.Add("filter.FreeBytes = $($Step.FreeBytes)L;") }
    $lines.Add("files = SelectFiles($(& $quote $Step.Root), filter);")
    switch ($Step.Operation) {
        'list' { $lines.Add('ListFiles(files);') }
        'delete' { $lines.Add('DeleteFiles(files, apply);') }
        'copy' { $lines.Add("TransferFiles(files, $(& $quote $Step.Destination), false, apply);") }
        'move' { $lines.Add("TransferFiles(files, $(& $quote $Step.Destination), true, apply);") }
    }
    return $lines.ToArray()
}
