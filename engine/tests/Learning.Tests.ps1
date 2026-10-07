BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null

    # A small world for the version space: types (.jpg and .png are images, images and audio are media) and folders
    function Get-TestSpace {
        $type = [LambekConceptTree]::new('Type')
        $type.AddChain([string[]] @('.jpg', 'image', 'media'))
        $type.AddChain([string[]] @('.png', 'image', 'media'))
        $type.AddChain([string[]] @('.mp3', 'audio', 'media'))
        $type.AddChain([string[]] @('.txt'))
        $folder = [LambekConceptTree]::new('Folder')
        $folder.AddChain([string[]] @('/p/a', '/p'))
        $folder.AddChain([string[]] @('/q'))
        return [LambekVersionSpace]::new([LambekConceptTree[]] @($type, $folder))
    }

    function Get-BoundaryText {
        param($Space)
        return (@($Space.General | ForEach-Object { $_ -join ' ' } | Sort-Object) -join ' | ')
    }

    # Every fact a Datalog text gives, as sorted lines "name(a,b)"
    function Get-AllFact {
        param([string] $Program)
        InModuleScope Lambek -Parameters @{ Program = $Program } {
            $logic = [LambekLogic]::new()
            foreach ($clause in (ConvertFrom-LambekLogic -Text $Program)) {
                if ($clause.Body.Count -eq 0) { [void] $logic.Add($clause.Head.Name, [string[]] @($clause.Head.Terms | ForEach-Object { [LambekLogic]::Value($_) })) }
                else { $logic.Rules.Add($clause) }
            }
            $logic.Run()
            $lines = foreach ($name in $logic.Rows.Keys) { foreach ($row in $logic.Rows[$name]) { "$name($($row -join ','))" } }
            @($lines | Sort-Object)
        }
    }

    # The macro rule of every derived fact of a Datalog text
    function Get-AllMacro {
        param([string] $Program)
        InModuleScope Lambek -Parameters @{ Program = $Program } {
            $logic = [LambekLogic]::new()
            foreach ($clause in (ConvertFrom-LambekLogic -Text $Program)) {
                if ($clause.Body.Count -eq 0) { [void] $logic.Add($clause.Head.Name, [string[]] @($clause.Head.Terms | ForEach-Object { [LambekLogic]::Value($_) })) }
                else { $logic.Rules.Add($clause) }
            }
            $logic.Run()
            $rules = foreach ($name in $logic.Rows.Keys) {
                foreach ($row in $logic.Rows[$name]) {
                    $clause = [LambekLearning]::Generalise($logic, $name, [string[]] $row)
                    if ($null -ne $clause) { [LambekLearning]::Format($clause) }
                }
            }
            @($rules | Sort-Object -Unique)
        }
    }

    # Every hypothesis of the small world of Get-TestSpace: 8 types by 4 folders
    function Get-EveryHypothesis {
        foreach ($type in '.jpg', '.png', '.mp3', '.txt', 'image', 'audio', 'media', 'any') {
            foreach ($folder in '/p/a', '/p', '/q', 'any') { , [string[]] @($type, $folder) }
        }
    }
}

