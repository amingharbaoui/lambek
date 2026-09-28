function Get-LambekFileReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Path,

        [Parameter(Mandatory)]
        [string] $Language
    )

    $answer = (Get-LambekLexicon -Language $Language).Answer
    $texts = $answer.Files
    $culture = [cultureinfo]::GetCultureInfo($texts.Culture)
    $lines = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $Path) {
        $name = Split-Path -Path $item -Leaf
        if (-not (Test-Path -LiteralPath $item)) {
            $lines.Add(($texts.Missing -f $item))
            continue
        }

        # Folders: how many items, and when they last changed
        $info = Get-Item -LiteralPath $item -Force
        $changed = $info.LastWriteTime.ToString($texts.DateFormat, $culture)
        if ($info.PSIsContainer) {
            $count = @(Get-ChildItem -LiteralPath $item -Force -ErrorAction SilentlyContinue).Count
            $lines.Add(($texts.Folder -f $name, $count, $changed))
            continue
        }

        $size = Format-LambekHumanValue -Name 'Size' -Value ([long] $info.Length) -Units $answer.Units
        $extension = $info.Extension.TrimStart('.').ToLowerInvariant()

        # Images: pixel size from the header, then what the camera wrote
        $image = Get-LambekImageInfo -Path $item
        if ($image) {
            if ($image.Width -gt 0) { $lines.Add(($texts.Image -f $name, $image.Format, $image.Width, $image.Height, $size, $changed)) }
            else { $lines.Add(($texts.ImageNoSize -f $name, $image.Format, $size, $changed)) }

            $taken = $null
            if ($image.Taken) { $taken = $image.Taken.ToString($texts.DateFormat, $culture) }
            if ($taken -and $image.Camera) { $lines.Add(($texts.TakenWith -f $taken, $image.Camera)) }
            elseif ($taken) { $lines.Add(($texts.Taken -f $taken)) }
            elseif ($image.Camera) { $lines.Add(($texts.Camera -f $image.Camera)) }

            if ($null -ne $image.Latitude) {
                $latitude = '{0:0.0000}{2} {1}' -f [math]::Abs($image.Latitude), $(if ($image.Latitude -ge 0) { 'N' } else { 'S' }), [char] 0x00B0
                $longitude = '{0:0.0000}{2} {1}' -f [math]::Abs($image.Longitude), $(if ($image.Longitude -ge 0) { 'E' } else { 'W' }), [char] 0x00B0
                $lines.Add(($texts.Location -f $latitude.Replace(',', '.'), $longitude.Replace(',', '.')))
            }
            continue
        }

        # Text: number of lines
        if ($extension -in $script:TextExtensions -and $info.Length -le 50MB) {
            $count = 0
            foreach ($line in [System.IO.File]::ReadLines($info.FullName)) { $count++ }
            $lines.Add(($texts.Text -f $name, $count, $size, $changed))
            continue
        }

        # PDF: number of pages
        if ($extension -eq 'pdf' -and $info.Length -le 20MB) {
            $content = [System.Text.Encoding]::Latin1.GetString([System.IO.File]::ReadAllBytes($info.FullName))
            $pages = [regex]::Matches($content, '/Type\s*/Page(?![a-zA-Z])').Count
            if ($pages -gt 0) {
                $lines.Add(($texts.Pdf -f $name, $pages, $size, $changed))
                continue
            }
        }

        $kind = $extension.ToUpperInvariant()
        if (-not $kind) { $kind = '?' }
        $lines.Add(($texts.Other -f $name, $kind, $size, $changed))
    }

    # What Lambek can do next
    if ($Path.Count -gt 1) { $lines.Add($texts.NextMany) }
    else { $lines.Add($texts.Next) }
    return $lines -join "`n"
}

