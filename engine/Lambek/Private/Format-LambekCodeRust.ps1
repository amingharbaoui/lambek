function Format-LambekCodeRust {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Model
    )

    $need = Get-LambekCodeNeed -Model $Model
    $lines = [System.Collections.Generic.List[string]]::new()

    # Header comment and imports
    foreach ($line in Get-LambekCodeHeader -Model $Model -Switch '--apply' -Needs 'Needs Rust 1.75 or later (edition 2021), standard library only: rustc --edition 2021 main.rs') {
        $lines.Add(("// $line").TrimEnd())
    }
    $lines.Add('use std::env;')
    $lines.Add('use std::fs;')
    if ($need.Select -or $need.Rename) { $lines.Add('use std::path::Path;') }
    $lines.Add('use std::process;')
    if ($need.Select) { $lines.Add('use std::time::{SystemTime, UNIX_EPOCH};') }
    $lines.Add('')
    $lines.Add(@'
// Every function gives back the error as a text, ready to print
type Outcome<T> = Result<T, String>;

fn exists(path: &str) -> bool {
    // True for a file, a folder or a link, even a broken one
    fs::symlink_metadata(path).is_ok()
}
'@)

    # Finding and choosing the files
    if ($need.Select -or $need.Transfer) {
        $lines.Add('')
        $lines.Add(@'
fn file_name_of(path: &str) -> String {
    // The last part of a path
    match Path::new(path).file_name() {
        Some(name) => name.to_string_lossy().into_owned(),
        None => String::new(),
    }
}

fn join_path(folder: &str, name: &str) -> String {
    // Keeps the folder as it was written
    if folder.ends_with('/') || folder.ends_with(std::path::MAIN_SEPARATOR) {
        return format!("{}{}", folder, name);
    }
    format!("{}{}{}", folder, std::path::MAIN_SEPARATOR, name)
}
'@)
    }
    if ($need.Select) {
        $lines.Add('')
        $lines.Add(@'
// One file that was found: its path, its size in bytes and its last change in nanoseconds since 1970
struct FoundFile {
    path: String,
    size: u64,
    changed: i128,
}

// The filters of one step: the ones left at None are not asked. Ages are in seconds, sizes in bytes
#[derive(Default)]
struct Filter {
    recurse: bool,
    name: Option<&'static str>,
    extensions: Option<&'static [&'static str]>,
    except_extensions: &'static [&'static str],
    except_name: Option<&'static str>,
    older_than: Option<i128>,
    newer_than: Option<i128>,
    min_size: Option<u64>,
    max_size: Option<u64>,
    order: Option<&'static str>,
    count: Option<usize>,
    free_bytes: Option<u64>,
}

fn nanoseconds(moment: SystemTime) -> i128 {
    // Nanoseconds since 1970, negative before
    match moment.duration_since(UNIX_EPOCH) {
        Ok(after) => after.as_nanos() as i128,
        Err(before) => -(before.duration().as_nanos() as i128),
    }
}

#[cfg(windows)]
fn is_hidden(_name: &str, info: &fs::Metadata) -> bool {
    // Windows marks a hidden file with an attribute
    use std::os::windows::fs::MetadataExt;
    info.file_attributes() & 2 != 0
}

#[cfg(not(windows))]
fn is_hidden(name: &str, _info: &fs::Metadata) -> bool {
    // The other systems hide a name that starts with a dot
    name.starts_with('.')
}

fn describe(path: &str, info: &fs::Metadata) -> Outcome<FoundFile> {
    let changed = info.modified().map_err(|error| format!("{}: {}", path, error))?;
    Ok(FoundFile { path: path.to_string(), size: info.len(), changed: nanoseconds(changed) })
}

fn find_files(root: &str, recurse: bool) -> Outcome<Vec<FoundFile>> {
    // Every file below the root; a path to one file gives that file
    let mut found = Vec::new();
    if !Path::new(root).is_dir() {
        let info = fs::symlink_metadata(root).map_err(|error| format!("{}: {}", root, error))?;
        found.push(describe(root, &info)?);
        return Ok(found);
    }
    let mut folders = vec![root.to_string()];
    while let Some(folder) = folders.pop() {
        let entries = fs::read_dir(&folder).map_err(|error| format!("{}: {}", folder, error))?;
        for entry in entries {
            let entry = entry.map_err(|error| format!("{}: {}", folder, error))?;
            let name = entry.file_name().to_string_lossy().into_owned();
            let path = join_path(&folder, &name);
            // The entry itself, not what a link leads to
            let info = entry.metadata().map_err(|error| format!("{}: {}", path, error))?;
            if is_hidden(&name, &info) {
                continue;
            }
            if info.is_dir() {
                if recurse {
                    folders.push(path);
                }
                continue;
            }
            // A link to a folder is not a file, and is not followed
            if info.file_type().is_symlink() && Path::new(&path).is_dir() {
                continue;
            }
            found.push(describe(&path, &info)?);
        }
    }
    Ok(found)
}

fn extension_of(name: &str) -> String {
    // ".txt" for "Notes.TXT", "" for a name without a dot
    match name.rfind('.') {
        Some(dot) => name[dot..].to_lowercase(),
        None => String::new(),
    }
}

fn select_files(root: &str, filter: &Filter) -> Outcome<Vec<FoundFile>> {
    // Filters: every one that is given must hold
    let now = nanoseconds(SystemTime::now());
    let mut kept = Vec::new();
    for file in find_files(root, filter.recurse)? {
        let name = file_name_of(&file.path);
        let extension = extension_of(&name);
        if let Some(wanted) = filter.name {
            if name.to_lowercase() != wanted.to_lowercase() {
                continue;
            }
        }
        if let Some(unwanted) = filter.except_name {
            if name.to_lowercase() == unwanted.to_lowercase() {
                continue;
            }
        }
        if let Some(extensions) = filter.extensions {
            if !extensions.contains(&extension.as_str()) {
                continue;
            }
        }
        if filter.except_extensions.contains(&extension.as_str()) {
            continue;
        }
        if let Some(age) = filter.older_than {
            if !(file.changed < now - age * 1_000_000_000) {
                continue;
            }
        }
        if let Some(age) = filter.newer_than {
            if !(file.changed >= now - age * 1_000_000_000) {
                continue;
            }
        }
        if let Some(size) = filter.min_size {
            if !(file.size > size) {
                continue;
            }
        }
        if let Some(size) = filter.max_size {
            if !(file.size < size) {
                continue;
            }
        }
        kept.push(file);
    }

    // Order: what was asked, then the path, so that files of the same size or date always come in the same order
    kept.sort_by(|first, second| {
        let difference = match filter.order {
            Some("newest") => second.changed.cmp(&first.changed),
            Some("oldest") => first.changed.cmp(&second.changed),
            Some("largest") => second.size.cmp(&first.size),
            Some("smallest") => first.size.cmp(&second.size),
            _ => std::cmp::Ordering::Equal,
        };
        difference.then_with(|| first.path.cmp(&second.path))
    });

    // The first ones only, or as many as it takes to free the bytes asked
    if let Some(count) = filter.count {
        kept.truncate(count);
    }
    if let Some(wanted) = filter.free_bytes {
        let mut chosen = Vec::new();
        let mut freed: u64 = 0;
        for file in kept {
            if freed >= wanted {
                break;
            }
            freed += file.size;
            chosen.push(file);
        }
        kept = chosen;
    }
    Ok(kept)
}
'@)
    }

    if ($need.List) {
        $lines.Add('')
        $lines.Add(@'
fn utc_text(changed: i128) -> String {
    // Seconds since 1970 as a date of the calendar (UTC), without any library
    let seconds = changed.div_euclid(1_000_000_000);
    let days = seconds.div_euclid(86_400);
    let rest = seconds.rem_euclid(86_400);
    let shifted = days + 719_468;
    let era = shifted.div_euclid(146_097);
    let day_of_era = shifted.rem_euclid(146_097);
    let year_of_era = (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_index = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_index + 2) / 5 + 1;
    let month = if month_index < 10 { month_index + 3 } else { month_index - 9 };
    let year = year_of_era + era * 400 + if month <= 2 { 1 } else { 0 };
    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", year, month, day, rest / 3_600, rest % 3_600 / 60, rest % 60)
}

fn list_files(files: &[FoundFile]) {
    // One line per file: path, size in bytes, last change (UTC)
    for file in files {
        println!("{}\t{}\t{}", file.path, file.size, utc_text(file.changed));
    }
}
'@)
    }

    if ($need.Delete) {
        $lines.Add('')
        $lines.Add(@'
fn delete_files(files: &[FoundFile], apply: bool) -> Outcome<()> {
    // A real deletion: the file does not go to any trash
    for file in files {
        if !apply {
            println!("would delete: {}", file.path);
            continue;
        }
        fs::remove_file(&file.path).map_err(|error| format!("{}: {}", file.path, error))?;
        println!("deleted: {}", file.path);
    }
    Ok(())
}
'@)
    }

    if ($need.Transfer) {
        $lines.Add('')
        $lines.Add(@'
fn copy_file(source: &str, target: &str) -> Outcome<()> {
    // Replaces a file of the same name, and keeps the date of the original
    let info = fs::metadata(source).map_err(|error| format!("{}: {}", source, error))?;
    fs::copy(source, target).map_err(|error| format!("{}: {}", target, error))?;
    let changed = info.modified().map_err(|error| format!("{}: {}", source, error))?;
    let copy = fs::OpenOptions::new().write(true).open(target).map_err(|error| format!("{}: {}", target, error))?;
    copy.set_modified(changed).map_err(|error| format!("{}: {}", target, error))?;
    Ok(())
}

fn transfer_files(files: &[FoundFile], destination: &str, moving: bool, apply: bool) -> Outcome<()> {
    // Into the destination when it is a folder; one file alone may also go to a new name
    let verb = if moving { "move" } else { "copy" };
    let done = if moving { "moved" } else { "copied" };
    let mut into_folder = Path::new(destination).is_dir();
    if !into_folder && files.len() > 1 {
        if apply {
            return Err(format!("{} is not an existing folder", destination));
        }
        eprintln!("warning: {} is not an existing folder yet", destination);
        into_folder = true;
    }
    for file in files {
        let mut target = destination.to_string();
        if into_folder {
            target = join_path(destination, &file_name_of(&file.path));
        }
        if !apply {
            println!("would {}: {} -> {}", verb, file.path, target);
            continue;
        }
        if moving {
            // A move never replaces a file that is already there
            if exists(&target) {
                return Err(format!("{} already exists", target));
            }
            if fs::rename(&file.path, &target).is_err() {
                // Another disk: copy, then remove the original
                copy_file(&file.path, &target)?;
                fs::remove_file(&file.path).map_err(|error| format!("{}: {}", file.path, error))?;
            }
        } else {
            copy_file(&file.path, &target)?;
        }
        println!("{}: {} -> {}", done, file.path, target);
    }
    Ok(())
}
'@)
    }

    if ($need.Rename) {
        $lines.Add('')
        $lines.Add(@'
fn rename_item(source: &str, new_name: &str, apply: bool) -> Outcome<()> {
    // A file or a folder gets a new name in the folder it is in
    let target = Path::new(source).with_file_name(new_name).to_string_lossy().into_owned();
    if !apply {
        println!("would rename: {} -> {}", source, target);
        return Ok(());
    }
    if !exists(source) {
        return Err(format!("{} does not exist", source));
    }
    if exists(&target) {
        return Err(format!("{} already exists", target));
    }
    fs::rename(source, &target).map_err(|error| format!("{}: {}", source, error))?;
    println!("renamed: {} -> {}", source, target);
    Ok(())
}
'@)
    }

    if ($need.Create) {
        $lines.Add('')
        $lines.Add(@'
fn create_item(path: &str, folder: bool, apply: bool) -> Outcome<()> {
    // A new empty file (its folder must exist) or a new folder (with the folders above it)
    let kind = if folder { "folder" } else { "file" };
    if !apply {
        println!("would create {}: {}", kind, path);
        return Ok(());
    }
    if exists(path) {
        return Err(format!("{} already exists", path));
    }
    if folder {
        fs::create_dir_all(path).map_err(|error| format!("{}: {}", path, error))?;
    } else {
        fs::OpenOptions::new().write(true).create_new(true).open(path).map_err(|error| format!("{}: {}", path, error))?;
    }
    println!("created {}: {}", kind, path);
    Ok(())
}
'@)
    }

    # The steps of the plan
    $lines.Add('')
    if ($need.Changes) { $lines.Add('fn run(apply: bool) -> Outcome<()> {') }
    else { $lines.Add('fn run(_apply: bool) -> Outcome<()> {') }
    $first = $true
    foreach ($step in $Model.Steps) {
        if (-not $first) { $lines.Add('') }
        $first = $false
        $lines.Add("    // Step $($step.Step): " + (ConvertTo-LambekCodeComment -Text $step.Sentence))
        foreach ($line in Format-LambekCodeRustStep -Step $step) { $lines.Add("    $line") }
    }
    if ($need.Changes) {
        $lines.Add('')
        $lines.Add('    if !apply {')
        $lines.Add('        println!("Dry run: nothing was changed. Add --apply to really do it.");')
        $lines.Add('    }')
    }
    $lines.Add('    Ok(())')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add(@'
fn main() {
    let mut apply = false;
    for argument in env::args().skip(1) {
        if argument != "--apply" {
            eprintln!("error: unknown argument {} (the only one is --apply)", argument);
            process::exit(1);
        }
        apply = true;
    }
    if let Err(message) = run(apply) {
        eprintln!("error: {}", message);
        process::exit(1);
    }
}
'@)

    return (($lines -join "`n") -replace "`r", '') + "`n"
}

function Format-LambekCodeRustStep {
    param([pscustomobject] $Step)

    $quote = { param($text) ConvertTo-LambekCodeLiteral -Value $text -Language Rust }

    if ($Step.Operation -eq 'rename') {
        return "rename_item($(& $quote $Step.Source), $(& $quote $Step.NewName), apply)?;"
    }
    if ($Step.Operation -eq 'create') {
        $folder = 'false'
        if ($Step.Kind -eq 'Directory') { $folder = 'true' }
        return "create_item($(& $quote $Step.Path), $folder, apply)?;"
    }

    # The filters that were asked, one per line; the others keep their empty value
    $fields = [System.Collections.Generic.List[string]]::new()
    if ($Step.Recurse) { $fields.Add('recurse: true') }
    if ($null -ne $Step.Name) { $fields.Add("name: Some($(& $quote $Step.Name))") }
    if ($null -ne $Step.Extensions) { $fields.Add("extensions: Some(&[$(@($Step.Extensions | ForEach-Object { & $quote $_ }) -join ', ')])") }
    if ($Step.ExceptExtensions.Count -gt 0) { $fields.Add("except_extensions: &[$(@($Step.ExceptExtensions | ForEach-Object { & $quote $_ }) -join ', ')]") }
    if ($null -ne $Step.ExceptName) { $fields.Add("except_name: Some($(& $quote $Step.ExceptName))") }
    if ($null -ne $Step.OlderThanSeconds) { $fields.Add("older_than: Some($($Step.OlderThanSeconds))") }
    if ($null -ne $Step.NewerThanSeconds) { $fields.Add("newer_than: Some($($Step.NewerThanSeconds))") }
    if ($null -ne $Step.MinSize) { $fields.Add("min_size: Some($($Step.MinSize))") }
    if ($null -ne $Step.MaxSize) { $fields.Add("max_size: Some($($Step.MaxSize))") }
    if ($null -ne $Step.Order) { $fields.Add("order: Some($(& $quote $Step.Order))") }
    if ($null -ne $Step.Count) { $fields.Add("count: Some($($Step.Count))") }
    if ($null -ne $Step.FreeBytes) { $fields.Add("free_bytes: Some($($Step.FreeBytes))") }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('let filter = Filter {')
    foreach ($field in $fields) { $lines.Add("    $field,") }
    $lines.Add('    ..Default::default()')
    $lines.Add('};')
    $lines.Add("let files = select_files($(& $quote $Step.Root), &filter)?;")
    switch ($Step.Operation) {
        'list' { $lines.Add('list_files(&files);') }
        'delete' { $lines.Add('delete_files(&files, apply)?;') }
        'copy' { $lines.Add("transfer_files(&files, $(& $quote $Step.Destination), false, apply)?;") }
        'move' { $lines.Add("transfer_files(&files, $(& $quote $Step.Destination), true, apply)?;") }
    }
    return $lines.ToArray()
}