Describe 'Version space (candidate elimination)' {

    It 'knows the trees: ancestors, covering, lowest common value' {
        $space = Get-TestSpace
        $type = $space.Trees[0]
        ($type.Ancestors('.jpg') -join ' ') | Should -Be '.jpg image media any'
        $type.Covers('media', '.mp3') | Should -BeTrue
        $type.Covers('image', '.mp3') | Should -BeFalse
        $type.Join('.jpg', '.png') | Should -Be 'image'
        $type.Join('.jpg', '.mp3') | Should -Be 'media'
        $type.Join('.jpg', '.txt') | Should -Be 'any'
    }

    It 'moves S up and G down exactly as computed by hand' {
        $space = Get-TestSpace

        # One chosen file: S is that file, G is everything
        $space.AddPositive([string[]] @('.jpg', '/p/a')) | Should -BeTrue
        ($space.Specific -join ' ') | Should -Be '.jpg /p/a'
        Get-BoundaryText $space | Should -Be 'any any'

        # A refused .mp3 of the same folder: only "image" separates it from S
        $space.AddNegative([string[]] @('.mp3', '/p/a')) | Should -BeTrue
        Get-BoundaryText $space | Should -Be 'image any'

        # A refused .png elsewhere: either ".jpg anywhere" or "an image under /p"
        $space.AddNegative([string[]] @('.png', '/q')) | Should -BeTrue
        Get-BoundaryText $space | Should -Be '.jpg any | image /p'
        $space.Converged | Should -BeFalse

        # Between S and G: (.jpg,/p/a) (.jpg,/p) (.jpg,any) (image,/p/a) (image,/p)
        $space.Hypotheses().Count | Should -Be 5

        $space.Classify([string[]] @('.jpg', '/p/a')) | Should -Be 'yes'
        $space.Classify([string[]] @('.jpg', '/q')) | Should -Be 'unknown'
        $space.Classify([string[]] @('.png', '/p/a')) | Should -Be 'unknown'
        $space.Classify([string[]] @('.mp3', '/p')) | Should -Be 'no'
        $space.Classify([string[]] @('.txt', '/q')) | Should -Be 'no'

        # A chosen .png: S becomes "image in /p/a" and ".jpg anywhere" leaves G
        $space.AddPositive([string[]] @('.png', '/p/a')) | Should -BeTrue
        ($space.Specific -join ' ') | Should -Be 'image /p/a'
        Get-BoundaryText $space | Should -Be 'image /p'
        $space.Converged | Should -BeFalse

        # A chosen .jpg directly in /p: S meets G
        $space.AddPositive([string[]] @('.jpg', '/p')) | Should -BeTrue
        ($space.Specific -join ' ') | Should -Be 'image /p'
        $space.Converged | Should -BeTrue
        $space.Hypotheses().Count | Should -Be 1
    }

    It 'asks about the file that splits the hypotheses most evenly' {
        $space = Get-TestSpace
        [void] $space.AddPositive([string[]] @('.jpg', '/p/a'))
        [void] $space.AddNegative([string[]] @('.mp3', '/p/a'))
        [void] $space.AddNegative([string[]] @('.png', '/q'))
        # Of the 5 hypotheses: (.jpg,/q) is covered by 1, (.png,/p/a) by 2, (.png,/p) by 1: min(2,3) = 2 is the best
        $candidates = [System.Collections.Generic.List[string[]]]::new()
        $candidates.Add([string[]] @('.jpg', '/q'))
        $candidates.Add([string[]] @('.png', '/p/a'))
        $candidates.Add([string[]] @('.png', '/p'))
        $space.NextQuestion($candidates) | Should -Be 1
    }

    It 'has no question left when every hypothesis agrees' {
        $space = Get-TestSpace
        [void] $space.AddPositive([string[]] @('.jpg', '/p/a'))
        $candidates = [System.Collections.Generic.List[string[]]]::new()
        $candidates.Add([string[]] @('.jpg', '/p/a'))
        $space.NextQuestion($candidates) | Should -Be -1
    }

    It 'specialises G before any chosen file is known' {
        $space = Get-TestSpace
        # Not the .mp3 of /p/a: "a .txt", "an image", or "in /q" (the largest descriptions that leave it out)
        $space.AddNegative([string[]] @('.mp3', '/p/a')) | Should -BeTrue
        Get-BoundaryText $space | Should -Be '.txt any | any /q | image any'
        $space.Specific | Should -BeNullOrEmpty
        $space.Classify([string[]] @('.mp3', '/p/a')) | Should -Be 'no'
        $space.Classify([string[]] @('.jpg', '/p')) | Should -Be 'unknown'
        # Then a chosen .jpg in /p: only "an image" still covers it
        $space.AddPositive([string[]] @('.jpg', '/p')) | Should -BeTrue
        Get-BoundaryText $space | Should -Be 'image any'
    }

    It 'keeps a description that needs a value met after a refused file' {
        $space = Get-TestSpace
        # ".pdf" is not in the trees yet when the .mp3 is refused; "a .pdf" is then the only description left:
        # the folder cannot help, because /p covers /p/a
        $space.AddNegative([string[]] @('.mp3', '/p/a')) | Should -BeTrue
        $space.AddPositive([string[]] @('.pdf', '/p')) | Should -BeTrue
        $space.Collapsed | Should -BeFalse
        ($space.Specific -join ' ') | Should -Be '.pdf /p'
        Get-BoundaryText $space | Should -Be '.pdf any'
        # (.pdf,/p) and (.pdf,any)
        $space.Hypotheses().Count | Should -Be 2
    }

    It 'gives the same S and G whatever the order of the examples' {
        $steps = '+.jpg /p/a', '-.mp3 /p/a', '-.png /q', '+.png /p/a', '-.txt /p'
        $orders = @(0, 1, 2, 3, 4), @(4, 3, 2, 1, 0), @(1, 2, 4, 0, 3), @(3, 0, 4, 2, 1)
        $seen = foreach ($order in $orders) {
            $space = Get-TestSpace
            foreach ($index in $order) {
                $values = [string[]] @($steps[$index].Substring(1) -split ' ')
                if ($steps[$index].StartsWith('+')) { [void] $space.AddPositive($values) }
                else { [void] $space.AddNegative($values) }
            }
            ($space.Specific -join ' ') + ' ; ' + (Get-BoundaryText $space)
        }
        # S = image in /p/a; G: the refused .png in /q and .txt in /p leave "an image under /p"
        @($seen | Select-Object -Unique) | Should -Be @('image /p/a ; image /p')
    }

    It 'holds exactly the hypotheses consistent with the examples (checked against every hypothesis)' {
        # 12 files (4 types in 3 folders), labelled by each of the 32 possible descriptions in turn;
        # after 3, 6, 9 and 12 labelled files the version space is compared with a plain enumeration
        $every = @(Get-EveryHypothesis)
        $files = @(foreach ($type in '.jpg', '.mp3', '.png', '.txt') { foreach ($folder in '/p', '/q', '/p/a') { , [string[]] @($type, $folder) } })
        $world = Get-TestSpace

        # Which hypothesis covers which file, and which hypothesis covers which other one, asked once
        $coversFile = @{}
        $coversOther = @{}
        for ($h = 0; $h -lt $every.Count; $h++) {
            for ($f = 0; $f -lt $files.Count; $f++) { $coversFile["$h,$f"] = $world.Covers($every[$h], $files[$f]) }
            for ($o = 0; $o -lt $every.Count; $o++) { $coversOther["$h,$o"] = ($h -ne $o) -and $world.Covers($every[$h], $every[$o]) }
        }

        $wrong = [System.Collections.Generic.List[string]]::new()
        $checked = 0
        for ($target = 0; $target -lt $every.Count; $target++) {
            $space = Get-TestSpace
            $positive = 0
            for ($given = 1; $given -le $files.Count; $given++) {
                if ($coversFile["$target,$($given - 1)"]) {
                    [void] $space.AddPositive($files[$given - 1])
                    $positive++
                }
                else { [void] $space.AddNegative($files[$given - 1]) }
                if ($given % 3 -ne 0 -or $positive -eq 0) { continue }
                $label = "target $($every[$target] -join ' ') after $given files"
                if ($space.Collapsed) { $wrong.Add("$label collapsed") }

                # By enumeration: the hypotheses that agree with the target on every file given so far
                $consistent = @(for ($h = 0; $h -lt $every.Count; $h++) {
                        $fits = $true
                        for ($f = 0; $f -lt $given; $f++) {
                            if ($coversFile["$h,$f"] -ne $coversFile["$target,$f"]) { $fits = $false; break }
                        }
                        if ($fits) { $h }
                    })
                $expected = @($consistent | ForEach-Object { $every[$_] -join ' ' } | Sort-Object) -join ' | '
                $found = @($space.Hypotheses() | ForEach-Object { $_ -join ' ' } | Sort-Object) -join ' | '
                if ($found -ne $expected) { $wrong.Add("$label hypotheses: $found instead of $expected") }
                if ($consistent -notcontains $target) { $wrong.Add("$label lost its target") }

                # G: the consistent hypotheses no other consistent one covers; S: the one that covers no other
                $maximal = @(foreach ($one in $consistent) {
                        $covered = $false
                        foreach ($other in $consistent) { if ($coversOther["$other,$one"]) { $covered = $true; break } }
                        if (-not $covered) { $every[$one] -join ' ' }
                    })
                $boundary = Get-BoundaryText $space
                if ($boundary -ne (@($maximal | Sort-Object) -join ' | ')) { $wrong.Add("$label G: $boundary") }
                $minimal = @(foreach ($one in $consistent) {
                        $covers = $false
                        foreach ($other in $consistent) { if ($coversOther["$one,$other"]) { $covers = $true; break } }
                        if (-not $covers) { $every[$one] -join ' ' }
                    })
                if (($minimal -join ' | ') -ne ($space.Specific -join ' ')) { $wrong.Add("$label S: $($space.Specific -join ' ')") }

                # Classify: yes when all agree, no when none covers, unknown otherwise
                for ($f = 0; $f -lt $files.Count; $f++) {
                    $yes = @($consistent | Where-Object { $coversFile["$_,$f"] }).Count
                    $answer = 'unknown'
                    if ($yes -eq $consistent.Count) { $answer = 'yes' }
                    elseif ($yes -eq 0) { $answer = 'no' }
                    $said = $space.Classify($files[$f])
                    if ($said -ne $answer) { $wrong.Add("$label file $($files[$f] -join ' '): $said instead of $answer") }
                }
                $checked++
            }
        }
        $wrong | Should -BeNullOrEmpty
        # 32 targets, 4 checks each, less those before the first chosen file
        $checked | Should -BeGreaterThan 60
    }

    It 'reports the collapse instead of hiding it: <Name>' -ForEach @(
        @{ Name = 'the same file chosen then refused'; Steps = @('+.jpg /p/a', '-.jpg /p/a') }
        @{ Name = 'the same file refused then chosen'; Steps = @('-.jpg /p/a', '+.jpg /p/a') }
        @{ Name = 'a refused file between two chosen ones'; Steps = @('+.jpg /p', '+.mp3 /q', '-.png /p/a') }
        @{ Name = 'a chosen file that needs a refused one'; Steps = @('+.jpg /p', '-.png /p/a', '+.mp3 /q') }
    ) {
        $space = Get-TestSpace
        $last = $true
        foreach ($step in $Steps) {
            $values = [string[]] @($step.Substring(1) -split ' ')
            if ($step.StartsWith('+')) { $last = $space.AddPositive($values) }
            else { $last = $space.AddNegative($values) }
        }
        $last | Should -BeFalse
        $space.Collapsed | Should -BeTrue
        $space.CollapseReason | Should -Not -BeNullOrEmpty
        $space.Converged | Should -BeFalse
        $space.Hypotheses().Count | Should -Be 0
    }

    It 'keeps every hypothesis consistent with every example' {
        $space = Get-TestSpace
        [void] $space.AddPositive([string[]] @('.jpg', '/p/a'))
        [void] $space.AddNegative([string[]] @('.txt', '/p/a'))
        [void] $space.AddPositive([string[]] @('.mp3', '/p'))
        [void] $space.AddNegative([string[]] @('.png', '/q'))
        $space.Collapsed | Should -BeFalse
        foreach ($hypothesis in $space.Hypotheses()) {
            foreach ($positive in $space.Positives) { $space.Covers($hypothesis, $positive) | Should -BeTrue }
            foreach ($negative in $space.Negatives) { $space.Covers($hypothesis, $negative) | Should -BeFalse }
        }
        # S = (media, /p); G = (media, /p): the refused .png in /q forces the folder, the refused .txt forces the type
        ($space.Specific -join ' ') | Should -Be 'media /p'
        Get-BoundaryText $space | Should -Be 'media /p'
        $space.Converged | Should -BeTrue
    }
}