function Get-LambekImageInfo {
    param([string] $Path)

    # The first 256 KB hold the header and the EXIF block
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $length = [int] [math]::Min($stream.Length, 262144)
        $bytes = [byte[]]::new($length)
        $read = 0
        while ($read -lt $length) {
            $count = $stream.Read($bytes, $read, $length - $read)
            if ($count -le 0) { break }
            $read += $count
        }
    }
    finally {
        $stream.Dispose()
    }
    if ($read -lt 12) { return $null }

    $result = [ordered]@{ Format = $null; Width = 0; Height = 0; Taken = $null; Camera = $null; Latitude = $null; Longitude = $null }
    $ascii = [System.Text.Encoding]::ASCII

    # PNG, GIF, BMP, WebP
    if ($bytes[0] -eq 0x89 -and $ascii.GetString($bytes, 1, 3) -eq 'PNG' -and $read -ge 24) {
        $result.Format = 'PNG'
        $result.Width = Read-LambekNumber -Bytes $bytes -Offset 16 -Size 4 -BigEndian $true
        $result.Height = Read-LambekNumber -Bytes $bytes -Offset 20 -Size 4 -BigEndian $true
    }
    elseif ($ascii.GetString($bytes, 0, 4) -eq 'GIF8') {
        $result.Format = 'GIF'
        $result.Width = Read-LambekNumber -Bytes $bytes -Offset 6 -Size 2 -BigEndian $false
        $result.Height = Read-LambekNumber -Bytes $bytes -Offset 8 -Size 2 -BigEndian $false
    }
    elseif ($ascii.GetString($bytes, 0, 2) -eq 'BM' -and $read -ge 26) {
        $result.Format = 'BMP'
        $result.Width = [BitConverter]::ToInt32($bytes, 18)
        $result.Height = [math]::Abs([BitConverter]::ToInt32($bytes, 22))
    }
    elseif ($ascii.GetString($bytes, 0, 4) -eq 'RIFF' -and $ascii.GetString($bytes, 8, 4) -eq 'WEBP' -and $read -ge 30) {
        $result.Format = 'WebP'
        $chunk = $ascii.GetString($bytes, 12, 4)
        if ($chunk -eq 'VP8X') {
            $result.Width = 1 + (Read-LambekNumber -Bytes $bytes -Offset 24 -Size 3 -BigEndian $false)
            $result.Height = 1 + (Read-LambekNumber -Bytes $bytes -Offset 27 -Size 3 -BigEndian $false)
        }
        elseif ($chunk -eq 'VP8 ') {
            $result.Width = (Read-LambekNumber -Bytes $bytes -Offset 26 -Size 2 -BigEndian $false) -band 0x3FFF
            $result.Height = (Read-LambekNumber -Bytes $bytes -Offset 28 -Size 2 -BigEndian $false) -band 0x3FFF
        }
        elseif ($chunk -eq 'VP8L') {
            $b0 = [int] $bytes[21]; $b1 = [int] $bytes[22]; $b2 = [int] $bytes[23]; $b3 = [int] $bytes[24]
            $result.Width = 1 + ((($b1 -band 0x3F) -shl 8) -bor $b0)
            $result.Height = 1 + ((($b3 -band 0x0F) -shl 10) -bor ($b2 -shl 2) -bor (($b1 -band 0xC0) -shr 6))
        }
    }
    elseif ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) {
        $result.Format = 'JPEG'
        Read-LambekJpeg -Bytes $bytes -Length $read -Result $result
    }
    else {
        return $null
    }

    return [pscustomobject] $result
}

function Read-LambekNumber {
    param(
        [byte[]] $Bytes,
        [int] $Offset,
        [int] $Size,
        [bool] $BigEndian
    )

    # Unsigned integer of 1 to 4 bytes
    if ($Offset -lt 0 -or $Offset + $Size -gt $Bytes.Length) { throw 'Outside the file header.' }
    [long] $value = 0
    for ($i = 0; $i -lt $Size; $i++) {
        $index = $Offset + $i
        if (-not $BigEndian) { $index = $Offset + $Size - 1 - $i }
        $value = ($value -shl 8) -bor $Bytes[$index]
    }
    return $value
}

function Read-LambekJpeg {
    param(
        [byte[]] $Bytes,
        [int] $Length,
        [System.Collections.IDictionary] $Result
    )

    # Segments: FF marker, then a big-endian length
    $position = 2
    try {
        while ($position + 4 -le $Length) {
            if ($Bytes[$position] -ne 0xFF) { break }
            $marker = $Bytes[$position + 1]
            if ($marker -eq 0xFF) { $position++; continue }
            if ($marker -eq 0x01 -or ($marker -ge 0xD0 -and $marker -le 0xD8)) { $position += 2; continue }
            if ($marker -eq 0xDA -or $marker -eq 0xD9) { break }

            $segment = Read-LambekNumber -Bytes $Bytes -Offset ($position + 2) -Size 2 -BigEndian $true

            # EXIF block: "Exif" then a TIFF header
            if ($marker -eq 0xE1 -and $position + 10 -le $Length -and [System.Text.Encoding]::ASCII.GetString($Bytes, $position + 4, 4) -eq 'Exif') {
                Read-LambekExif -Bytes $Bytes -Start ($position + 10) -Result $Result
            }

            # Frame header: height, then width
            if ($marker -ge 0xC0 -and $marker -le 0xCF -and $marker -notin 0xC4, 0xC8, 0xCC) {
                $Result.Height = Read-LambekNumber -Bytes $Bytes -Offset ($position + 5) -Size 2 -BigEndian $true
                $Result.Width = Read-LambekNumber -Bytes $Bytes -Offset ($position + 7) -Size 2 -BigEndian $true
                break
            }
            $position += 2 + $segment
        }
    }
    catch {
        Write-Verbose "Incomplete JPEG header: $($_.Exception.Message)"
    }
}

