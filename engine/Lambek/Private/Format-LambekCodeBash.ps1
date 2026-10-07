function Format-LambekCodeBash {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Model
    )

    $need = Get-LambekCodeNeed -Model $Model
    $lines = [System.Collections.Generic.List[string]]::new()

    # Header comment and the arguments
    $lines.Add('#!/usr/bin/env bash')
    foreach ($line in Get-LambekCodeHeader -Model $Model -Switch '--apply' -Needs 'Needs Bash 4.2 or later with GNU find and coreutils (Linux, WSL).') {
        $lines.Add(("# $line").TrimEnd())
    }
    $lines.Add('')
    $lines.Add(@'
fail() {
  # Says what went wrong and stops: the steps after it are not run
  printf 'error: %s\n' "$1" >&2
  exit 1
}

APPLY=0
for argument in "$@"; do
  if [ "$argument" = "--apply" ]; then
    APPLY=1
  else
    fail "unknown argument $argument (the only one is --apply)"
  fi
done
'@)

    # Finding and choosing the files
    if ($need.Select) {
        $lines.Add('')
        $lines.Add(@'
# The list of files found is kept in a temporary file, removed when the script ends
LISTING=''
trap 'if [ -n "$LISTING" ]; then rm -f -- "$LISTING"; fi' EXIT

reset_filter() {
  # No filter at all: each step then sets the ones it uses. Ages are in seconds, sizes in bytes
  RECURSE=0
  NAME_SET=0
  NAME=''
  EXCEPT_NAME_SET=0
  EXCEPT_NAME=''
  EXTENSIONS_SET=0
  EXTENSIONS=()
  EXCEPT_EXTENSIONS=()
  OLDER_THAN=''
  NEWER_THAN=''
  MIN_SIZE=''
  MAX_SIZE=''
  ORDER=''
  COUNT=''
  FREE_BYTES=''
}

contains() {
  # contains VALUE ITEM...: true when VALUE is one of the items
  local wanted="$1" item
  shift
  for item in "$@"; do
    if [ "$item" = "$wanted" ]; then
      return 0
    fi
  done
  return 1
}

select_files() {
  # select_files ROOT: fills FILES, SIZES (bytes) and TIMES (seconds) with the files that pass the filters
  local root="$1" start="$1"
  FILES=()
  SIZES=()
  TIMES=()
  if [ ! -e "$root" ] && [ ! -L "$root" ]; then
    fail "$root does not exist"
  fi
  case "$start" in
    -*) start="./$start" ;;
  esac

  # Hidden names are skipped with all they hold; a folder, or a link to one, is not a file.
  # A path to one file gives that file
  local tests=(-mindepth 1)
  if [ "$RECURSE" != 1 ]; then
    tests+=(-maxdepth 1)
  fi
  tests+=(-name '.*' -prune -o ! -type d ! -xtype d)
  if [ ! -d "$root" ]; then
    tests=(-maxdepth 0)
  fi
  if [ -z "$LISTING" ]; then
    LISTING=$(mktemp) || fail "no temporary file could be made"
  fi
  find -H "$start" "${tests[@]}" -printf '%s\t%T@\t%p\0' > "$LISTING" || fail "$root could not be read"

  # Order: what was asked, then the path, so that files of the same size or date always come in the same order
  local keys=(-k3)
  case "$ORDER" in
    newest) keys=(-k2,2nr -k3) ;;
    oldest) keys=(-k2,2n -k3) ;;
    largest) keys=(-k1,1nr -k3) ;;
    smallest) keys=(-k1,1n -k3) ;;
  esac

  local now record size rest changed file seconds fraction stamp name lower extension freed=0
  now=$(date +%s%N)
  while IFS= read -r -d '' record; do
    size="${record%%$'\t'*}"
    rest="${record#*$'\t'}"
    changed="${rest%%$'\t'*}"
    file="${rest#*$'\t'}"

    # The last change in nanoseconds: find writes it as seconds.fraction
    seconds="${changed%%.*}"
    fraction=0
    case "$changed" in
      *.*) fraction="${changed#*.}000000000" ;;
    esac
    stamp=$(( seconds * 1000000000 + 10#${fraction:0:9} ))

    # Names and extensions are compared in lower case; the extension is what follows the last dot
    name="${file##*/}"
    lower="${name,,}"
    extension=''
    case "$lower" in
      *.*) extension=".${lower##*.}" ;;
    esac

    if [ "$NAME_SET" = 1 ] && [ "$lower" != "${NAME,,}" ]; then
      continue
    fi
    if [ "$EXCEPT_NAME_SET" = 1 ] && [ "$lower" = "${EXCEPT_NAME,,}" ]; then
      continue
    fi
    if [ "$EXTENSIONS_SET" = 1 ] && ! contains "$extension" "${EXTENSIONS[@]}"; then
      continue
    fi
    if contains "$extension" "${EXCEPT_EXTENSIONS[@]}"; then
      continue
    fi
    if [ -n "$OLDER_THAN" ] && [ ! "$stamp" -lt $(( now - OLDER_THAN * 1000000000 )) ]; then
      continue
    fi
    if [ -n "$NEWER_THAN" ] && [ ! "$stamp" -ge $(( now - NEWER_THAN * 1000000000 )) ]; then
      continue
    fi
    if [ -n "$MIN_SIZE" ] && [ ! "$size" -gt "$MIN_SIZE" ]; then
      continue
    fi
    if [ -n "$MAX_SIZE" ] && [ ! "$size" -lt "$MAX_SIZE" ]; then
      continue
    fi

    # The first ones only, or as many as it takes to free the bytes asked
    if [ -n "$COUNT" ] && [ "${#FILES[@]}" -ge "$COUNT" ]; then
      break
    fi
    if [ -n "$FREE_BYTES" ]; then
      if [ "$freed" -ge "$FREE_BYTES" ]; then
        break
      fi
      freed=$(( freed + size ))
    fi
    FILES+=("$file")
    SIZES+=("$size")
    TIMES+=("$seconds")
  done < <(LC_ALL=C sort -z -t $'\t' "${keys[@]}" "$LISTING")
}
'@)
    }

    if ($need.List) {
        $lines.Add('')
        $lines.Add(@'
list_files() {
  # One line per file: path, size in bytes, last change (UTC)
  local index moment
  for index in "${!FILES[@]}"; do
    moment=$(date -u -d "@${TIMES[$index]}" '+%Y-%m-%dT%H:%M:%SZ') || fail "the date of ${FILES[$index]} could not be read"
    printf '%s\t%s\t%s\n' "${FILES[$index]}" "${SIZES[$index]}" "$moment"
  done
}
'@)
    }

    if ($need.Delete) {
        $lines.Add('')
        $lines.Add(@'
delete_files() {
  # A real deletion: the file does not go to any trash
  local file
  for file in "${FILES[@]}"; do
    if [ "$APPLY" != 1 ]; then
      printf 'would delete: %s\n' "$file"
      continue
    fi
    rm -f -- "$file" || fail "$file could not be deleted"
    printf 'deleted: %s\n' "$file"
  done
}
'@)
    }

    if ($need.Transfer) {
        $lines.Add('')
        $lines.Add(@'
transfer_files() {
  # transfer_files DESTINATION copy|move: into the destination when it is a folder;
  # one file alone may also go to a new name
  local destination="$1" verb="$2" finished="copied" into_folder=0 file target
  if [ "$verb" = "move" ]; then
    finished="moved"
  fi
  if [ -d "$destination" ]; then
    into_folder=1
  fi
  if [ "$into_folder" = 0 ] && [ "${#FILES[@]}" -gt 1 ]; then
    if [ "$APPLY" = 1 ]; then
      fail "$destination is not an existing folder"
    fi
    printf 'warning: %s is not an existing folder yet\n' "$destination" >&2
    into_folder=1
  fi
  for file in "${FILES[@]}"; do
    target="$destination"
    if [ "$into_folder" = 1 ]; then
      target="${destination%/}/${file##*/}"
    fi
    if [ "$APPLY" != 1 ]; then
      printf 'would %s: %s -> %s\n' "$verb" "$file" "$target"
      continue
    fi
    if [ "$verb" = "move" ]; then
      # A move never replaces a file that is already there
      if [ -e "$target" ] || [ -L "$target" ]; then
        fail "$target already exists"
      fi
      mv -T -- "$file" "$target" || fail "$file could not be moved"
    else
      # A copy replaces a file of the same name, and keeps the date of the original
      cp -p -T -- "$file" "$target" || fail "$file could not be copied"
    fi
    printf '%s: %s -> %s\n' "$finished" "$file" "$target"
  done
}
'@)
    }

    if ($need.Rename) {
        $lines.Add('')
        $lines.Add(@'
rename_item() {
  # rename_item SOURCE NEW_NAME: a file or a folder gets a new name in the folder it is in
  local source="$1" new_name="$2" target
  case "$source" in
    */*) target="${source%/*}/$new_name" ;;
    *) target="$new_name" ;;
  esac
  if [ "$APPLY" != 1 ]; then
    printf 'would rename: %s -> %s\n' "$source" "$target"
    return 0
  fi
  if [ ! -e "$source" ] && [ ! -L "$source" ]; then
    fail "$source does not exist"
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    fail "$target already exists"
  fi
  mv -T -- "$source" "$target" || fail "$source could not be renamed"
  printf 'renamed: %s -> %s\n' "$source" "$target"
}
'@)
    }

    if ($need.Create) {
        $lines.Add('')
        $lines.Add(@'
create_item() {
  # create_item PATH file|folder: a new empty file (its folder must exist) or a new folder (with the folders above it)
  local target="$1" kind="$2"
  if [ "$APPLY" != 1 ]; then
    printf 'would create %s: %s\n' "$kind" "$target"
    return 0
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    fail "$target already exists"
  fi
  if [ "$kind" = "folder" ]; then
    mkdir -p -- "$target" || fail "$target could not be created"
  else
    ( set -o noclobber; : > "$target" ) || fail "$target could not be created"
  fi
  printf 'created %s: %s\n' "$kind" "$target"
}
'@)
    }

    # The steps of the plan
    foreach ($step in $Model.Steps) {
        $lines.Add('')
        $lines.Add("# Step $($step.Step): " + (ConvertTo-LambekCodeComment -Text $step.Sentence))
        foreach ($line in Format-LambekCodeBashStep -Step $step) { $lines.Add($line) }
    }
    if ($need.Changes) {
        $lines.Add('')
        $lines.Add('if [ "$APPLY" != 1 ]; then')
        $lines.Add("  printf '%s\n' 'Dry run: nothing was changed. Add --apply to really do it.'")
        $lines.Add('fi')
    }
    $lines.Add('exit 0')

    return (($lines -join "`n") -replace "`r", '') + "`n"
}

function Format-LambekCodeBashStep {
    param([pscustomobject] $Step)

    $quote = { param($text) ConvertTo-LambekCodeLiteral -Value $text -Language Bash }

    if ($Step.Operation -eq 'rename') {
        return "rename_item $(& $quote $Step.Source) $(& $quote $Step.NewName)"
    }
    if ($Step.Operation -eq 'create') {
        $kind = 'file'
        if ($Step.Kind -eq 'Directory') { $kind = 'folder' }
        return "create_item $(& $quote $Step.Path) $kind"
    }

    # The filters that were asked, one per line
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('reset_filter')
    if ($Step.Recurse) { $lines.Add('RECURSE=1') }
    if ($null -ne $Step.Name) { $lines.Add('NAME_SET=1'); $lines.Add("NAME=$(& $quote $Step.Name)") }
    if ($null -ne $Step.Extensions) {
        $lines.Add('EXTENSIONS_SET=1')
        $lines.Add("EXTENSIONS=($(@($Step.Extensions | ForEach-Object { & $quote $_ }) -join ' '))")
    }
    if ($Step.ExceptExtensions.Count -gt 0) { $lines.Add("EXCEPT_EXTENSIONS=($(@($Step.ExceptExtensions | ForEach-Object { & $quote $_ }) -join ' '))") }
    if ($null -ne $Step.ExceptName) { $lines.Add('EXCEPT_NAME_SET=1'); $lines.Add("EXCEPT_NAME=$(& $quote $Step.ExceptName)") }
    if ($null -ne $Step.OlderThanSeconds) { $lines.Add("OLDER_THAN=$($Step.OlderThanSeconds)") }
    if ($null -ne $Step.NewerThanSeconds) { $lines.Add("NEWER_THAN=$($Step.NewerThanSeconds)") }
    if ($null -ne $Step.MinSize) { $lines.Add("MIN_SIZE=$($Step.MinSize)") }
    if ($null -ne $Step.MaxSize) { $lines.Add("MAX_SIZE=$($Step.MaxSize)") }
    if ($null -ne $Step.Order) { $lines.Add("ORDER=$(& $quote $Step.Order)") }
    if ($null -ne $Step.Count) { $lines.Add("COUNT=$($Step.Count)") }
    if ($null -ne $Step.FreeBytes) { $lines.Add("FREE_BYTES=$($Step.FreeBytes)") }
    $lines.Add("select_files $(& $quote $Step.Root)")
    switch ($Step.Operation) {
        'list' { $lines.Add('list_files') }
        'delete' { $lines.Add('delete_files') }
        'copy' { $lines.Add("transfer_files $(& $quote $Step.Destination) copy") }
        'move' { $lines.Add("transfer_files $(& $quote $Step.Destination) move") }
    }
    return $lines.ToArray()
}
