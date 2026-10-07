function Format-LambekCodePython {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Model
    )

    $need = Get-LambekCodeNeed -Model $Model
    $lines = [System.Collections.Generic.List[string]]::new()

    # Header comment and imports
    $lines.Add('#!/usr/bin/env python3')
    foreach ($line in Get-LambekCodeHeader -Model $Model -Switch '--apply' -Needs 'Needs Python 3.8 or later, standard library only.') {
        $lines.Add(("# $line").TrimEnd())
    }
    $lines.Add('import os')
    if ($need.Transfer) { $lines.Add('import shutil') }
    if ($need.Select) { $lines.Add('import stat') }
    $lines.Add('import sys')
    if ($need.Select) { $lines.Add('import time') }
    if ($need.List) { $lines.Add('from datetime import datetime, timezone') }
    $lines.Add('')
    $lines.Add('')
    $lines.Add(@'
class StepError(Exception):
    """A step that cannot go on."""
'@)

    # Finding and choosing the files
    if ($need.Select) {
        $lines.Add('')
        $lines.Add('')
        $lines.Add(@'
def is_hidden(entry):
    # Windows marks a hidden file with an attribute, the other systems with a leading dot
    if os.name == "nt":
        attributes = entry.stat(follow_symlinks=False).st_file_attributes
        return bool(attributes & stat.FILE_ATTRIBUTE_HIDDEN)
    return entry.name.startswith(".")


def find_files(root, recurse):
    # Every file as (path, size in bytes, last change in nanoseconds); a path to one file gives that file
    if not os.path.isdir(root):
        info = os.lstat(root)
        return [(root, info.st_size, info.st_mtime_ns)]
    found = []
    folders = [root]
    while folders:
        folder = folders.pop()
        with os.scandir(folder) as entries:
            for entry in entries:
                if is_hidden(entry):
                    continue
                if entry.is_dir(follow_symlinks=False):
                    if recurse:
                        folders.append(entry.path)
                    continue
                if entry.is_symlink() and os.path.isdir(entry.path):
                    continue
                info = entry.stat(follow_symlinks=False)
                found.append((entry.path, info.st_size, info.st_mtime_ns))
    return found


def extension_of(name):
    # ".txt" for "Notes.TXT", "" for a name without a dot
    dot = name.rfind(".")
    if dot < 0:
        return ""
    return name[dot:].lower()


def select_files(root, recurse=False, name=None, extensions=None, except_extensions=(),
                 except_name=None, older_than=None, newer_than=None, min_size=None,
                 max_size=None, order=None, count=None, free_bytes=None):
    # Filters: every one that is given must hold. Ages are in seconds, sizes in bytes
    now = time.time_ns()
    kept = []
    for path, size, changed in find_files(root, recurse):
        base = os.path.basename(path)
        if name is not None and base.lower() != name.lower():
            continue
        if except_name is not None and base.lower() == except_name.lower():
            continue
        if extensions is not None and extension_of(base) not in extensions:
            continue
        if extension_of(base) in except_extensions:
            continue
        if older_than is not None and not changed < now - older_than * 1000000000:
            continue
        if newer_than is not None and not changed >= now - newer_than * 1000000000:
            continue
        if min_size is not None and not size > min_size:
            continue
        if max_size is not None and not size < max_size:
            continue
        kept.append((path, size, changed))

    # Order: by path first, so that files of the same size or date always come in the same order
    kept.sort(key=lambda item: item[0])
    if order == "newest":
        kept.sort(key=lambda item: item[2], reverse=True)
    elif order == "oldest":
        kept.sort(key=lambda item: item[2])
    elif order == "largest":
        kept.sort(key=lambda item: item[1], reverse=True)
    elif order == "smallest":
        kept.sort(key=lambda item: item[1])

    # The first ones only, or as many as it takes to free the bytes asked
    if count is not None:
        kept = kept[:count]
    if free_bytes is not None:
        chosen = []
        freed = 0
        for item in kept:
            if freed >= free_bytes:
                break
            freed += item[1]
            chosen.append(item)
        kept = chosen
    return kept
'@)
    }

    if ($need.List) {
        $lines.Add('')
        $lines.Add('')
        $lines.Add(@'
def list_files(files):
    # One line per file: path, size in bytes, last change (UTC)
    for path, size, changed in files:
        moment = datetime.fromtimestamp(changed // 1000000000, timezone.utc)
        print(path + "\t" + str(size) + "\t" + moment.strftime("%Y-%m-%dT%H:%M:%SZ"))
'@)
    }

    if ($need.Delete) {
        $lines.Add('')
        $lines.Add('')
        $lines.Add(@'
def delete_files(files, apply):
    # A real deletion: the file does not go to any trash
    for path, _size, _changed in files:
        if not apply:
            print("would delete: " + path)
            continue
        os.remove(path)
        print("deleted: " + path)
'@)
    }

    if ($need.Transfer) {
        $lines.Add('')
        $lines.Add('')
        $lines.Add(@'
def transfer_files(files, destination, move, apply):
    # Into the destination when it is a folder; one file alone may also go to a new name
    verb, done = ("move", "moved") if move else ("copy", "copied")
    into_folder = os.path.isdir(destination)
    if not into_folder and len(files) > 1:
        if apply:
            raise StepError(destination + " is not an existing folder")
        print("warning: " + destination + " is not an existing folder yet", file=sys.stderr)
        into_folder = True
    for path, _size, _changed in files:
        target = destination
        if into_folder:
            target = os.path.join(destination, os.path.basename(path))
        if not apply:
            print("would " + verb + ": " + path + " -> " + target)
            continue
        if move:
            # A move never replaces a file that is already there
            if os.path.lexists(target):
                raise StepError(target + " already exists")
            shutil.move(path, target)
        else:
            # A copy replaces a file of the same name, and keeps the date of the original
            shutil.copy2(path, target)
        print(done + ": " + path + " -> " + target)
'@)
    }

    if ($need.Rename) {
        $lines.Add('')
        $lines.Add('')
        $lines.Add(@'
def rename_item(source, new_name, apply):
    # A file or a folder gets a new name in the folder it is in
    target = os.path.join(os.path.dirname(source), new_name)
    if not apply:
        print("would rename: " + source + " -> " + target)
        return
    if not os.path.lexists(source):
        raise StepError(source + " does not exist")
    if os.path.lexists(target):
        raise StepError(target + " already exists")
    os.rename(source, target)
    print("renamed: " + source + " -> " + target)
'@)
    }

    if ($need.Create) {
        $lines.Add('')
        $lines.Add('')
        $lines.Add(@'
def create_item(path, folder, apply):
    # A new empty file (its folder must exist) or a new folder (with the folders above it)
    kind = "folder" if folder else "file"
    if not apply:
        print("would create " + kind + ": " + path)
        return
    if os.path.lexists(path):
        raise StepError(path + " already exists")
    if folder:
        os.makedirs(path)
    else:
        with open(path, "x"):
            pass
    print("created " + kind + ": " + path)
'@)
    }

    # The steps of the plan
    $lines.Add('')
    $lines.Add('')
    $lines.Add('def main():')
    $lines.Add('    arguments = sys.argv[1:]')
    $lines.Add('    for argument in arguments:')
    $lines.Add('        if argument != "--apply":')
    $lines.Add('            raise StepError("unknown argument " + argument + " (the only one is --apply)")')
    if ($need.Changes) { $lines.Add('    apply = "--apply" in arguments') }
    $lines.Add('    sys.stdout.reconfigure(errors="backslashreplace")')
    foreach ($step in $Model.Steps) {
        $lines.Add('')
        $lines.Add("    # Step $($step.Step): " + (ConvertTo-LambekCodeComment -Text $step.Sentence))
        foreach ($line in Format-LambekCodePythonStep -Step $step) { $lines.Add("    $line") }
    }
    if ($need.Changes) {
        $lines.Add('')
        $lines.Add('    if not apply:')
        $lines.Add('        print("Dry run: nothing was changed. Add --apply to really do it.")')
    }
    $lines.Add('    return 0')
    $lines.Add('')
    $lines.Add('')
    $lines.Add(@'
if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, StepError) as error:
        print("error: " + str(error), file=sys.stderr)
        sys.exit(1)
'@)

    return (($lines -join "`n") -replace "`r", '') + "`n"
}

function Format-LambekCodePythonStep {
    param([pscustomobject] $Step)

    $quote = { param($text) ConvertTo-LambekCodeLiteral -Value $text -Language Python }

    if ($Step.Operation -eq 'rename') {
        return "rename_item($(& $quote $Step.Source), $(& $quote $Step.NewName), apply)"
    }
    if ($Step.Operation -eq 'create') {
        $folder = 'False'
        if ($Step.Kind -eq 'Directory') { $folder = 'True' }
        return "create_item($(& $quote $Step.Path), $folder, apply)"
    }

    # The filters that were asked, one per line
    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add((& $quote $Step.Root))
    if ($Step.Recurse) { $arguments.Add('recurse=True') }
    if ($null -ne $Step.Name) { $arguments.Add("name=$(& $quote $Step.Name)") }
    if ($null -ne $Step.Extensions) { $arguments.Add("extensions=[$(@($Step.Extensions | ForEach-Object { & $quote $_ }) -join ', ')]") }
    if ($Step.ExceptExtensions.Count -gt 0) { $arguments.Add("except_extensions=[$(@($Step.ExceptExtensions | ForEach-Object { & $quote $_ }) -join ', ')]") }
    if ($null -ne $Step.ExceptName) { $arguments.Add("except_name=$(& $quote $Step.ExceptName)") }
    if ($null -ne $Step.OlderThanSeconds) { $arguments.Add("older_than=$($Step.OlderThanSeconds)") }
    if ($null -ne $Step.NewerThanSeconds) { $arguments.Add("newer_than=$($Step.NewerThanSeconds)") }
    if ($null -ne $Step.MinSize) { $arguments.Add("min_size=$($Step.MinSize)") }
    if ($null -ne $Step.MaxSize) { $arguments.Add("max_size=$($Step.MaxSize)") }
    if ($null -ne $Step.Order) { $arguments.Add("order=$(& $quote $Step.Order)") }
    if ($null -ne $Step.Count) { $arguments.Add("count=$($Step.Count)") }
    if ($null -ne $Step.FreeBytes) { $arguments.Add("free_bytes=$($Step.FreeBytes)") }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('files = select_files(')
    foreach ($argument in $arguments) { $lines.Add("    $argument,") }
    $lines.Add(')')
    switch ($Step.Operation) {
        'list' { $lines.Add('list_files(files)') }
        'delete' { $lines.Add('delete_files(files, apply)') }
        'copy' { $lines.Add("transfer_files(files, $(& $quote $Step.Destination), False, apply)") }
        'move' { $lines.Add("transfer_files(files, $(& $quote $Step.Destination), True, apply)") }
    }
    return $lines.ToArray()
}