function Read-LambekExif {
    param(
        [byte[]] $Bytes,
        [int] $Start,
        [System.Collections.IDictionary] $Result
    )

    try {
        $bigEndian = [System.Text.Encoding]::ASCII.GetString($Bytes, $Start, 2) -eq 'MM'
        $read = { param($Offset, $Size) Read-LambekNumber -Bytes $Bytes -Offset ($Start + $Offset) -Size $Size -BigEndian $bigEndian }

        $main = Read-LambekExifFolder -Offset (& $read 4 4) -Reader $read
        $make = Get-LambekExifText -Bytes $Bytes -Start $Start -Entry $main[0x010F]
        $model = Get-LambekExifText -Bytes $Bytes -Start $Start -Entry $main[0x0110]
        if ($model -and $make -and -not $model.StartsWith($make, [StringComparison]::OrdinalIgnoreCase)) { $model = "$make $model" }
        if ($model -or $make) { $Result.Camera = if ($model) { $model } else { $make } }

        # Date taken, in the EXIF folder
        if ($main.ContainsKey(0x8769)) {
            $details = Read-LambekExifFolder -Offset $main[0x8769].Value -Reader $read
            $date = Get-LambekExifText -Bytes $Bytes -Start $Start -Entry $details[0x9003]
            $taken = [datetime]::MinValue
            if ($date -and [datetime]::TryParseExact($date, 'yyyy:MM:dd HH:mm:ss', [cultureinfo]::InvariantCulture, 'None', [ref] $taken)) {
                $Result.Taken = $taken
            }
        }

        # GPS position: degrees, minutes, seconds, and N/S or E/W
        if ($main.ContainsKey(0x8825)) {
            $gps = Read-LambekExifFolder -Offset $main[0x8825].Value -Reader $read
            $latitude = Get-LambekExifDegree -Entry $gps[2] -Reader $read
            $longitude = Get-LambekExifDegree -Entry $gps[4] -Reader $read
            if ($null -ne $latitude -and $null -ne $longitude) {
                if ((Get-LambekExifText -Bytes $Bytes -Start $Start -Entry $gps[1]) -eq 'S') { $latitude = -$latitude }
                if ((Get-LambekExifText -Bytes $Bytes -Start $Start -Entry $gps[3]) -eq 'W') { $longitude = -$longitude }
                $Result.Latitude = $latitude
                $Result.Longitude = $longitude
            }
        }
    }
    catch {
        Write-Verbose "Incomplete EXIF block: $($_.Exception.Message)"
    }
}

function Read-LambekExifFolder {
    param(
        [long] $Offset,
        [scriptblock] $Reader
    )

    # Entries of 12 bytes: tag, type, count, and the value or where it is
    $sizes = @{ 1 = 1; 2 = 1; 3 = 2; 4 = 4; 5 = 8; 7 = 1; 9 = 4; 10 = 8 }
    $entries = @{}
    $count = & $Reader $Offset 2
    for ($i = 0; $i -lt $count; $i++) {
        $entry = $Offset + 2 + 12 * $i
        $type = [int] (& $Reader ($entry + 2) 2)
        $number = & $Reader ($entry + 4) 4
        $size = 4
        if ($sizes.ContainsKey($type)) { $size = $sizes[$type] * $number }
        $place = $entry + 8
        if ($size -gt 4) { $place = & $Reader ($entry + 8) 4 }

        $value = 0
        if ($type -eq 3) { $value = & $Reader ($entry + 8) 2 }
        elseif ($type -eq 4) { $value = & $Reader ($entry + 8) 4 }
        $entries[[int] (& $Reader $entry 2)] = [pscustomobject]@{ Type = $type; Count = $number; Place = $place; Value = $value }
    }
    return $entries
}

function Get-LambekExifText {
    param(
        [byte[]] $Bytes,
        [int] $Start,
        [object] $Entry
    )

    if (-not $Entry -or $Entry.Type -ne 2 -or $Entry.Count -lt 1) { return $null }
    $from = $Start + $Entry.Place
    if ($from + $Entry.Count -gt $Bytes.Length) { return $null }
    return [System.Text.Encoding]::ASCII.GetString($Bytes, $from, $Entry.Count).Trim([char] 0, ' ')
}

function Get-LambekExifDegree {
    param(
        [object] $Entry,
        [scriptblock] $Reader
    )

    # Three fractions: degrees, minutes, seconds
    if (-not $Entry -or $Entry.Type -ne 5 -or $Entry.Count -lt 3) { return $null }
    $parts = foreach ($i in 0..2) {
        $numerator = & $Reader ($Entry.Place + 8 * $i) 4
        $denominator = & $Reader ($Entry.Place + 8 * $i + 4) 4
        if ($denominator -eq 0) { 0 } else { $numerator / $denominator }
    }
    return $parts[0] + $parts[1] / 60 + $parts[2] / 3600
}
