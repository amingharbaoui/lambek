BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
}

Describe 'Get-LambekFileReport' {

    BeforeAll {
        $photo = "$PSScriptRoot/Fixtures/Photo.jpg"
        $folder = Join-Path $TestDrive 'files'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $folder 'notes.txt') -Value 'one', 'two', 'three'

        # A 3 x 2 PNG: signature, then the IHDR chunk with the size
        $png = [byte[]] (0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 3, 0, 0, 0, 2, 8, 2, 0, 0, 0)
        [System.IO.File]::WriteAllBytes((Join-Path $folder 'dot.png'), $png)
    }

    It 'reads the size, the camera, the date, and the GPS position of a photo' {
        $report = InModuleScope Lambek -Parameters @{ Photo = $photo } { Get-LambekFileReport -Path $Photo -Language 'en' }
        $lines = $report -split "`n"
        $lines[0] | Should -BeLike 'Photo.jpg is a JPEG image of 1920 × 1080 pixels, *'
        $lines[1] | Should -Be 'Taken on Aug 12, 2025 with Apple iPhone 13.'
        $lines[2] | Should -Be 'Location: 50.8467° N, 4.3525° E.'
        $lines[3] | Should -Be 'Tell me what to do with it, for example copy, move, or rename it.'
    }

    It 'answers in French' {
        $report = InModuleScope Lambek -Parameters @{ Photo = $photo } { Get-LambekFileReport -Path $Photo -Language 'fr' }
        ($report -split "`n")[1] | Should -Be 'Prise le 12 août 2025 avec Apple iPhone 13.'
    }

    It 'reads a PNG, a text file, a folder, and a missing file' {
        $paths = @((Join-Path $folder 'dot.png'), (Join-Path $folder 'notes.txt'), $folder, (Join-Path $folder 'nope.bin'))
        $lines = (InModuleScope Lambek -Parameters @{ Paths = $paths } { Get-LambekFileReport -Path $Paths -Language 'en' }) -split "`n"
        $lines[0] | Should -BeLike 'dot.png is a PNG image of 3 × 2 pixels, *'
        $lines[1] | Should -BeLike 'notes.txt is a text file of 3 lines, *'
        $lines[2] | Should -BeLike 'files is a folder with 2 items, *'
        $lines[3] | Should -BeLike "I can't find *nope.bin."
        $lines[-1] | Should -Be 'Tell me what to do with them, for example copy, move, or rename them.'
    }

    It 'does not fail on a file that only looks like an image' {
        $broken = Join-Path $folder 'broken.jpg'
        [System.IO.File]::WriteAllBytes($broken, [byte[]] (0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x40, 0x45, 0x78, 0x69, 0x66, 0, 0, 0x49, 0x49))
        $report = InModuleScope Lambek -Parameters @{ Path = $broken } { Get-LambekFileReport -Path $Path -Language 'en' }
        $report | Should -BeLike 'broken.jpg is a JPEG image, *'
    }
}