Describe 'Size principle' {

    It 'gives 27/28 to a hypothesis of size 1 against one of size 3 after 3 examples' {
        # Weights 1/1^3 = 1 and 1/3^3 = 1/27; total 28/27; so 27/28 and 1/28
        $posterior = [LambekSizePrinciple]::Posterior([int[]] @(1, 3), 3, $null)
        $posterior[0].Exact() | Should -Be '27/28'
        $posterior[1].Exact() | Should -Be '1/28'
    }

    It 'multiplies by the prior' {
        # Sizes 2 and 4, 2 examples, priors 1 and 3: weights 1/4 and 3/16; total 7/16; so 4/7 and 3/7
        $priors = [LambekRational[]] @([LambekRational]::new(1, 1), [LambekRational]::new(3, 1))
        $posterior = [LambekSizePrinciple]::Posterior([int[]] @(2, 4), 2, $priors)
        $posterior[0].Exact() | Should -Be '4/7'
        $posterior[1].Exact() | Should -Be '3/7'
    }

    It 'is the prior again with no example, and gives nothing to a hypothesis that covers nothing' {
        $posterior = [LambekSizePrinciple]::Posterior([int[]] @(5, 50, 0), 0, $null)
        $posterior[0].Exact() | Should -Be '1/2'
        $posterior[1].Exact() | Should -Be '1/2'
        $posterior[2].Exact() | Should -Be '0'
        { [LambekSizePrinciple]::Posterior([int[]] @(0, 0), 2, $null) } | Should -Throw
    }

    It 'stays exact with numbers no double can hold' {
        # Sizes 1 and 10 after 40 examples: 10^40 / (10^40 + 1)
        $posterior = [LambekSizePrinciple]::Posterior([int[]] @(1, 10), 40, $null)
        $posterior[0].Exact() | Should -Be ('1' + ('0' * 40) + '/1' + ('0' * 39) + '1')
        ($posterior[0] + $posterior[1]).Exact() | Should -Be '1'
    }

    It 'makes "jpg files" far more likely than "images" or "all files" after three .jpg' {
        # 8 files: 3 .jpg, 1 .png, 2 .mp3, 2 .txt. Sizes: .jpg 3, image 4, media 6, any 8; n = 3.
        # Weights 1/27, 1/64, 1/216, 1/512 = (512, 216, 64, 27) / 13824; total 819.
        $found = Find-LambekConcept -Attribute Type -Positive '/p/a.jpg', '/p/b.jpg', '/p/c.jpg' `
            -Candidate '/p/d.png', '/p/e.mp3', '/p/f.mp3', '/p/g.txt', '/p/h.txt'
        ($found.Hypotheses.Text -join ' | ') | Should -Be 'Type=.jpg | Type=image | Type=media | any'
        ($found.Hypotheses.Size -join ' ') | Should -Be '3 4 6 8'
        ($found.Hypotheses.Probability -join ' ') | Should -Be '512/819 24/91 64/819 3/91'
        [math]::Round($found.Hypotheses[0].ProbabilityValue, 6) | Should -Be 0.625153
        [math]::Round(($found.Hypotheses.ProbabilityValue | Measure-Object -Sum).Sum, 9) | Should -Be 1
    }
}

Describe 'Find-LambekConcept' {

    It 'returns S, G and the question for three .jpg' {
        $found = Find-LambekConcept -Attribute Type -Positive '/p/a.jpg', '/p/b.jpg', '/p/c.jpg' `
            -Candidate '/p/d.png', '/p/e.mp3', '/p/f.mp3', '/p/g.txt', '/p/h.txt'
        $found.S['Type'] | Should -Be '.jpg'
        $found.SText | Should -Be 'Type=.jpg'
        $found.GText | Should -Be @('any')
        $found.Converged | Should -BeFalse
        $found.Collapsed | Should -BeFalse
        # .png is covered by 3 of the 4 hypotheses (min 1), .mp3 by 2 (min 2): the .mp3 is the question
        $found.Question | Should -Be '/p/e.mp3'
        ($found.Answers.Answer | Select-Object -Unique) | Should -Be 'unknown'
    }

    It 'uses folders and refused files' {
        # S = image in /p. The refused .mp3 leaves G = image (the folder cannot separate it: it is in /p too).
        # Universe of 7: image in /p = a, b, d (3); image = these and h (4). n = 2: 1/9 against 1/16 = 16/25 and 9/25
        $found = Find-LambekConcept -Attribute Type, Folder -Positive '/p/a.jpg', '/p/b.png' -Negative '/p/e.mp3' `
            -Candidate '/p/d.gif', '/q/f.mp4', '/p/g.txt', '/q/h.jpg'
        $found.SText | Should -Be 'Type=image, Folder=/p'
        $found.GText | Should -Be @('Type=image')
        ($found.Hypotheses.Text -join ' | ') | Should -Be 'Type=image, Folder=/p | Type=image'
        ($found.Hypotheses.Probability -join ' ') | Should -Be '16/25 9/25'
        $answers = @{}
        foreach ($answer in $found.Answers) { $answers[$answer.File] = $answer.Answer }
        $answers['/p/d.gif'] | Should -Be 'yes'
        $answers['/q/f.mp4'] | Should -Be 'no'
        $answers['/p/g.txt'] | Should -Be 'no'
        $answers['/q/h.jpg'] | Should -Be 'unknown'
        $found.Question | Should -Be '/q/h.jpg'
    }

    It 'converges after the answer to its question' {
        $found = Find-LambekConcept -Attribute Type, Folder -Positive '/p/a.jpg', '/p/b.png' -Negative '/p/e.mp3', '/q/h.jpg' `
            -Candidate '/p/d.gif', '/q/f.mp4'
        $found.Converged | Should -BeTrue
        $found.SText | Should -Be 'Type=image, Folder=/p'
        $found.Hypotheses.Count | Should -Be 1
        $found.Hypotheses[0].Probability | Should -Be '1'
        $found.Question | Should -BeNullOrEmpty
    }

    It 'learns a size class from file descriptions' {
        # S = video of 1 MB or more; the refused 5 KB video leaves only the size to separate it.
        # Sizes over the 5 files: video and big 2, media and big 3, big 4. n = 2: (1/4, 1/9, 1/16) = (36, 16, 9) / 61
        $found = Find-LambekConcept -Attribute Type, Folder, Size, Name `
            -Positive @{ Path = '/v/a.mp4'; Length = 200MB }, @{ Path = '/w/b.mkv'; Length = 5MB } `
            -Negative @{ Path = '/v/c.mp4'; Length = 5KB } `
            -Candidate @{ Path = '/v/d.mp3'; Length = 3MB }, @{ Path = '/v/e.txt'; Length = 2MB }
        $found.SText | Should -Be 'Type=video, Size=1 MB or more'
        $found.GText | Should -Be @('Size=1 MB or more')
        ($found.Hypotheses.Text -join ' | ') | Should -Be 'Type=video, Size=1 MB or more | Type=media, Size=1 MB or more | Size=1 MB or more'
        ($found.Hypotheses.Probability -join ' ') | Should -Be '36/61 16/61 9/61'
        $found.Question['Path'] | Should -Be '/v/d.mp3'
    }

    It 'counts a chosen file given twice once' {
        # 2 chosen files, not 3. Sizes: .jpg, image and media 2 each, any 3; n = 2:
        # weights 1/4, 1/4, 1/4, 1/9 = (9, 9, 9, 4) / 36; total 31
        $found = Find-LambekConcept -Attribute Type -Positive '/p/a.jpg', '/p/b.jpg', '/p/a.jpg' -Candidate '/p/c.txt'
        ($found.Hypotheses.Text -join ' | ') | Should -Be 'Type=.jpg | Type=image | Type=media | any'
        ($found.Hypotheses.Probability -join ' ') | Should -Be '9/31 9/31 9/31 4/31'
    }

    It 'reports a collapse' {
        $found = Find-LambekConcept -Attribute Type -Positive '/p/a.jpg' -Negative '/p/b.jpg'
        $found.Collapsed | Should -BeTrue
        $found.Reason | Should -Not -BeNullOrEmpty
        $found.Converged | Should -BeFalse
        $found.Hypotheses.Count | Should -Be 0
    }

    It 'describes a file by type, folder, size, age and name' {
        InModuleScope Lambek {
            $now = [datetime] '2026-01-10T00:00:00'
            $file = @{ Path = 'C:\Users\me\Pictures\IMG_001.JPG'; Length = 5KB; LastWriteTime = [datetime] '2026-01-07T00:00:00' }
            $instance = ConvertTo-LambekFileInstance -File $file -KindOf @{ '.jpg' = 'image' } -ParentOf @{ image = 'media' } -Now $now
            ($instance.Chains.Type -join ' < ') | Should -Be '.jpg < image < media'
            ($instance.Chains.Folder -join ' < ') | Should -Be 'C:\Users\me\Pictures < C:\Users\me < C:\Users < C:\'
            ($instance.Chains.Size -join ' < ') | Should -Be 'under 10 KB < under 1 MB'
            ($instance.Chains.Age -join ' < ') | Should -Be '1 to 7 days < under 30 days'
            ($instance.Chains.Name -join ' < ') | Should -Be 'IMG_001 < img*'

            $old = @{ Path = '/home/me/notes'; Length = 300MB; LastWriteTime = [datetime] '2024-01-01T00:00:00' }
            $instance = ConvertTo-LambekFileInstance -File $old -Now $now
            ($instance.Chains.Type -join ' < ') | Should -Be '(no extension)'
            ($instance.Chains.Folder -join ' < ') | Should -Be '/home/me < /home'
            ($instance.Chains.Size -join ' < ') | Should -Be '100 MB or more < 1 MB or more'
            ($instance.Chains.Age -join ' < ') | Should -Be '1 year or more < 30 days or more'
        }
    }

    It 'takes the kinds of the packs: image, video and audio are media' {
        $found = Find-LambekConcept -Attribute Type -Positive 'a.jpg', 'b.mp4'
        $found.SText | Should -Be 'Type=media'
    }

    It 'learns a first word of the name' {
        $found = Find-LambekConcept -Attribute Type, Name -Positive 'IMG_001.jpg', 'IMG_002.jpg' -Negative 'DSC_001.jpg' -Candidate 'IMG_003.png'
        $found.SText | Should -Be 'Type=.jpg, Name=img*'
        $found.GText | Should -Be @('Name=img*')
        $found.Answers[0].Answer | Should -Be 'unknown'
    }
}

Describe 'Rename by example: the pieces' {

    It 'splits a name from its extension' {
        $stem = ''
        $extension = ''
        [LambekRename]::Split('IMG_001.jpg', [ref] $stem, [ref] $extension)
        "$stem|$extension" | Should -Be 'IMG_001|.jpg'
        [LambekRename]::Split('archive.tar.gz', [ref] $stem, [ref] $extension)
        "$stem|$extension" | Should -Be 'archive.tar|.gz'
        [LambekRename]::Split('.gitignore', [ref] $stem, [ref] $extension)
        "$stem|$extension" | Should -Be '.gitignore|'
        [LambekRename]::Split('README', [ref] $stem, [ref] $extension)
        "$stem|$extension" | Should -Be 'README|'
    }

    It 'finds the place <Key> of IMG_20240315_123456 at <Expected>' -ForEach @(
        @{ Key = 'Start'; Expected = 0 }
        @{ Key = 'End'; Expected = 19 }
        @{ Key = 'Digits(1).Start'; Expected = 4 }
        @{ Key = 'Digits(1).End'; Expected = 12 }
        @{ Key = 'Digits(-1).Start'; Expected = 13 }
        @{ Key = 'Digits(1).Start+4'; Expected = 8 }
        @{ Key = 'Digits(1).End-2'; Expected = 10 }
        @{ Key = 'Letters(1).End'; Expected = 3 }
        @{ Key = 'Alnum(2).Start'; Expected = 4 }
        @{ Key = 'Upper(-1).End'; Expected = 3 }
        @{ Key = 'Char(4)'; Expected = 4 }
        @{ Key = 'Char(-6)'; Expected = 13 }
    ) {
        $text = 'IMG_20240315_123456'
        $places = [LambekRenamePosition]::At($text, $Expected)
        $place = $places | Where-Object { $_.Key -ceq $Key }
        $place | Should -Not -BeNullOrEmpty
        $place.Resolve($text) | Should -Be $Expected
    }

    It 'has no place where the name has no such run' {
        [LambekRenamePosition]::Token('Digits', 3, 'Start', 0).Resolve('IMG_20240315_123456') | Should -Be -1
        [LambekRenamePosition]::Token('Digits', 1, 'Start', 9).Resolve('IMG_20240315_123456') | Should -Be -1
        [LambekRenamePosition]::Token('Digits', 1, 'Start', 0).Resolve('notes') | Should -Be -1
        [LambekRenamePosition]::Character(-6).Resolve('abc') | Should -Be -1
    }

    It 'prices the places: <Key> costs <Cost>' -ForEach @(
        # |k| (3 at most), +1 from the end, +1 for Alnum, Upper and Lower, +3 inside the run; 8 for a fixed count
        @{ Key = 'Digits(1).Start'; Cost = 1 }
        @{ Key = 'Digits(-1).Start'; Cost = 2 }
        @{ Key = 'Alnum(2).Start'; Cost = 3 }
        @{ Key = 'Digits(1).Start+4'; Cost = 4 }
        @{ Key = 'Char(4)'; Cost = 8 }
        @{ Key = 'Start'; Cost = 0 }
    ) {
        $index = 4
        if ($Key -eq 'Start') { $index = 0 }
        if ($Key -eq 'Digits(1).Start+4') { $index = 8 }
        if ($Key -eq 'Digits(-1).Start') { $index = 13 }
        $place = [LambekRenamePosition]::At('IMG_20240315_123456', $index) | Where-Object { $_.Key -ceq $Key }
        $place.Cost | Should -Be $Cost
    }

    It 'prices the pieces' {
        # Const: 4 + 13 per letter or digit + 4 per other character
        [LambekRenameAtom]::Const('holiday').Cost | Should -Be 95
        [LambekRenameAtom]::Const('holiday_').Cost | Should -Be 99
        [LambekRenameAtom]::Const(' - ').Cost | Should -Be 16
        # Counter: 12 + 8 per digit of the start
        [LambekRenameAtom]::Counter(1, 3).Cost | Should -Be 20
        [LambekRenameAtom]::Counter(2024, 1).Cost | Should -Be 44
        [LambekRenameAtom]::Date('yyyy-MM-dd').Cost | Should -Be 16
        [LambekRenameAtom]::Extension('').Cost | Should -Be 8
        [LambekRenameAtom]::Extension('Lower').Cost | Should -Be 11
        # Substr: 10 + its places; +3 for a change
        $from = [LambekRenamePosition]::Token('Digits', 1, 'Start', 0)
        $to = [LambekRenamePosition]::Edge('End')
        [LambekRenameAtom]::Substr($from, $to, '').Cost | Should -Be 11
        [LambekRenameAtom]::Substr($from, $to, 'Upper').Cost | Should -Be 14
        [LambekRenameAtom]::Number($from, $to, 3).Cost | Should -Be 14
    }

    It 'evaluates the pieces' {
        $start = [LambekRenamePosition]::Edge('Start')
        $end = [LambekRenamePosition]::Edge('End')
        $digits = [LambekRenamePosition]::Token('Digits', 1, 'Start', 0)
        [LambekRenameAtom]::Counter(1, 3).Evaluate('x', '', 6, $null) | Should -Be '007'
        [LambekRenameAtom]::Counter(9, 1).Evaluate('x', '', 1, $null) | Should -Be '10'
        [LambekRenameAtom]::Substr($digits, $end, '').Evaluate('IMG_0042', '.jpg', 0, $null) | Should -Be '0042'
        [LambekRenameAtom]::Number($digits, $end, 1).Evaluate('IMG_0042', '.jpg', 0, $null) | Should -Be '42'
        [LambekRenameAtom]::Number($digits, $end, 3).Evaluate('Scan 3', '.pdf', 0, $null) | Should -Be '003'
        [LambekRenameAtom]::Number($digits, $end, 1).Evaluate('v000', '', 0, $null) | Should -Be '0'
        [LambekRenameAtom]::Number($start, $end, 3).Evaluate('v12', '', 0, $null) | Should -BeNullOrEmpty
        [LambekRenameAtom]::Substr($digits, $end, '').Evaluate('notes', '.txt', 0, $null) | Should -BeNullOrEmpty
        [LambekRenameAtom]::Substr($start, $end, 'Title').Evaluate('hello wORLD-foo', '', 0, $null) | Should -Be 'Hello World-Foo'
        [LambekRenameAtom]::Substr($start, $end, 'Upper').Evaluate('abc', '', 0, $null) | Should -Be 'ABC'
        [LambekRenameAtom]::Extension('Lower').Evaluate('a', '.JPG', 0, $null) | Should -Be '.jpg'
        [LambekRenameAtom]::Date('yyyy-MM-dd').Evaluate('a', '', 0, [datetime] '2024-03-15T10:11:12') | Should -Be '2024-03-15'
        [LambekRenameAtom]::Date('HHmmss').Evaluate('a', '', 0, [datetime] '2024-03-15T10:11:12') | Should -Be '101112'
        [LambekRenameAtom]::Date('yyyy').Evaluate('a', '', 0, $null) | Should -BeNullOrEmpty
    }

    It 'reports empty names, separators, duplicates and names still in use' {
        $names = [string[]] @('a.txt', 'b.txt', 'c.txt', 'd.txt', 'e.txt', 'f.txt')
        # The fifth file has no new name at all (a cast to [string[]] would turn $null into '')
        $targets = [string[]]::new(6)
        $targets[0] = 'x.txt'
        $targets[1] = 'X.TXT'
        $targets[2] = ''
        $targets[3] = 'sub/y.txt'
        $targets[5] = 'a.txt'
        $issues = [LambekRename]::Check($names, $targets)
        (@($issues | ForEach-Object { "$($_.Kind):$($_.Name)" }) -join ' ') | Should -Be 'Duplicate:b.txt Empty:c.txt Separator:d.txt Undefined:e.txt Order:f.txt'
        ($issues | Where-Object Kind -EQ 'Duplicate').Other | Should -Be 'a.txt'
        ($issues | Where-Object Kind -EQ 'Order').Other | Should -Be 'a.txt'
        [LambekRename]::Check([string[]] @('a.txt', 'b.txt'), [string[]] @('a.txt', 'c.txt')).Count | Should -Be 0
    }
}

Describe 'Find-LambekRenameRule' {

    It 'finds the cheapest program for IMG_001.jpg -> holiday_001.jpg, and its rival' {
        $found = Find-LambekRenameRule -Example @{ 'IMG_001.jpg' = 'holiday_001.jpg' } -Name 'IMG_001.jpg', 'IMG_002.jpg', 'IMG_007.jpg'
        $found.Found | Should -BeTrue
        # Const("holiday") 95 + Substr(Letters(1).End, End) 11 + Extension 8 = 114
        $found.Program | Should -Be 'Const("holiday") + Substr(Letters(1).End, End) + Extension'
        $found.Cost | Should -Be 114
        $found.Atoms.Count | Should -Be 3
        $found.Atoms[0].Kind | Should -Be 'Const'
        $found.Atoms[0].Value | Should -Be 'holiday'
        $found.Atoms[1].From | Should -Be 'Letters(1).End'
        $found.Atoms[1].To | Should -Be 'End'
        ($found.Renames.NewName -join ' ') | Should -Be 'holiday_001.jpg holiday_002.jpg holiday_007.jpg'
        $found.IsSafe | Should -BeTrue

        # The rival: a counter. Const("holiday_") 99 + Counter(1, 3) 20 + Extension 8 = 127.
        # Both give holiday_002.jpg to the second file; they part on the third
        $found.Ambiguous | Should -BeTrue
        $found.Alternative | Should -Be 'Const("holiday_") + Counter(1, 3) + Extension'
        $found.AlternativeCost | Should -Be 127
        $found.Question.Name | Should -Be 'IMG_007.jpg'
        $found.Question.First | Should -Be 'holiday_007.jpg'
        $found.Question.Second | Should -Be 'holiday_003.jpg'
    }

    It 'takes the answer as a second example and settles on the counter' {
        $example = [ordered]@{ 'IMG_001.jpg' = 'holiday_001.jpg'; 'IMG_007.jpg' = 'holiday_003.jpg' }
        $found = Find-LambekRenameRule -Example $example -Name 'IMG_001.jpg', 'IMG_002.jpg', 'IMG_007.jpg', 'DSC_0042.JPG'
        $found.Program | Should -Be 'Const("holiday_") + Counter(1, 3) + Extension'
        ($found.Renames.NewName -join ' ') | Should -Be 'holiday_001.jpg holiday_002.jpg holiday_003.jpg holiday_004.JPG'
        $found.IsSafe | Should -BeTrue
    }

    It 'renames as meant: <Title>' -ForEach @(
        @{
            Title   = 'lower case, extension included'
            Example = [ordered]@{ 'IMG_0001.JPG' = 'img_0001.jpg' }
            Name    = 'IMG_0001.JPG', 'IMG_0002.JPG', 'DSC_0003.JPG'
            Program = 'Lower(Substr(Start, End)) + Lower(Extension)'
            Cost    = 24
            New     = 'img_0001.jpg', 'img_0002.jpg', 'dsc_0003.jpg'
        }
        @{
            Title   = 'upper case'
            Example = [ordered]@{ 'notes.txt' = 'NOTES.TXT' }
            Name    = 'notes.txt', 'todo.txt'
            Program = 'Upper(Substr(Start, End)) + Upper(Extension)'
            Cost    = 24
            New     = 'NOTES.TXT', 'TODO.TXT'
        }
        @{
            Title   = 'title case of each word'
            Example = [ordered]@{ 'report final.DOCX' = 'Report Final.docx' }
            Name    = 'report final.DOCX', 'meeting notes.DOCX', 'x.PDF'
            Program = 'Title(Substr(Start, End)) + Lower(Extension)'
            Cost    = 24
            New     = 'Report Final.docx', 'Meeting Notes.docx', 'X.pdf'
        }
        @{
            Title   = 'a suffix before the extension'
            Example = [ordered]@{ 'notes.txt' = 'notes_backup.txt' }
            Name    = 'notes.txt', 'todo.txt', 'a.b.txt'
            Program = 'Substr(Start, End) + Const("_backup") + Extension'
            Cost    = 104
            New     = 'notes_backup.txt', 'todo_backup.txt', 'a.b_backup.txt'
        }
        @{
            Title   = 'a prefix'
            Example = [ordered]@{ 'report.txt' = 'old_report.txt' }
            Name    = 'report.txt', 'budget.txt'
            Program = 'Const("old_") + Substr(Start, End) + Extension'
            Cost    = 65
            New     = 'old_report.txt', 'old_budget.txt'
        }
        @{
            Title   = 'a new extension'
            Example = [ordered]@{ 'photo.jpeg' = 'photo.jpg' }
            Name    = 'photo.jpeg', 'b.jpeg', 'c.png'
            Program = 'Substr(Start, End) + Const(".jpg")'
            Cost    = 57
            New     = 'photo.jpg', 'b.jpg', 'c.jpg'
        }
        @{
            Title   = 'the date of a camera name cut into year-month-day'
            Example = [ordered]@{ 'IMG_20240315_123456.jpg' = '2024-03-15_123456.jpg' }
            Name    = 'IMG_20240315_123456.jpg', 'IMG_20231201_080000.jpg', 'VID_20240101_000001.mp4'
            Program = 'Substr(Digits(1).Start, Digits(1).End-4) + Const("-") + Substr(Digits(1).End-4, Digits(1).End-2) + Const("-") + Substr(Digits(1).End-2, End) + Extension'
            Cost    = 71
            New     = '2024-03-15_123456.jpg', '2023-12-01_080000.jpg', '2024-01-01_000001.mp4'
        }
        @{
            Title   = 'number first, then the lower-cased camera prefix'
            Example = [ordered]@{ 'DSC_0042.JPG' = '0042_dsc.jpg' }
            Name    = 'DSC_0042.JPG', 'DSC_0043.JPG', 'P1000123.JPG'
            Program = 'Substr(Digits(1).Start, End) + Const("_") + Lower(Substr(Start, Letters(1).End)) + Lower(Extension)'
            Cost    = 44
            New     = '0042_dsc.jpg', '0043_dsc.jpg', '1000123_p.jpg'
        }
        @{
            Title   = 'two parts swapped'
            Example = [ordered]@{ 'Invoice 2024-03.pdf' = '2024-03 Invoice.pdf' }
            Name    = 'Invoice 2024-03.pdf', 'Invoice 2024-04.pdf', 'Receipt 2023-12.pdf'
            Program = 'Substr(Digits(1).Start, End) + Const(" ") + Substr(Start, Letters(1).End) + Extension'
            Cost    = 38
            New     = '2024-03 Invoice.pdf', '2024-04 Invoice.pdf', '2023-12 Receipt.pdf'
        }
        @{
            Title   = 'surname_name to Name Surname'
            Example = [ordered]@{ 'smith_john.docx' = 'John Smith.docx' }
            Name    = 'smith_john.docx', 'doe_jane.docx'
            Program = 'Title(Substr(Letters(-1).Start, End)) + Const(" ") + Title(Substr(Start, Letters(1).End)) + Extension'
            Cost    = 45
            New     = 'John Smith.docx', 'Jane Doe.docx'
        }
        @{
            Title   = 'a number padded with zeros'
            Example = [ordered]@{ 'chapter1.md' = 'chapter-01.md' }
            Name    = 'chapter1.md', 'chapter2.md', 'chapter10.md'
            Program = 'Substr(Start, Digits(1).Start) + Const("-") + Number(Substr(Digits(1).Start, End), 2) + Extension'
            Cost    = 41
            New     = 'chapter-01.md', 'chapter-02.md', 'chapter-10.md'
        }
        @{
            Title   = 'a number without its zeros'
            Example = [ordered]@{ 'IMG_0042.jpg' = 'IMG_42.jpg' }
            Name    = 'IMG_0042.jpg', 'IMG_0007.jpg', 'IMG_0100.jpg'
            Program = 'Substr(Start, Digits(1).Start) + Number(Substr(Digits(1).Start, End), 1) + Extension'
            Cost    = 33
            New     = 'IMG_42.jpg', 'IMG_7.jpg', 'IMG_100.jpg'
        }
        @{
            Title   = 'a scanner name, lower case and padded, from two examples'
            Example = [ordered]@{ 'Scan 3.pdf' = 'scan_003.pdf'; 'Scan 12.pdf' = 'scan_012.pdf' }
            Name    = 'Scan 3.pdf', 'Scan 12.pdf', 'Scan 104.pdf'
            Program = 'Lower(Substr(Start, Letters(1).End)) + Const("_") + Number(Substr(Digits(1).Start, End), 3) + Extension'
            Cost    = 44
            New     = 'scan_003.pdf', 'scan_012.pdf', 'scan_104.pdf'
        }
        @{
            # The first example needs no change of case: the second one shows it
            # Lower(Substr(Start, End)) 10 + 3 = 13, Lower(Extension) 8 + 3 = 11
            Title   = 'lower case that the first example does not show'
            Example = [ordered]@{ 'notes.txt' = 'notes.txt'; 'Todo.TXT' = 'todo.txt' }
            Name    = 'notes.txt', 'Todo.TXT', 'READ ME.Md'
            Program = 'Lower(Substr(Start, End)) + Lower(Extension)'
            Cost    = 24
            New     = 'notes.txt', 'todo.txt', 'read me.md'
        }
        @{
            # The first number needs no zero: the second example shows the width
            Title   = 'a padded number that the first example does not show'
            Example = [ordered]@{ 'Scan 104.pdf' = 'scan_104.pdf'; 'Scan 3.pdf' = 'scan_003.pdf' }
            Name    = 'Scan 104.pdf', 'Scan 3.pdf', 'Scan 12.pdf'
            Program = 'Lower(Substr(Start, Letters(1).End)) + Const("_") + Number(Substr(Digits(1).Start, End), 3) + Extension'
            Cost    = 44
            New     = 'scan_104.pdf', 'scan_003.pdf', 'scan_012.pdf'
        }
        @{
            Title   = 'a counter in front, the name kept'
            Example = [ordered]@{ 'song.mp3' = '01 - song.mp3' }
            Name    = 'song.mp3', 'tune.mp3', 'z.mp3'
            Program = 'Counter(1, 2) + Const(" - ") + Substr(Start, End) + Extension'
            Cost    = 54
            New     = '01 - song.mp3', '02 - tune.mp3', '03 - z.mp3'
        }
        @{
            Title   = 'a counter learned from two examples that are not the first files'
            Example = [ordered]@{ 'a.jpg' = 'photo_1.jpg'; 'c.jpg' = 'photo_3.jpg' }
            Name    = 'a.jpg', 'b.jpg', 'c.jpg'
            # Const("photo_") 4 + 5 * 13 + 4 = 73, Counter(1, 1) 20, Extension 8
            Program = 'Const("photo_") + Counter(1, 1) + Extension'
            Cost    = 101
            New     = 'photo_1.jpg', 'photo_2.jpg', 'photo_3.jpg'
        }
        @{
            Title   = 'only the second word kept'
            Example = [ordered]@{ 'draft_report_v2.docx' = 'report.docx' }
            Name    = 'draft_report_v2.docx', 'draft_budget_v3.docx'
            Program = 'Substr(Letters(2).Start, Letters(2).End) + Extension'
            Cost    = 22
            New     = 'report.docx', 'budget.docx'
        }
        @{
            Title   = 'first word only, lower case'
            Example = [ordered]@{ 'Report.final.v2.DOC' = 'report.doc' }
            Name    = 'Report.final.v2.DOC', 'Budget.draft.v1.DOC'
            Program = 'Lower(Substr(Start, Letters(1).End)) + Lower(Extension)'
            Cost    = 25
            New     = 'report.doc', 'budget.doc'
        }
        @{
            Title   = 'three words joined with underscores'
            Example = [ordered]@{ 'My Holiday Photo.PNG' = 'my_holiday_photo.png' }
            Name    = 'My Holiday Photo.PNG', 'Other Nice Pic.PNG'
            Program = 'Lower(Substr(Start, Letters(1).End)) + Const("_") + Lower(Substr(Letters(2).Start, Letters(2).End)) + Const("_") + Lower(Substr(Letters(-1).Start, End)) + Lower(Extension)'
            Cost    = 73
            New     = 'my_holiday_photo.png', 'other_nice_pic.png'
        }
        @{
            Title   = 'date and time of a chat picture, from two examples'
            Example = [ordered]@{
                'WhatsApp Image 2024-03-15 at 10.11.12.jpeg' = '2024-03-15_101112.jpeg'
                'WhatsApp Image 2023-12-01 at 08.09.10.jpeg' = '2023-12-01_080910.jpeg'
            }
            Name    = 'WhatsApp Image 2024-03-15 at 10.11.12.jpeg', 'WhatsApp Image 2023-12-01 at 08.09.10.jpeg', 'WhatsApp Image 2022-01-02 at 03.04.05.jpeg'
            Program = 'Substr(Digits(1).Start, Digits(3).End) + Const("_") + Substr(Digits(4).Start, Digits(4).End) + Substr(Digits(-2).Start, Digits(-2).End) + Substr(Digits(-1).Start, End) + Extension'
            Cost    = 74
            New     = '2024-03-15_101112.jpeg', '2023-12-01_080910.jpeg', '2022-01-02_030405.jpeg'
        }
        @{
            Title   = 'nothing to change'
            Example = [ordered]@{ 'IMG_001.jpg' = 'IMG_001.jpg' }
            Name    = 'IMG_001.jpg', 'b.png'
            Program = 'Substr(Start, End) + Extension'
            Cost    = 18
            New     = 'IMG_001.jpg', 'b.png'
        }
    ) {
        $found = Find-LambekRenameRule -Example $Example -Name $Name
        $found.Found | Should -BeTrue
        $found.Program | Should -Be $Program
        $found.Cost | Should -Be $Cost
        $found.Renames.NewName | Should -Be $New
        $found.IsSafe | Should -BeTrue
        # The program gives each example its new name, and the cost is the sum of its pieces
        foreach ($rename in $found.Renames) {
            if ($rename.IsExample) { $rename.NewName | Should -Be $Example[$rename.Name] }
            $found.Rule.Apply($rename.Name, $rename.Index, $null) | Should -Be $rename.NewName
        }
        ($found.Atoms.Cost | Measure-Object -Sum).Sum | Should -Be $Cost
    }

    It 'asks the right question when two rules fit: <Title>' -ForEach @(
        @{
            # The file keeps its own number (07 -> 08), or every file gets "07"
            Title   = 'number copied or typed'
            Example = [ordered]@{ 'track07.mp3' = '07 track.mp3' }
            Name    = 'track07.mp3', 'track08.mp3'
            Ask     = 'track08.mp3'
            First   = '08 track.mp3'
            Second  = '07 track.mp3'
        }
        @{
            # Padded number of the file (10), or a counter that goes 01, 02, 03
            Title   = 'padded number or counter'
            Example = [ordered]@{ 'chapter1.md' = 'chapter-01.md' }
            Name    = 'chapter1.md', 'chapter2.md', 'chapter10.md'
            Ask     = 'chapter10.md'
            First   = 'chapter-10.md'
            Second  = 'chapter-03.md'
        }
        @{
            # Counter per file, or the same "01" for all
            Title   = 'counter or constant'
            Example = [ordered]@{ 'song.mp3' = '01 - song.mp3' }
            Name    = 'song.mp3', 'tune.mp3', 'z.mp3'
            Ask     = 'tune.mp3'
            First   = '02 - tune.mp3'
            Second  = '01 - tune.mp3'
        }
        @{
            # The whole name before the suffix, or only its first word
            Title   = 'whole name or first word'
            Example = [ordered]@{ 'notes.txt' = 'notes_backup.txt' }
            Name    = 'notes.txt', 'todo.txt', 'a.b.txt'
            Ask     = 'a.b.txt'
            First   = 'a.b_backup.txt'
            Second  = 'a_backup.txt'
        }
        @{
            # Zeros removed, or the last two digits kept
            Title   = 'number without zeros or last two digits'
            Example = [ordered]@{ 'IMG_0042.jpg' = 'IMG_42.jpg' }
            Name    = 'IMG_0042.jpg', 'IMG_0007.jpg', 'IMG_0100.jpg'
            Ask     = 'IMG_0007.jpg'
            First   = 'IMG_7.jpg'
            Second  = 'IMG_07.jpg'
        }
    ) {
        $found = Find-LambekRenameRule -Example $Example -Name $Name
        $found.Ambiguous | Should -BeTrue
        $found.Question.Name | Should -Be $Ask
        $found.Question.First | Should -Be $First
        $found.Question.Second | Should -Be $Second
        $found.AlternativeCost | Should -BeGreaterOrEqual $found.Cost
        # The rival also gives each example its new name
        $rival = Find-LambekRenameRule -Example $Example -Name $Name
        $rival.Alternative | Should -Be $found.Alternative
    }

    It 'is not ambiguous when no other name can tell two rules apart' {
        $found = Find-LambekRenameRule -Example @{ 'IMG_001.jpg' = 'holiday_001.jpg' }
        $found.Found | Should -BeTrue
        $found.Ambiguous | Should -BeFalse
        $found.Question | Should -BeNullOrEmpty
        $found.Renames.Count | Should -Be 1
    }

    It 'writes the date of the file' {
        $time = @{ 'a.jpg' = [datetime] '2024-03-15T10:11:12'; 'b.jpg' = [datetime] '2023-01-02T03:04:05' }
        # Date 16 + Const("_") 8 + Substr(Start, End) 10 + Extension 8 = 42
        $found = Find-LambekRenameRule -Example @{ 'a.jpg' = '2024-03-15_a.jpg' } -Name 'a.jpg', 'b.jpg' -Time $time
        $found.Program | Should -Be 'Date("yyyy-MM-dd") + Const("_") + Substr(Start, End) + Extension'
        $found.Cost | Should -Be 42
        ($found.Renames.NewName -join ' ') | Should -Be '2024-03-15_a.jpg 2023-01-02_b.jpg'
        $found.Atoms[0].Format | Should -Be 'yyyy-MM-dd'
        $found.Rule.Apply('c.jpg', 2, [datetime] '2020-12-31T00:00:00') | Should -Be '2020-12-31_c.jpg'

        # Date 16 + Const("_") 8 + Date 16 + Extension 8 = 48; a file without a date cannot be named: it is reported
        $found = Find-LambekRenameRule -Example @{ 'a.jpg' = '20240315_101112.jpg' } -Name 'a.jpg', 'b.jpg', 'c.jpg' -Time $time
        $found.Program | Should -Be 'Date("yyyyMMdd") + Const("_") + Date("HHmmss") + Extension'
        $found.Cost | Should -Be 48
        $found.Renames[1].NewName | Should -Be '20230102_030405.jpg'
        $found.Renames[2].NewName | Should -BeNullOrEmpty
        $found.IsSafe | Should -BeFalse
        $found.Issues[0].Kind | Should -Be 'Undefined'
        $found.Issues[0].Name | Should -Be 'c.jpg'
    }

    It 'reports two files that would get the same name' {
        $found = Find-LambekRenameRule -Example @{ 'b.jpg' = 'photo.jpg' } -Name 'a.jpg', 'b.jpg', 'c.jpg'
        $found.Found | Should -BeTrue
        $found.IsSafe | Should -BeFalse
        (@($found.Issues | ForEach-Object { "$($_.Kind):$($_.Name)" }) -join ' ') | Should -Be 'Duplicate:b.jpg Duplicate:c.jpg'
    }

    It 'reports a name that would be empty' {
        # The cheapest program is the extension alone: a file without extension would get no name at all
        $found = Find-LambekRenameRule -Example @{ 'x.txt' = '.txt' } -Name 'x.txt', 'README'
        $found.Program | Should -Be 'Extension'
        $found.IsSafe | Should -BeFalse
        $found.Issues[0].Kind | Should -Be 'Empty'
        $found.Issues[0].Name | Should -Be 'README'
    }

    It 'reports a file the rule cannot name' {
        $found = Find-LambekRenameRule -Example @{ 'draft_report_v2.docx' = 'report.docx' } -Name 'draft_report_v2.docx', 'notes.docx'
        $found.Renames[1].NewName | Should -BeNullOrEmpty
        $found.IsSafe | Should -BeFalse
        $found.Issues[0].Kind | Should -Be 'Undefined'
    }

    It 'refuses an example whose new name is <Title>' -ForEach @(
        @{ Title = 'empty'; New = '' }
        @{ Title = 'blank'; New = '   ' }
        @{ Title = 'a path with /'; New = 'sub/b.txt' }
        @{ Title = 'a path with \'; New = 'sub\b.txt' }
    ) {
        $found = Find-LambekRenameRule -Example @{ 'a.txt' = $New } -Name 'a.txt', 'c.txt'
        $found.Found | Should -BeFalse
        $found.IsSafe | Should -BeFalse
        $found.Reason | Should -Not -BeNullOrEmpty
        $found.Renames.Count | Should -Be 2
        $found.Renames[0].NewName | Should -BeNullOrEmpty
    }

    It 'says when no single rule fits the examples' {
        $found = Find-LambekRenameRule -Example ([ordered]@{ 'a.jpg' = 'x.jpg'; 'b.jpg' = 'y.png' })
        $found.Found | Should -BeFalse
        $found.Reason | Should -BeLike '*No single rule*'
    }

    It 'gives the same answer whatever the order of a plain table, and twice in a row' {
        $names = 'IMG_001.jpg', 'IMG_002.jpg', 'IMG_009.jpg', 'IMG_010.jpg'
        $first = Find-LambekRenameRule -Example @{ 'IMG_001.jpg' = 'holiday_001.jpg'; 'IMG_002.jpg' = 'holiday_002.jpg'; 'IMG_009.jpg' = 'holiday_009.jpg' } -Name $names
        $second = Find-LambekRenameRule -Example @{ 'IMG_009.jpg' = 'holiday_009.jpg'; 'IMG_002.jpg' = 'holiday_002.jpg'; 'IMG_001.jpg' = 'holiday_001.jpg' } -Name $names
        $first.Program | Should -Be 'Const("holiday") + Substr(Letters(1).End, End) + Extension'
        $second.Program | Should -Be $first.Program
        $second.Alternative | Should -Be $first.Alternative
        ($first.Renames.NewName -join ' ') | Should -Be 'holiday_001.jpg holiday_002.jpg holiday_009.jpg holiday_010.jpg'
    }

    It 'prefers the program whose text comes first among equal costs' {
        # Number(...) and Substr(Digits(1).End-2, End) both cost 14 here: "N" comes before "S"
        $found = Find-LambekRenameRule -Example @{ 'IMG_0042.jpg' = 'IMG_42.jpg' } -Name 'IMG_0042.jpg', 'IMG_0007.jpg'
        $found.Cost | Should -Be 33
        $found.AlternativeCost | Should -Be 33
        $found.Atoms[1].Text | Should -Be 'Number(Substr(Digits(1).Start, End), 1)'
        $found.Alternative | Should -Be 'Substr(Start, Digits(1).Start) + Substr(Digits(1).End-2, End) + Extension'
    }

    It 'handles a folder of 200 names' {
        $names = 0..199 | ForEach-Object { 'Screenshot 2024-03-{0:d2} at 10.{1:d2}.{2:d2}.png' -f (1 + $_ % 28), ($_ % 60), (($_ * 7) % 60) }
        $example = [ordered]@{}
        $example[$names[0]] = 'shot_20240301_100000.png'
        $example[$names[5]] = 'shot_20240306_100535.png'
        $found = Find-LambekRenameRule -Example $example -Name $names
        $found.Found | Should -BeTrue
        $found.Renames.Count | Should -Be 200
        $found.Renames[199].NewName | Should -Be 'shot_20240304_101913.png'
        $found.IsSafe | Should -BeTrue
    }
}

Describe 'Explanation-based generalisation' {

    It 'folds a chain of three edges into one rule' {
        # path(a, d) is edge(a, b), then path(b, d) = edge(b, c), then path(c, d) = edge(c, d).
        # Unifying the heads link by link leaves three edges that share their middle points
        $program = 'edge(a, b). edge(b, c). edge(c, d). path(X, Y) :- edge(X, Y). path(X, Z) :- edge(X, Y), path(Y, Z).'
        $learned = @(ConvertTo-LambekLearnedRule 'path(a, d)' -Program $program)
        $learned.Count | Should -Be 1
        $learned[0].Rule | Should -Be 'path(X, Y) :- edge(X, X2), edge(X2, X3), edge(X3, Y).'
        $learned[0].Steps | Should -Be 3
        $learned[0].IsNew | Should -BeTrue
        $learned[0].Fact | Should -Be 'path("a", "d")'
    }

    It 'keeps the constants the rules wrote and frees the others' {
        # "system" is written in the rule: it stays. "/etc", "linux" and the path come from facts: they become variables
        $program = @'
os("linux"). protected_on("linux", "/etc"). changes("/etc/passwd").
protected(P) :- os(O), protected_on(O, P).
blocked(P, "system") :- changes(P), protected(Q), under(P, Q).
'@
        $learned = @(ConvertTo-LambekLearnedRule 'blocked("/etc/passwd", R)' -Program $program)
        $learned[0].Rule | Should -Be 'blocked(P, "system") :- changes(P), os(O), protected_on(O, P2), under(P, P2).'
        $learned[0].Steps | Should -Be 2
    }

    It 'keeps a constant with a backslash and a quote readable by the parser' {
        $program = 'kept("C:\Temp\"). named("say ""hi"""). changes("C:\Temp\a"). inside(P, "C:\Temp\") :- changes(P), kept("C:\Temp\"). tagged(P, "say ""hi""") :- inside(P, _), named("say ""hi""").'
        $learned = @(ConvertTo-LambekLearnedRule 'tagged(P, T)' -Program $program)
        $learned[0].Rule | Should -Be 'tagged(P, "say ""hi""") :- changes(P), kept("C:\Temp\"), named("say ""hi""").'
        Get-AllFact ($program + ' ' + $learned[0].Rule) | Should -Be (Get-AllFact $program)
    }

    It 'carries negations and anonymous variables through' {
        $program = 'file(a). file(b). kept(a). owns(b, x). gone(F) :- file(F), not kept(F). has(F) :- owns(F, _). lost(F) :- gone(F), has(F).'
        $learned = @(ConvertTo-LambekLearnedRule 'lost(b)' -Program $program)
        $learned[0].Rule | Should -Be 'lost(F) :- file(F), not kept(F), owns(F, _).'
        $learned[0].Steps | Should -Be 3
    }

    It 'gives the rule itself for a one-step proof, and nothing for a given fact' {
        $program = 'edge(a, b). path(X, Y) :- edge(X, Y).'
        $learned = @(ConvertTo-LambekLearnedRule 'path(a, b)' -Program $program)
        $learned[0].Rule | Should -Be 'path(X, Y) :- edge(X, Y).'
        $learned[0].IsNew | Should -BeFalse
        @(ConvertTo-LambekLearnedRule 'edge(a, b)' -Program $program).Count | Should -Be 0
        @(ConvertTo-LambekLearnedRule 'path(b, a)' -Program $program).Count | Should -Be 0
    }

    It 'derives the same fact directly, and never a fact the rules did not derive: <Title>' -ForEach @(
        @{
            Title = 'paths in a graph'
            Rules = 'path(X, Y) :- edge(X, Y). path(X, Z) :- edge(X, Y), path(Y, Z).'
            Facts = 'edge(a, b). edge(b, c). edge(c, d).'
            Other = 'edge(m, n). edge(n, o). edge(o, p). edge(p, q). edge(q, m). edge(z, z).'
            Query = 'path(a, d)'
            Fact  = 'path(a,d)'
        }
        @{
            Title = 'family'
            Rules = 'parent(X, Y) :- father(X, Y). parent(X, Y) :- mother(X, Y). grand(X, Z) :- parent(X, Y), parent(Y, Z). old(X) :- grand(X, _), not young(X).'
            Facts = 'father(tom, bob). mother(bob2, ann). mother(tom, bob2). father(bob, liz). young(liz).'
            Other = 'father(a, b). father(b, c). mother(c, d). mother(d, e). young(a). young(c). father(x, x).'
            Query = 'old(tom)'
            Fact  = 'old(tom)'
        }
        @{
            Title = 'blocked folders with tests and negation'
            Rules = 'protected(P) :- os(O), protected_on(O, P). mine(P) :- changes(P), home(H), under(P, H). blocked(P, "system") :- changes(P), protected(Q), under(P, Q). blocked(P, "other") :- changes(P), users(U), under(P, U), not same(P, U), not mine(P).'
            Facts = 'os("linux"). protected_on("linux", "/etc"). protected_on("macos", "/System"). home("/home/me"). users("/home"). changes("/etc/ssh/config"). changes("/home/you/a").'
            Other = 'os("macos"). protected_on("linux", "/etc"). protected_on("macos", "/System"). home("/Users/me"). users("/Users"). changes("/System/x"). changes("/Users/me/a"). changes("/Users/you/b"). changes("/etc/x"). changes("/Users").'
            Query = 'blocked("/etc/ssh/config", R)'
            Fact  = 'blocked(/etc/ssh/config,system)'
        }
        @{
            Title = 'blocked folders, the rule with two negations'
            Rules = 'protected(P) :- os(O), protected_on(O, P). mine(P) :- changes(P), home(H), under(P, H). blocked(P, "system") :- changes(P), protected(Q), under(P, Q). blocked(P, "other") :- changes(P), users(U), under(P, U), not same(P, U), not mine(P). warned(P) :- blocked(P, "other"), listed(P).'
            Facts = 'os("linux"). protected_on("linux", "/etc"). home("/home/me"). users("/home"). changes("/home/you/a"). listed("/home/you/a").'
            Other = 'os("macos"). home("/Users/me"). users("/Users"). changes("/Users/me/a"). changes("/Users/you/b"). changes("/Users"). listed("/Users/me/a"). listed("/Users/you/b"). listed("/Users").'
            Query = 'warned(P)'
            Fact  = 'warned(/home/you/a)'
            # The macro rule says "not mine": alone, it still needs the rule that says what is mine
            Keep  = 'mine(P) :- changes(P), home(H), under(P, H).'
        }
        @{
            Title = 'a rule used twice with a shared middle'
            Rules = 'link(X, Y) :- wire(X, Y). link(X, Y) :- wire(Y, X). both(X, Z) :- link(X, Y), link(Y, Z), neq(X, Z).'
            Facts = 'wire(a, b). wire(c, b).'
            Other = 'wire(p, q). wire(q, r). wire(r, p). wire(s, s). wire(t, s).'
            Query = 'both(a, c)'
            Fact  = 'both(a,c)'
        }
    ) {
        $learned = @(ConvertTo-LambekLearnedRule $Query -Program "$Facts $Rules")
        $learned.Count | Should -BeGreaterThan 0
        $macro = $learned[0].Rule
        $learned[0].IsNew | Should -BeTrue

        # With the macro rule added, the facts are exactly the same: on the facts of the proof, and on other facts
        Get-AllFact "$Facts $Rules $macro" | Should -Be (Get-AllFact "$Facts $Rules")
        Get-AllFact "$Other $Rules $macro" | Should -Be (Get-AllFact "$Other $Rules")

        # The macro rule alone (with the rules of what it negates) gives the fact in one step from the given facts
        $support = ''
        if ($_.ContainsKey('Keep')) { $support = $_['Keep'] }
        $alone = Get-AllFact "$Facts $support $macro"
        $alone | Should -Contain $Fact
        foreach ($line in $alone) { (Get-AllFact "$Facts $Rules") | Should -Contain $line }
        foreach ($line in (Get-AllFact "$Other $support $macro")) { (Get-AllFact "$Other $Rules") | Should -Contain $line }
    }

    It 'leaves a rule that counts alone' {
        # total(2) comes from every item at once, not from one proof: it is neither folded nor generalised
        $program = 'item(a). item(b). total(count<X>) :- item(X). big(N) :- total(N), gt(N, "1").'
        $learned = @(ConvertTo-LambekLearnedRule 'big(N)' -Program $program)
        $learned[0].Fact | Should -Be 'big("2")'
        $learned[0].Rule | Should -Be 'big(N) :- total(N), gt(N, "1").'
        $learned[0].Steps | Should -Be 1
        @(ConvertTo-LambekLearnedRule 'total(N)' -Program $program).Count | Should -Be 0
    }

    It 'changes nothing with the macro rule of any derived fact: <Title>' -ForEach @(
        @{
            Title = 'graph'
            Rules = 'path(X, Y) :- edge(X, Y). path(X, Z) :- edge(X, Y), path(Y, Z). loop(X) :- path(X, X). far(X, Y) :- path(X, Y), not edge(X, Y), neq(X, Y).'
            Facts = 'edge(a, b). edge(b, c). edge(c, d). edge(d, b). edge(e, e).'
            Other = 'edge(m, n). edge(n, o). edge(o, p). edge(p, q). edge(q, m). edge(z, z). edge(z, m).'
        }
        @{
            Title = 'family'
            Rules = 'parent(X, Y) :- father(X, Y). parent(X, Y) :- mother(X, Y). grand(X, Z) :- parent(X, Y), parent(Y, Z). old(X) :- grand(X, _), not young(X). kin(X, Y) :- parent(Z, X), parent(Z, Y), neq(X, Y).'
            Facts = 'father(tom, bob). mother(bob2, ann). mother(tom, bob2). father(bob, liz). father(bob, max). young(liz).'
            Other = 'father(a, b). father(b, c). mother(c, d). mother(d, e). mother(c, f). young(a). young(c). father(x, x).'
        }
        @{
            Title = 'blocked folders'
            Rules = 'protected(P) :- os(O), protected_on(O, P). mine(P) :- changes(P), home(H), under(P, H). blocked(P, "system") :- changes(P), protected(Q), under(P, Q). blocked(P, "other") :- changes(P), users(U), under(P, U), not same(P, U), not mine(P). warned(P) :- blocked(P, _), listed(P). safe(P) :- changes(P), not blocked(P, "system"), not blocked(P, "other").'
            Facts = 'os("linux"). protected_on("linux", "/etc"). protected_on("macos", "/System"). home("/home/me"). users("/home"). changes("/etc/ssh/config"). changes("/home/you/a"). changes("/home/me/b"). changes("/tmp/x"). listed("/home/you/a"). listed("/etc/ssh/config").'
            Other = 'os("macos"). protected_on("linux", "/etc"). protected_on("macos", "/System"). home("/Users/me"). users("/Users"). changes("/System/x"). changes("/Users/me/a"). changes("/Users/you/b"). changes("/etc/x"). changes("/Users"). listed("/System/x"). listed("/Users/you/b"). listed("/Users/me/a").'
        }
    ) {
        $macros = @(Get-AllMacro "$Facts $Rules")
        $macros.Count | Should -BeGreaterThan 3
        $before = Get-AllFact "$Facts $Rules"
        $beforeOther = Get-AllFact "$Other $Rules"
        foreach ($macro in $macros) {
            Get-AllFact "$Facts $Rules $macro" | Should -Be $before
            Get-AllFact "$Other $Rules $macro" | Should -Be $beforeOther
        }
        # And with all of them at once
        Get-AllFact "$Other $Rules $($macros -join ' ')" | Should -Be $beforeOther
    }

    It 'generalises a block of the real rules of Lambek' {
        $folder = [Environment]::GetFolderPath('UserProfile')
        $learned = @(ConvertTo-LambekLearnedRule 'blocked(P, R)' -Changes $folder)
        $learned.Count | Should -BeGreaterThan 0
        $learned[0].Rule | Should -BeLike 'blocked(P, "*") :- changes(P), *'
        $learned[0].Proof.Count | Should -BeGreaterThan 1
        # The rule text is read back by the parser of the rules
        InModuleScope Lambek -Parameters @{ Text = $learned[0].Rule } {
            $clauses = ConvertFrom-LambekLogic -Text $Text
            $clauses.Count | Should -Be 1
            [LambekLearning]::Format($clauses[0]) | Should -Be $Text
        }
    }
}

Describe 'Bounded type learning' {

    It 'keeps types inside the bounds, the narrowest first' {
        InModuleScope Lambek {
            # Widths: "o" 1, "o o^l" 2, "s o^l" 2, "o^r o d^l" 3, "s p^l o^l d^l" 4
            $types = 'o^r o d^l', 's o^l', 'o', 'o o^l', 's p^l o^l d^l'
            Select-LambekBoundedType -Type $types -MaxWidth 3 -MaxTypes 5 | Should -Be @('o', 'o o^l', 's o^l', 'o^r o d^l')
            Select-LambekBoundedType -Type $types -MaxWidth 2 -MaxTypes 5 | Should -Be @('o', 'o o^l', 's o^l')
            Select-LambekBoundedType -Type $types -MaxWidth 4 -MaxTypes 2 | Should -Be @('o', 'o o^l')
            # A word that already has "o" has room for one more type when K = 2, and for none when K = 1
            Select-LambekBoundedType -Type $types -MaxWidth 3 -MaxTypes 2 -Known 'o' | Should -Be @('o o^l')
            @(Select-LambekBoundedType -Type $types -MaxWidth 3 -MaxTypes 1 -Known 'o').Count | Should -Be 0
            @(Select-LambekBoundedType -Type @() -MaxWidth 3 -MaxTypes 2).Count | Should -Be 0
        }
    }

    It 'respects the bounds on a sentence with one unknown word: <Text>' -ForEach @(
        @{ Text = 'zorp the .tmp files in C:\Temp'; Type = 's o^l'; Width = 2 }
        @{ Text = 'zap the files in C:\A to D:\B'; Type = 's p^l o^l'; Width = 3 }
        @{ Text = 'delete the screenshots in C:\A'; Type = 'o'; Width = 1 }
    ) {
        InModuleScope Lambek -Parameters @{ Text = $Text; Type = $Type; Width = $Width } {
            $request = ConvertTo-LambekRequest $Text
            $grammar = Resolve-LambekGrammar -Request $request
            $free = Get-LambekTypeGuess -Request $request -Grammar $grammar

            # Wide enough: the type that makes the sentence reduce to s is found
            $guess = Get-LambekBoundedTypeGuess -Request $request -Grammar $grammar -MaxWidth $Width -MaxTypes 1
            $guess.Types | Should -Be @($Type)
            $guess.Types.Count | Should -BeLessOrEqual 1
            foreach ($one in $guess.Types) {
                @(ConvertFrom-LambekType -Type $one).Count | Should -BeLessOrEqual $Width
                $free.Types | Should -Contain $one
                (Resolve-LambekGrammar -Request $request -Hypothesis @{ $guess.Word = @($one) } -SentenceOnly).IsSentence | Should -BeTrue
            }

            # One simple type too narrow: nothing is learned rather than something outside the bound
            if ($Width -gt 1) {
                Get-LambekBoundedTypeGuess -Request $request -Grammar $grammar -MaxWidth ($Width - 1) -MaxTypes 4 | Should -BeNullOrEmpty
            }
        }
    }

    It 'learns nothing from two unknown words' {
        InModuleScope Lambek {
            $request = ConvertTo-LambekRequest 'zorp blarg the .tmp files in C:\Temp'
            $grammar = Resolve-LambekGrammar -Request $request
            Get-LambekBoundedTypeGuess -Request $request -Grammar $grammar | Should -BeNullOrEmpty
        }
    }
}
