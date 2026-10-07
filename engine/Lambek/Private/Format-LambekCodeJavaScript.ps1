function Format-LambekCodeJavaScript {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Model
    )

    $need = Get-LambekCodeNeed -Model $Model
    $lines = [System.Collections.Generic.List[string]]::new()

    # Header comment and modules
    $remark = @()
    if ($need.Select) { $remark = @('On Windows, Node cannot read the hidden attribute: hidden files are not skipped there.') }
    $lines.Add('#!/usr/bin/env node')
    foreach ($line in Get-LambekCodeHeader -Model $Model -Switch '--apply' -Needs 'Needs Node.js 18 or later, built-in modules only.' -Remark $remark) {
        $lines.Add(("// $line").TrimEnd())
    }
    $lines.Add('"use strict";')
    $lines.Add('')
    $lines.Add('const fs = require("fs");')
    $lines.Add('const path = require("path");')
    $lines.Add('')
    $lines.Add(@'
// A step that cannot go on
class StepError extends Error {}

function exists(file) {
  // True for a file, a folder or a link, even a broken one
  try {
    fs.lstatSync(file);
    return true;
  } catch (error) {
    return false;
  }
}

function isFolder(file) {
  try {
    return fs.statSync(file).isDirectory();
  } catch (error) {
    return false;
  }
}
'@)

    # Finding and choosing the files
    if ($need.Select -or $need.Transfer) {
        $lines.Add('')
        $lines.Add(@'
function joinPath(folder, name) {
  // Keeps the folder as it was written (path.join would rewrite it)
  if (folder.endsWith("/") || folder.endsWith(path.sep)) {
    return folder + name;
  }
  return folder + path.sep + name;
}
'@)
    }
    if ($need.Select) {
        $lines.Add('')
        $lines.Add(@'
function findFiles(root, recurse) {
  // Every file as { path, size in bytes, changed in nanoseconds }; a path to one file gives that file
  if (!isFolder(root)) {
    const info = fs.lstatSync(root, { bigint: true });
    return [{ path: root, size: Number(info.size), changed: info.mtimeNs }];
  }
  const found = [];
  const folders = [root];
  while (folders.length > 0) {
    const folder = folders.pop();
    for (const entry of fs.readdirSync(folder, { withFileTypes: true })) {
      if (process.platform !== "win32" && entry.name.startsWith(".")) {
        continue;
      }
      const file = joinPath(folder, entry.name);
      if (entry.isDirectory()) {
        if (recurse) {
          folders.push(file);
        }
        continue;
      }
      if (entry.isSymbolicLink() && isFolder(file)) {
        continue;
      }
      const info = fs.lstatSync(file, { bigint: true });
      found.push({ path: file, size: Number(info.size), changed: info.mtimeNs });
    }
  }
  return found;
}

function extensionOf(name) {
  // ".txt" for "Notes.TXT", "" for a name without a dot
  const dot = name.lastIndexOf(".");
  if (dot < 0) {
    return "";
  }
  return name.slice(dot).toLowerCase();
}

function compare(first, second) {
  if (first < second) {
    return -1;
  }
  if (first > second) {
    return 1;
  }
  return 0;
}

function selectFiles(root, options) {
  // Filters: every one that is given must hold. Ages are in seconds, sizes in bytes
  const now = BigInt(Date.now()) * 1000000n;
  const exceptExtensions = options.exceptExtensions || [];
  let kept = [];
  for (const file of findFiles(root, options.recurse === true)) {
    const base = path.basename(file.path);
    if (options.name !== undefined && base.toLowerCase() !== options.name.toLowerCase()) {
      continue;
    }
    if (options.exceptName !== undefined && base.toLowerCase() === options.exceptName.toLowerCase()) {
      continue;
    }
    if (options.extensions !== undefined && !options.extensions.includes(extensionOf(base))) {
      continue;
    }
    if (exceptExtensions.includes(extensionOf(base))) {
      continue;
    }
    if (options.olderThan !== undefined && !(file.changed < now - BigInt(options.olderThan) * 1000000000n)) {
      continue;
    }
    if (options.newerThan !== undefined && !(file.changed >= now - BigInt(options.newerThan) * 1000000000n)) {
      continue;
    }
    if (options.minSize !== undefined && !(file.size > options.minSize)) {
      continue;
    }
    if (options.maxSize !== undefined && !(file.size < options.maxSize)) {
      continue;
    }
    kept.push(file);
  }

  // Order: what was asked, then the path, so that files of the same size or date always come in the same order
  kept.sort((first, second) => {
    let difference = 0;
    if (options.order === "newest") {
      difference = compare(second.changed, first.changed);
    } else if (options.order === "oldest") {
      difference = compare(first.changed, second.changed);
    } else if (options.order === "largest") {
      difference = compare(second.size, first.size);
    } else if (options.order === "smallest") {
      difference = compare(first.size, second.size);
    }
    if (difference !== 0) {
      return difference;
    }
    return compare(first.path, second.path);
  });

  // The first ones only, or as many as it takes to free the bytes asked
  if (options.count !== undefined) {
    kept = kept.slice(0, options.count);
  }
  if (options.freeBytes !== undefined) {
    const chosen = [];
    let freed = 0;
    for (const file of kept) {
      if (freed >= options.freeBytes) {
        break;
      }
      freed += file.size;
      chosen.push(file);
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
function listFiles(files) {
  // One line per file: path, size in bytes, last change (UTC)
  for (const file of files) {
    const moment = new Date(Number(file.changed / 1000000n)).toISOString().slice(0, 19) + "Z";
    console.log(file.path + "\t" + file.size + "\t" + moment);
  }
}
'@)
    }

    if ($need.Delete) {
        $lines.Add('')
        $lines.Add(@'
function deleteFiles(files, apply) {
  // A real deletion: the file does not go to any trash
  for (const file of files) {
    if (!apply) {
      console.log("would delete: " + file.path);
      continue;
    }
    fs.unlinkSync(file.path);
    console.log("deleted: " + file.path);
  }
}
'@)
    }

    if ($need.Transfer) {
        $lines.Add('')
        $lines.Add(@'
function copyFile(source, target) {
  // Replaces a file of the same name, and keeps the date of the original
  const info = fs.statSync(source);
  fs.copyFileSync(source, target);
  fs.utimesSync(target, info.atime, info.mtime);
}

function transferFiles(files, destination, move, apply) {
  // Into the destination when it is a folder; one file alone may also go to a new name
  const verb = move ? "move" : "copy";
  const done = move ? "moved" : "copied";
  let intoFolder = isFolder(destination);
  if (!intoFolder && files.length > 1) {
    if (apply) {
      throw new StepError(destination + " is not an existing folder");
    }
    console.error("warning: " + destination + " is not an existing folder yet");
    intoFolder = true;
  }
  for (const file of files) {
    let target = destination;
    if (intoFolder) {
      target = joinPath(destination, path.basename(file.path));
    }
    if (!apply) {
      console.log("would " + verb + ": " + file.path + " -> " + target);
      continue;
    }
    if (move) {
      // A move never replaces a file that is already there
      if (exists(target)) {
        throw new StepError(target + " already exists");
      }
      try {
        fs.renameSync(file.path, target);
      } catch (error) {
        // Another disk: copy, then remove the original
        if (error.code !== "EXDEV") {
          throw error;
        }
        copyFile(file.path, target);
        fs.unlinkSync(file.path);
      }
    } else {
      copyFile(file.path, target);
    }
    console.log(done + ": " + file.path + " -> " + target);
  }
}
'@)
    }

    if ($need.Rename) {
        $lines.Add('')
        $lines.Add(@'
function renameItem(source, newName, apply) {
  // A file or a folder gets a new name in the folder it is in
  const target = path.join(path.dirname(source), newName);
  if (!apply) {
    console.log("would rename: " + source + " -> " + target);
    return;
  }
  if (!exists(source)) {
    throw new StepError(source + " does not exist");
  }
  if (exists(target)) {
    throw new StepError(target + " already exists");
  }
  fs.renameSync(source, target);
  console.log("renamed: " + source + " -> " + target);
}
'@)
    }

    if ($need.Create) {
        $lines.Add('')
        $lines.Add(@'
function createItem(target, folder, apply) {
  // A new empty file (its folder must exist) or a new folder (with the folders above it)
  const kind = folder ? "folder" : "file";
  if (!apply) {
    console.log("would create " + kind + ": " + target);
    return;
  }
  if (exists(target)) {
    throw new StepError(target + " already exists");
  }
  if (folder) {
    fs.mkdirSync(target, { recursive: true });
  } else {
    fs.closeSync(fs.openSync(target, "wx"));
  }
  console.log("created " + kind + ": " + target);
}
'@)
    }

    # The steps of the plan
    $lines.Add('')
    $lines.Add('function main() {')
    $lines.Add('  const parameters = process.argv.slice(2);')
    $lines.Add('  for (const parameter of parameters) {')
    $lines.Add('    if (parameter !== "--apply") {')
    $lines.Add('      throw new StepError("unknown argument " + parameter + " (the only one is --apply)");')
    $lines.Add('    }')
    $lines.Add('  }')
    if ($need.Changes) { $lines.Add('  const apply = parameters.includes("--apply");') }
    if ($need.Select) { $lines.Add('  let files = [];') }
    foreach ($step in $Model.Steps) {
        $lines.Add('')
        $lines.Add("  // Step $($step.Step): " + (ConvertTo-LambekCodeComment -Text $step.Sentence))
        foreach ($line in Format-LambekCodeJavaScriptStep -Step $step) { $lines.Add("  $line") }
    }
    if ($need.Changes) {
        $lines.Add('')
        $lines.Add('  if (!apply) {')
        $lines.Add('    console.log("Dry run: nothing was changed. Add --apply to really do it.");')
        $lines.Add('  }')
    }
    $lines.Add('}')
    $lines.Add('')
    $lines.Add(@'
try {
  main();
} catch (error) {
  console.error("error: " + error.message);
  process.exitCode = 1;
}
'@)

    return (($lines -join "`n") -replace "`r", '') + "`n"
}

function Format-LambekCodeJavaScriptStep {
    param([pscustomobject] $Step)

    $quote = { param($text) ConvertTo-LambekCodeLiteral -Value $text -Language JavaScript }

    if ($Step.Operation -eq 'rename') {
        return "renameItem($(& $quote $Step.Source), $(& $quote $Step.NewName), apply);"
    }
    if ($Step.Operation -eq 'create') {
        $folder = 'false'
        if ($Step.Kind -eq 'Directory') { $folder = 'true' }
        return "createItem($(& $quote $Step.Path), $folder, apply);"
    }

    # The filters that were asked, one per line
    $options = [System.Collections.Generic.List[string]]::new()
    if ($Step.Recurse) { $options.Add('recurse: true') }
    if ($null -ne $Step.Name) { $options.Add("name: $(& $quote $Step.Name)") }
    if ($null -ne $Step.Extensions) { $options.Add("extensions: [$(@($Step.Extensions | ForEach-Object { & $quote $_ }) -join ', ')]") }
    if ($Step.ExceptExtensions.Count -gt 0) { $options.Add("exceptExtensions: [$(@($Step.ExceptExtensions | ForEach-Object { & $quote $_ }) -join ', ')]") }
    if ($null -ne $Step.ExceptName) { $options.Add("exceptName: $(& $quote $Step.ExceptName)") }
    if ($null -ne $Step.OlderThanSeconds) { $options.Add("olderThan: $($Step.OlderThanSeconds)") }
    if ($null -ne $Step.NewerThanSeconds) { $options.Add("newerThan: $($Step.NewerThanSeconds)") }
    if ($null -ne $Step.MinSize) { $options.Add("minSize: $($Step.MinSize)") }
    if ($null -ne $Step.MaxSize) { $options.Add("maxSize: $($Step.MaxSize)") }
    if ($null -ne $Step.Order) { $options.Add("order: $(& $quote $Step.Order)") }
    if ($null -ne $Step.Count) { $options.Add("count: $($Step.Count)") }
    if ($null -ne $Step.FreeBytes) { $options.Add("freeBytes: $($Step.FreeBytes)") }

    $lines = [System.Collections.Generic.List[string]]::new()
    if ($options.Count -eq 0) {
        $lines.Add("files = selectFiles($(& $quote $Step.Root), {});")
    }
    else {
        $lines.Add("files = selectFiles($(& $quote $Step.Root), {")
        foreach ($option in $options) { $lines.Add("  $option,") }
        $lines.Add('});')
    }
    switch ($Step.Operation) {
        'list' { $lines.Add('listFiles(files);') }
        'delete' { $lines.Add('deleteFiles(files, apply);') }
        'copy' { $lines.Add("transferFiles(files, $(& $quote $Step.Destination), false, apply);") }
        'move' { $lines.Add("transferFiles(files, $(& $quote $Step.Destination), true, apply);") }
    }
    return $lines.ToArray()
}
