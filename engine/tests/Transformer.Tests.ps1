BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    # A very small model whose every parameter is away from its starting value, and three requests of different lengths
    function Get-TestModel {
        param([uint64] $Seed = 7)
        $model = [LambekTransformer]::Create(32, 8, 2, 2, 16, 8, [string[]] @('a', 'b', 'c', 'none'), $Seed, 0.5)
        $random = [LambekXorShift]::new(99)
        foreach ($name in $model.Names) {
            if ($model.Shapes[$name][1] -ne 1) { continue }
            $values = $model.Weights[$name]
            for ($i = 0; $i -lt $values.Length; $i++) { $values[$i] += 0.3 * $random.NextGaussian() }
        }
        $model.Refresh()
        return $model
    }

    function Get-TestInput {
        param([LambekTransformer] $Model)
        return , ([int[][][]] @($Model.Encode('delete the old files in C:\Temp'), $Model.Encode('copy report.txt'), $Model.Encode('bonjour')))
    }

    # An adapter whose B is not zero any more, as after some training
    function Get-TestAdapter {
        param([LambekTransformer] $Model, [string] $Name = 'user')
        $adapter = $Model.NewAdapter($Name, 2, 4.0, 5, $true)
        $random = [LambekXorShift]::new(123)
        foreach ($target in $adapter.Targets) {
            $values = $adapter.B[$target]
            for ($i = 0; $i -lt $values.Length; $i++) { $values[$i] = 0.2 * $random.NextGaussian() }
        }
        return $adapter
    }

    function Test-SameBit {
        param([double[]] $Left, [double[]] $Right)
        if ($Left.Length -ne $Right.Length) { return $false }
        for ($i = 0; $i -lt $Left.Length; $i++) {
            if ([BitConverter]::DoubleToInt64Bits($Left[$i]) -ne [BitConverter]::DoubleToInt64Bits($Right[$i])) { return $false }
        }
        return $true
    }

    $script:Labels = [int[]] @(0, 2, 3)
    $script:ProposerFile = Join-Path $PSScriptRoot '../Lambek/Data/proposer.json'
}

Describe 'Transformer: the formulas, each with a value computed by hand' {

    It 'xorshift64 from seed 1 gives 1082269761 (1 -> 8193 -> 8257 -> 8257 xor 8257 * 2^17)' {
        [LambekXorShift]::new(1).Next() | Should -Be 1082269761
    }

    It 'the generator gives numbers in [0, 1) and the same ones for the same seed' {
        $one = [LambekXorShift]::new(42)
        $two = [LambekXorShift]::new(42)
        for ($i = 0; $i -lt 50; $i++) {
            $value = $one.NextDouble()
            $value | Should -BeGreaterOrEqual 0
            $value | Should -BeLessThan 1
            $two.NextDouble() | Should -Be $value
        }
    }

    It 'FNV-1a 32 bits: "" is 2166136261, "a" is 0xE40C292C, "foobar" is 0xBF9CF968' {
        [LambekTransformerText]::Fnv1a('') | Should -Be 2166136261
        [LambekTransformerText]::Fnv1a('a') | Should -Be 3826002220
        [LambekTransformerText]::Fnv1a('foobar') | Should -Be 3214735720
    }

    It 'the trigrams of "del" between its two ends are ^de, del, el$' {
        ([LambekTransformerText]::Trigrams('del') -join ' ') | Should -Be '^de del el$'
    }

    It 'a word gives one row for itself and one for each trigram; a placeholder gives one row only' {
        $rows = [LambekTransformerText]::RowsOf('del', 4096)
        $rows.Length | Should -Be 4
        $rows[0] | Should -Be ([LambekTransformerText]::Fnv1a('w:del') % 4096)
        $rows[1] | Should -Be ([LambekTransformerText]::Fnv1a('t:^de') % 4096)
        [LambekTransformerText]::RowsOf('<path>', 4096).Length | Should -Be 1
    }

    It 'normalises a text as the engine does: <Text>' -ForEach @(
        @{ Text = ("Supprime l'" + [char] 0x00E9 + 't' + [char] 0x00E9 + '  D' + [char] 0x00C9 + 'J' + [char] 0x00C0) }
        @{ Text = ('d' + [char] 0x00E9 + 'place-les vers D:\B') }
        @{ Text = ('Stra' + [char] 0x00DF + 'e  l' + [char] 0x00F6 + 'schen') }
        @{ Text = '' }
    ) {
        $expected = InModuleScope Lambek -Parameters @{ Text = $Text } { param($Text) ConvertTo-LambekNormalizedText -Text $Text }
        [LambekTransformerText]::Normalize($Text) | Should -Be $expected
    }

    It 'replaces paths, quoted names, file names, extensions and numbers by placeholders' {
        $words = [LambekTransformerText]::Words('Efface les fichiers .log de plus de 500 Ko dans C:\Data et "mes notes" report.txt')
        ($words -join ' ') | Should -Be 'efface les fichiers <ext> de plus de <num> ko dans <path> et <quoted> <file>'
        ([LambekTransformerText]::Words('  ') -join ' ') | Should -Be '<empty>'
    }

    It 'softmax of (0, ln 2, ln 5) is (1/8, 2/8, 5/8)' {
        $p = [LambekTransformer]::Softmax([double[]] @(0, [math]::Log(2), [math]::Log(5)))
        $p[0] | Should -BeLessThan (0.125 + 1e-12)
        $p[0] | Should -BeGreaterThan (0.125 - 1e-12)
        [math]::Abs($p[1] - 0.25) | Should -BeLessThan 1e-12
        [math]::Abs($p[2] - 0.625) | Should -BeLessThan 1e-12
    }

    It 'softmax does not overflow on large values' {
        $p = [LambekTransformer]::Softmax([double[]] @(1000, 1000))
        $p[0] | Should -Be 0.5
    }

    It 'GELU(1) is 0.5 (1 + tanh(sqrt(2 / pi) * 1.044715)) = 0.841191990608, and GELU(0) is 0' {
        [math]::Abs([LambekTransformer]::Gelu(1.0) - 0.8411919906082768) | Should -BeLessThan 1e-12
        [LambekTransformer]::Gelu(0.0) | Should -Be 0
    }

    It 'the slope of GELU at 1 is 1.082964083846, and it is the slope found by differences' {
        [math]::Abs([LambekTransformer]::GeluSlope(1.0) - 1.0829640838457826) | Should -BeLessThan 1e-12
        foreach ($x in -2.0, -0.3, 0.0, 0.7, 2.5) {
            $numeric = ([LambekTransformer]::Gelu($x + 1e-6) - [LambekTransformer]::Gelu($x - 1e-6)) / 2e-6
            [math]::Abs([LambekTransformer]::GeluSlope($x) - $numeric) | Should -BeLessThan 1e-8
        }
    }

    It 'the position 1 in dimension 4 is (sin 1, cos 1, sin 0.01, cos 0.01), and the position 0 is (0, 1, 0, 1)' {
        $p = [LambekTransformer]::Position(1, 4)
        [math]::Abs($p[0] - 0.8414709848078965) | Should -BeLessThan 1e-12
        [math]::Abs($p[1] - 0.5403023058681398) | Should -BeLessThan 1e-12
        [math]::Abs($p[2] - 0.009999833334166664) | Should -BeLessThan 1e-12
        [math]::Abs($p[3] - 0.9999500004166653) | Should -BeLessThan 1e-12
        ([LambekTransformer]::Position(0, 4) -join ' ') | Should -Be '0 1 0 1'
    }

    It 'layer norm of (1, 2, 3, 4): mean 2.5, variance 1.25, so the first is -1.5 / sqrt(1.25 + 1e-5)' {
        $y = [LambekTransformer]::LayerNorm([double[]] @(1, 2, 3, 4), [double[]] @(1, 1, 1, 1), [double[]] @(0, 0, 0, 0))
        [math]::Abs($y[0] - (-1.3416354199689269)) | Should -BeLessThan 1e-12
        [math]::Abs($y[0] + $y[3]) | Should -BeLessThan 1e-12
        # With a gain of 2 and a bias of 1 the third is 2 * 0.5 / sigma + 1
        $z = [LambekTransformer]::LayerNorm([double[]] @(1, 2, 3, 4), [double[]] @(2, 2, 2, 2), [double[]] @(1, 1, 1, 1))
        [math]::Abs($z[2] - 1.894423613312618) | Should -BeLessThan 1e-12
    }

    It 'a matrix times a vector: (1 2; 3 4) (1, 1) is (3, 7)' {
        $y = [LambekTransformer]::Apply([double[]] @(1, 2, 3, 4), 2, 2, [double[]] @(1, 1))
        ($y -join ' ') | Should -Be '3 7'
    }

    It 'attention: scores (0, ln 3) give weights (1/4, 3/4), so values 4 and 8 mix into 7; a zero query gives their mean 6' {
        $query = [double[][]] @(, [double[]] @(1.0)) + @(, [double[]] @(0.0))
        $key = [double[][]] @(, [double[]] @(0.0)) + @(, [double[]] @([math]::Log(3)))
        $value = [double[][]] @(, [double[]] @(4.0)) + @(, [double[]] @(8.0))
        $mixed = [LambekTransformer]::Attend($query, $key, $value, 1)
        [math]::Abs($mixed[0][0] - 7.0) | Should -BeLessThan 1e-12
        [math]::Abs($mixed[1][0] - 6.0) | Should -BeLessThan 1e-12
    }

    It 'attention divides the scores by sqrt(d_k): with d_k = 4 a product of 2 ln 3 gives the weights (1/4, 3/4)' {
        $query = [double[][]] @(, [double[]] @(2.0, 0, 0, 0)) + @(, [double[]] @(0.0, 0, 0, 0))
        $key = [double[][]] @(, [double[]] @(0.0, 0, 0, 0)) + @(, [double[]] @([math]::Log(3), 0, 0, 0))
        $value = [double[][]] @(, [double[]] @(4.0, 0, 0, 0)) + @(, [double[]] @(8.0, 0, 0, 0))
        $mixed = [LambekTransformer]::Attend($query, $key, $value, 1)
        [math]::Abs($mixed[0][0] - 7.0) | Should -BeLessThan 1e-12
    }

    It 'each head attends on its own slice' {
        # Head 0 (first number) looks at the second word, head 1 (second number) stays even
        $query = [double[][]] @(, [double[]] @(1.0, 0.0)) + @(, [double[]] @(0.0, 0.0))
        $key = [double[][]] @(, [double[]] @(0.0, 5.0)) + @(, [double[]] @([math]::Log(3), 5.0))
        $value = [double[][]] @(, [double[]] @(4.0, 10.0)) + @(, [double[]] @(8.0, 20.0))
        $mixed = [LambekTransformer]::Attend($query, $key, $value, 2)
        [math]::Abs($mixed[0][0] - 7.0) | Should -BeLessThan 1e-12
        [math]::Abs($mixed[0][1] - 15.0) | Should -BeLessThan 1e-12
    }

    It 'cross-entropy of the probability 1/4 is ln 4' {
        [math]::Abs([LambekTransformer]::CrossEntropy([double[]] @(0.25, 0.75), 0) - [math]::Log(4)) | Should -BeLessThan 1e-12
    }

    It 'LoRA: (1 2; 3 4) + (2 / 1) * (2; 3) (1 0) is (5 2; 9 4)' {
        $adapted = [LambekTransformer]::Adapt([double[]] @(1, 2, 3, 4), 2, 2, [double[]] @(1, 0), [double[]] @(2, 3), 1, 2.0)
        ($adapted -join ' ') | Should -Be '5 2 9 4'
    }

    It 'LoRA gradients: with G = (1 2; 3 4), A = (1 0), B = (2; 3), alpha / r = 2: dB = 2 G A'' = (2; 6), dA = 2 B'' G = (22 32)' {
        $model = [LambekTransformer]::Create(8, 2, 1, 1, 2, 4, [string[]] @('a', 'none'), 3, 0.5)
        $adapter = $model.NewAdapter('hand', 1, 2.0, 1, $false)
        $adapter.A['block0.query'] = [double[]] @(1, 0)
        $adapter.B['block0.query'] = [double[]] @(2, 3)
        $gradients = [System.Collections.Generic.Dictionary[string, double[]]]::new()
        $gradients['block0.query'] = [double[]] @(1, 2, 3, 4)
        $gradients['block0.value'] = [double[]] @(0, 0, 0, 0)
        $own = $model.AdapterGradient($adapter, $gradients)
        ($own['block0.query.B'] -join ' ') | Should -Be '2 6'
        ($own['block0.query.A'] -join ' ') | Should -Be '22 32'
    }

    It 'Adam: the first step moves a weight by the rate, whatever the size of the gradient (1 -> 0.9 -> 0.8)' {
        $adam = [LambekAdam]::new()
        $adam.Rate = 0.1
        $weights = [double[]] @(1.0)
        $adam.Begin()
        $adam.Update('w', $weights, [double[]] @(0.5))
        # m = 0.05, v = 0.00025, corrected: 0.5 and 0.25, step = 0.1 * 0.5 / (0.5 + 1e-8)
        [math]::Abs($weights[0] - 0.9) | Should -BeLessThan 1e-8
        $adam.Begin()
        $adam.Update('w', $weights, [double[]] @(0.5))
        # m = 0.095 / 0.19 = 0.5, v = 0.00049975 / 0.001999 = 0.25: the same step
        [math]::Abs($weights[0] - 0.8) | Should -BeLessThan 1e-7
    }

    It 'the threshold is the lowest confidence at which the proposals kept are right often enough' {
        $confidence = [double[]] @(0.9, 0.8, 0.7, 0.6)
        $right = [bool[]] @($true, $true, $false, $true)
        # Kept down to 0.6: 3 right of 4 = 0.75. Kept down to 0.8: 2 of 2
        [LambekTransformer]::Calibrate($confidence, $right, 0.75) | Should -Be 0.6
        [LambekTransformer]::Calibrate($confidence, $right, 0.9) | Should -Be 0.8
        [LambekTransformer]::Calibrate($confidence, [bool[]] @($false, $false, $false, $false), 0.9) | Should -Be 2
    }

    It 'ranks the classes from the most probable, the first of a tie first' {
        ([LambekTransformer]::Rank([double[]] @(0.2, 0.5, 0.2, 0.1)) -join ' ') | Should -Be '1 0 2 3'
    }

    It 'writes a number as its 8 bytes in base64 (1.0 is AAAAAAAA8D8=) and reads it back exactly' {
        [LambekTransformer]::Pack([double[]] @(1.0)) | Should -Be 'AAAAAAAA8D8='
        $values = [double[]] @(0.1, -2.5e-300, [math]::PI, 0.0)
        (Test-SameBit -Left ([LambekTransformer]::Unpack([LambekTransformer]::Pack($values))) -Right $values) | Should -BeTrue
    }

    It 'the mean pooling and the head: the probabilities add up to one, whatever the number of words' {
        $model = Get-TestModel
        foreach ($text in 'delete', 'delete the files in C:\Temp', 'a b c d e f g h i j k l') {
            $sum = 0.0
            foreach ($p in $model.Predict($text)) { $sum += $p }
            [math]::Abs($sum - 1.0) | Should -BeLessThan 1e-12
        }
    }
}

Describe 'Transformer: every gradient against finite differences' {

    It 'the gradient of <_> is the one found by differences (relative error under 1e-5)' -ForEach @(
        'embedding'
        'block0.norm1.gain', 'block0.norm1.bias', 'block0.query', 'block0.key', 'block0.value', 'block0.output'
        'block0.norm2.gain', 'block0.norm2.bias', 'block0.up', 'block0.up.bias', 'block0.down', 'block0.down.bias'
        'block1.norm1.gain', 'block1.norm1.bias', 'block1.query', 'block1.key', 'block1.value', 'block1.output'
        'block1.norm2.gain', 'block1.norm2.bias', 'block1.up', 'block1.up.bias', 'block1.down', 'block1.down.bias'
        'norm.gain', 'norm.bias', 'head', 'head.bias'
    ) {
        if (-not (Get-Variable -Name BaseCheck -Scope Script -ErrorAction Ignore)) {
            $model = Get-TestModel
            $script:BaseCheck = $model.CheckGradient((Get-TestInput -Model $model), $script:Labels, 1e-5)
            $script:BaseGradient = $model.Gradient((Get-TestInput -Model $model), $script:Labels)
        }
        $script:BaseCheck.ContainsKey($_) | Should -BeTrue
        $script:BaseCheck[$_] | Should -BeLessThan 1e-5
        # The check means something only when the gradient is not zero everywhere
        $largest = 0.0
        foreach ($value in $script:BaseGradient[$_]) { $largest = [math]::Max($largest, [math]::Abs($value)) }
        $largest | Should -BeGreaterThan 1e-3
    }

    It 'checks every parameter group of the model, none forgotten' {
        $model = Get-TestModel
        $check = $model.CheckGradient((Get-TestInput -Model $model), $script:Labels, 1e-5)
        $check.Count | Should -Be $model.Names.Count
        $check.Count | Should -Be 29
    }

    It 'the same holds for a wrong-sized step taken from here, without the checker of the class' {
        # Differences computed in this test, on a few numbers of each kind of matrix
        $model = Get-TestModel
        $inputs = Get-TestInput -Model $model
        $gradients = $model.Gradient($inputs, $script:Labels)
        foreach ($name in 'block0.query', 'block1.value', 'block0.up', 'block1.norm2.gain', 'head', 'embedding') {
            $values = $model.Weights[$name]
            $largest = 0
            for ($i = 1; $i -lt $values.Length; $i++) { if ([math]::Abs($gradients[$name][$i]) -gt [math]::Abs($gradients[$name][$largest])) { $largest = $i } }
            foreach ($at in 0, $largest, ($values.Length - 1)) {
                $kept = $values[$at]
                $values[$at] = $kept + 1e-5
                $model.Refresh()
                $above = $model.Loss($inputs, $script:Labels)
                $values[$at] = $kept - 1e-5
                $model.Refresh()
                $below = $model.Loss($inputs, $script:Labels)
                $values[$at] = $kept
                $model.Refresh()
                $numeric = ($above - $below) / 2e-5
                [LambekTransformer]::RelativeError($gradients[$name][$at], $numeric) | Should -BeLessThan 1e-5 -Because "$name[$at]"
            }
        }
    }

    It 'a wrong gradient is seen: the relative error of 1.01 against 1 is far over 1e-5' {
        [LambekTransformer]::RelativeError(1.01, 1.0) | Should -BeGreaterThan 1e-3
        [LambekTransformer]::RelativeError(-1.0, 1.0) | Should -Be 1
        [LambekTransformer]::RelativeError(0.0, 0.0) | Should -Be 0
    }

    It 'LoRA, B not zero: the gradient of <_> is the one found by differences' -ForEach @(
        'block0.query.A', 'block0.query.B', 'block0.value.A', 'block0.value.B'
        'block1.query.A', 'block1.query.B', 'block1.value.A', 'block1.value.B'
        'head.A', 'head.B'
    ) {
        if (-not (Get-Variable -Name AdapterCheck -Scope Script -ErrorAction Ignore)) {
            $model = Get-TestModel
            $adapter = Get-TestAdapter -Model $model
            $model.Attach($adapter)
            $inputs = Get-TestInput -Model $model
            $script:AdapterCheck = $model.CheckAdapterGradient($adapter, $inputs, $script:Labels, 1e-5)
            $script:AdapterGradient = $model.AdapterGradient($adapter, $model.Gradient($inputs, $script:Labels))
        }
        $script:AdapterCheck[$_] | Should -BeLessThan 1e-5
        $largest = 0.0
        foreach ($value in $script:AdapterGradient[$_]) { $largest = [math]::Max($largest, [math]::Abs($value)) }
        $largest | Should -BeGreaterThan 1e-4
    }

    It 'LoRA at its start (B = 0): B has a gradient, A has none, both as the differences say' {
        $model = Get-TestModel
        $adapter = $model.NewAdapter('user', 2, 4.0, 5, $true)
        $model.Attach($adapter)
        $inputs = Get-TestInput -Model $model
        $check = $model.CheckAdapterGradient($adapter, $inputs, $script:Labels, 1e-5)
        $check.Count | Should -Be 10
        foreach ($name in $check.Keys) { $check[$name] | Should -BeLessThan 1e-5 -Because $name }
        $own = $model.AdapterGradient($adapter, $model.Gradient($inputs, $script:Labels))
        foreach ($value in $own['head.A']) { $value | Should -Be 0 }
        $largest = 0.0
        foreach ($value in $own['head.B']) { $largest = [math]::Max($largest, [math]::Abs($value)) }
        $largest | Should -BeGreaterThan 1e-4
    }

    It 'LoRA with two adapters attached: the gradient of the second is still right' {
        $model = Get-TestModel
        $first = Get-TestAdapter -Model $model -Name 'first'
        $second = $model.NewAdapter('second', 3, 6.0, 11, $true)
        $random = [LambekXorShift]::new(77)
        foreach ($target in $second.Targets) {
            $values = $second.B[$target]
            for ($i = 0; $i -lt $values.Length; $i++) { $values[$i] = 0.1 * $random.NextGaussian() }
        }
        $model.Attach($first)
        $model.Attach($second)
        $check = $model.CheckAdapterGradient($second, (Get-TestInput -Model $model), $script:Labels, 1e-5)
        foreach ($name in $check.Keys) { $check[$name] | Should -BeLessThan 1e-5 -Because $name }
    }
}

Describe 'Transformer: LoRA adapters' {

    It 'a new adapter (B = 0) gives exactly the output of the base' {
        $model = Get-TestModel
        $before = $model.Predict('delete the old files in C:\Temp')
        $adapter = $model.NewAdapter('user', 2, 4.0, 5, $true)
        foreach ($target in $adapter.Targets) { foreach ($value in $adapter.B[$target]) { $value | Should -Be 0 } }
        $model.Attach($adapter)
        (Test-SameBit -Left $model.Predict('delete the old files in C:\Temp') -Right $before) | Should -BeTrue
    }

    It 'an adapter adapts the query and value matrices of each block, and the head when asked' {
        $model = Get-TestModel
        ($model.AdapterTargets($true) -join ' ') | Should -Be 'block0.query block0.value block1.query block1.value head'
        ($model.AdapterTargets($false) -join ' ') | Should -Be 'block0.query block0.value block1.query block1.value'
        $adapter = $model.NewAdapter('user', 2, 4.0, 5, $true)
        $adapter.A['block0.query'].Length | Should -Be (2 * 8)
        $adapter.B['block0.query'].Length | Should -Be (8 * 2)
        $adapter.B['head'].Length | Should -Be (4 * 2)
        $adapter.Scale | Should -Be 2
    }

    It 'an adapter that learned changes the output, and removing it restores the base bit for bit' {
        $model = Get-TestModel
        $before = $model.Predict('copy report.txt')
        $adapter = Get-TestAdapter -Model $model
        $model.Attach($adapter)
        (Test-SameBit -Left $model.Predict('copy report.txt') -Right $before) | Should -BeFalse
        $model.Detach('user') | Should -BeTrue
        (Test-SameBit -Left $model.Predict('copy report.txt') -Right $before) | Should -BeTrue
        $model.Detach('user') | Should -BeFalse
    }

    It 'merging an adapter gives the same output as the adapter attached (to 1e-12)' {
        $model = Get-TestModel
        $adapter = Get-TestAdapter -Model $model
        $model.Attach($adapter)
        $with = $model.Predict('delete the old files in C:\Temp')
        $model.Merge($adapter)
        $model.Adapters.Count | Should -Be 0
        $merged = $model.Predict('delete the old files in C:\Temp')
        for ($i = 0; $i -lt $with.Length; $i++) { [math]::Abs($with[$i] - $merged[$i]) | Should -BeLessThan 1e-12 }
    }

    It 'training an adapter moves A and B only: every weight of the base keeps its bits' {
        $model = Get-TestModel
        $print = $model.Fingerprint()
        $file = $model.Save()
        $adapter = $model.NewAdapter('user', 2, 4.0, 5, $true)
        $model.Attach($adapter)
        $inputs = Get-TestInput -Model $model
        $before = $model.Loss($inputs, $script:Labels)
        $losses = $model.Fit($inputs, $script:Labels, 30, 3, 0.02, $adapter)
        $model.Loss($inputs, $script:Labels) | Should -BeLessThan ($before / 2)
        $losses[29] | Should -BeLessThan $losses[0]
        $model.Fingerprint() | Should -Be $print
        $model.Save() | Should -Be $file
        $moved = 0.0
        foreach ($value in $adapter.B['head']) { $moved += [math]::Abs($value) }
        $moved | Should -BeGreaterThan 0
    }

    It 'the base cannot be trained while an adapter is attached' {
        $model = Get-TestModel
        $model.Attach($model.NewAdapter('user', 2, 4.0, 5, $true))
        { $model.Fit((Get-TestInput -Model $model), $script:Labels, 1, 3, 0.01, $null) } | Should -Throw
    }

    It 'learns one confirmed request in a few steps, keeps it in the adapter, and forgets it when the adapter is removed' {
        $model = Get-TestModel
        $before = $model.Predict('zap the folder')
        $adapter = $model.NewAdapter('user', 2, 4.0, 5, $true)
        $model.Attach($adapter)
        [void] $model.Learn($adapter, 'zap the folder', 'b', 40, 0.02)
        ($adapter.Texts -join '|') | Should -Be 'zap the folder'
        ($adapter.Labels -join '|') | Should -Be 'b'
        $after = $model.Predict('zap the folder')
        $after[1] | Should -BeGreaterThan $before[1]
        [LambekTransformer]::Rank($after)[0] | Should -Be 1
        [void] $model.Detach('user')
        (Test-SameBit -Left $model.Predict('zap the folder') -Right $before) | Should -BeTrue
        { $model.Learn($adapter, 'zap', 'no.such.action', 1, 0.01) } | Should -Throw
    }

    It 'an adapter file read back gives the same adapter, and it is small' {
        $model = Get-TestModel
        $adapter = Get-TestAdapter -Model $model
        $adapter.Texts.Add('zap the folder')
        $adapter.Labels.Add('b')
        $text = $adapter.Save()
        $back = [LambekAdapter]::Load($text)
        $back.Save() | Should -Be $text
        $back.Base | Should -Be $model.Fingerprint()
        $model.Attach($adapter)
        $with = $model.Predict('copy report.txt')
        [void] $model.Detach('user')
        $model.Attach($back)
        (Test-SameBit -Left $model.Predict('copy report.txt') -Right $with) | Should -BeTrue
        $text.Length | Should -BeLessThan $model.Save().Length
        { [LambekAdapter]::Load('{"Format":"other"}') } | Should -Throw
    }

    It 'refuses an adapter of another shape, and two adapters of the same name' {
        $model = Get-TestModel
        $other = [LambekTransformer]::Create(32, 16, 2, 2, 16, 8, [string[]] @('a', 'b', 'c', 'none'), 7, 0.5)
        { $model.Attach($other.NewAdapter('big', 2, 4.0, 5, $true)) } | Should -Throw
        $model.Attach($model.NewAdapter('user', 2, 4.0, 5, $true))
        { $model.Attach($model.NewAdapter('user', 2, 4.0, 6, $true)) } | Should -Throw
    }
}

Describe 'Transformer: training' {

    It 'learns a small set of requests, and the loss goes down' {
        $model = [LambekTransformer]::Create(256, 16, 2, 1, 32, 16, [string[]] @('delete', 'copy', 'none'), 11, 0.0)
        $texts = 'delete the files', 'remove the old files', 'erase everything', 'copy the files', 'duplicate this folder', 'copy it there', 'hello', 'what time is it', 'thanks'
        $labels = [int[]] @(0, 0, 0, 1, 1, 1, 2, 2, 2)
        $inputs = [int[][][]] @(foreach ($text in $texts) { , $model.Encode($text) })
        $losses = $model.Fit($inputs, $labels, 40, 3, 0.01, $null)
        $losses[0] | Should -BeGreaterThan 0.8
        $losses[39] | Should -BeLessThan 0.1
        for ($i = 0; $i -lt $texts.Count; $i++) { [LambekTransformer]::Rank($model.Predict($texts[$i]))[0] | Should -Be $labels[$i] }
        # A typing mistake keeps most of the trigrams of the word
        [LambekTransformer]::Rank($model.Predict('delette the files'))[0] | Should -Be 0
    }

    It 'training twice gives byte-identical files, for the base and for an adapter' {
        $files = foreach ($run in 1, 2) {
            $model = [LambekTransformer]::Create(256, 16, 2, 1, 32, 16, [string[]] @('delete', 'copy', 'none'), 11, 0.0)
            $texts = 'delete the files', 'copy the files', 'hello', 'remove the old files', 'copy it there', 'thanks'
            $labels = [int[]] @(0, 1, 2, 0, 1, 2)
            $inputs = [int[][][]] @(foreach ($text in $texts) { , $model.Encode($text) })
            [void] $model.Fit($inputs, $labels, 10, 2, 0.01, $null)
            $adapter = $model.NewAdapter('user', 2, 4.0, 5, $true)
            $model.Attach($adapter)
            [void] $model.Learn($adapter, 'zap the files', 'delete', 5, 0.01)
            [pscustomobject]@{ Base = $model.Save(); Adapter = $adapter.Save() }
        }
        $files[0].Base | Should -Be $files[1].Base
        $files[0].Adapter | Should -Be $files[1].Adapter
        [System.Text.Encoding]::UTF8.GetBytes($files[0].Base).Length | Should -Be ([System.Text.Encoding]::UTF8.GetBytes($files[1].Base).Length)
        $files[0].Base | Should -Not -Match "`r"
    }

    It 'another seed gives another model' {
        $one = [LambekTransformer]::Create(64, 8, 2, 1, 16, 8, [string[]] @('a', 'none'), 1, 0.5)
        $two = [LambekTransformer]::Create(64, 8, 2, 1, 16, 8, [string[]] @('a', 'none'), 2, 0.5)
        $one.Fingerprint() | Should -Not -Be $two.Fingerprint()
    }

    It 'a model file read back gives the same model: same file, same output, same threshold' {
        $model = Get-TestModel
        $model.Threshold = 0.4375
        $model.Notes['Samples'] = '3'
        $text = $model.Save()
        $back = [LambekTransformer]::Load($text)
        $back.Save() | Should -Be $text
        $back.Threshold | Should -Be 0.4375
        $back.Notes['Samples'] | Should -Be '3'
        (Test-SameBit -Left $back.Predict('copy report.txt') -Right $model.Predict('copy report.txt')) | Should -BeTrue
        { [LambekTransformer]::Load('{"Format":"other"}') } | Should -Throw
    }

    It 'a request longer than the model reads is cut, not refused' {
        $model = Get-TestModel
        $model.Encode('a b c d e f g h i j k l m n').Length | Should -Be 8
        $model.Predict('a b c d e f g h i j k l m n').Length | Should -Be 4
    }

    It 'the variations of a sentence are the same for the same seed' {
        $words = [string[]] @('delete', 'the', 'old', 'files')
        $one = [LambekTransformerText]::Vary($words, [LambekXorShift]::new(5), $null, [string[]] @('supprimer'))
        $two = [LambekTransformerText]::Vary($words, [LambekXorShift]::new(5), $null, [string[]] @('supprimer'))
        ($one -join ' ') | Should -Be ($two -join ' ')
        [LambekTransformerText]::Misspell('the', [LambekXorShift]::new(5)) | Should -Be 'the'
        [LambekTransformerText]::Misspell('<path>', [LambekXorShift]::new(5)) | Should -Be '<path>'
        [LambekTransformerText]::Misspell('delete', [LambekXorShift]::new(5)) | Should -Not -Be 'delete'
    }
}

Describe 'Proposer: Optimize-LambekProposer and Get-LambekProposal' {

    BeforeAll {
        # A small proposer trained here on the packs alone (few variations, few passes), in its own folder
        $script:Folder = Join-Path $TestDrive 'proposer'
        New-Item -ItemType Directory -Path $script:Folder -Force | Out-Null
        $script:SmallFile = Join-Path $script:Folder 'proposer.json'
        $script:SmallAdapter = Join-Path $script:Folder 'adapter.json'
        $script:Report = InModuleScope Lambek -Parameters @{ File = $script:SmallFile } {
            param($File)
            Optimize-LambekProposer -OutFile $File -Variations 2 -Epochs 4 -Dimension 16
        }
    }

    It 'trains on the examples of the packs and writes a file with every action and "none"' {
        Test-Path -LiteralPath $script:SmallFile | Should -BeTrue
        $script:Report.Classes | Should -Contain 'files.delete'
        $script:Report.Classes | Should -Contain 'code.generate'
        $script:Report.Classes[-1] | Should -Be 'none'
        $script:Report.Samples | Should -BeGreaterThan $script:Report.Seeds
        $model = [LambekTransformer]::Load([System.IO.File]::ReadAllText($script:SmallFile))
        $model.Dim | Should -Be 16
        $model.Notes['HeldOutSource'] | Should -Be 'variations'
    }

    It 'the same call writes the same bytes' {
        $again = Join-Path $script:Folder 'again.json'
        InModuleScope Lambek -Parameters @{ File = $again } { param($File) Optimize-LambekProposer -OutFile $File -Variations 2 -Epochs 4 -Dimension 16 } | Out-Null
        $one = [System.IO.File]::ReadAllBytes($script:SmallFile)
        $two = [System.IO.File]::ReadAllBytes($again)
        [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($two)) | Should -Be ([Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($one)))
    }

    It 'gives nothing when the proposer file is absent' {
        $found = InModuleScope Lambek -Parameters @{ File = (Join-Path $script:Folder 'absent.json') } { param($File) Get-LambekProposal -Text 'delete the files' -Path $File }
        $found | Should -BeNullOrEmpty
    }

    It 'gives the best actions with probabilities and an example sentence in the language of the text' {
        $found = InModuleScope Lambek -Parameters @{ File = $script:SmallFile; Adapter = $script:SmallAdapter } {
            param($File, $Adapter)
            Get-LambekProposal -Text 'supprimer les fichiers' -Threshold 0 -Path $File -AdapterPath $Adapter
        }
        $found.Action | Should -Be 'files.delete'
        $found.Language | Should -Be 'fr'
        $found.Example | Should -Be 'supprimer des fichiers'
        $found.Candidates.Count | Should -Be 3
        $found.Candidates[0].Action | Should -Be 'files.delete'
        $found.Candidates[0].Probability | Should -BeGreaterOrEqual $found.Candidates[1].Probability
        $found.Candidates.Action | Should -Not -Contain 'none'
    }

    It 'gives nothing under the threshold, and nothing for an empty text' {
        $found = InModuleScope Lambek -Parameters @{ File = $script:SmallFile; Adapter = $script:SmallAdapter } {
            param($File, $Adapter)
            Get-LambekProposal -Text 'supprimer les fichiers' -Threshold 1.01 -Path $File -AdapterPath $Adapter
            Get-LambekProposal -Text '   ' -Threshold 0 -Path $File -AdapterPath $Adapter
        }
        $found | Should -BeNullOrEmpty
    }

    It 'the adapter of the user learns a confirmed request without touching the base, and removing its file forgets it' {
        $base = [System.IO.File]::ReadAllBytes($script:SmallFile)
        $before = [LambekTransformer]::Load([System.IO.File]::ReadAllText($script:SmallFile)).Predict('zorglub the thingies')
        $learned = InModuleScope Lambek -Parameters @{ File = $script:SmallFile; Adapter = $script:SmallAdapter } {
            param($File, $Adapter)
            Add-LambekProposalExample -Text 'zorglub the thingies' -Action 'files.rename' -Steps 40 -Path $File -AdapterPath $Adapter
        }
        $learned.Examples | Should -Be 1
        Test-Path -LiteralPath $script:SmallAdapter | Should -BeTrue
        (Get-Item -LiteralPath $script:SmallAdapter).Length | Should -BeLessThan ((Get-Item -LiteralPath $script:SmallFile).Length / 4)
        $found = InModuleScope Lambek -Parameters @{ File = $script:SmallFile; Adapter = $script:SmallAdapter } {
            param($File, $Adapter)
            Get-LambekProposal -Text 'zorglub the thingies' -Threshold 0 -Path $File -AdapterPath $Adapter
        }
        $found.Action | Should -Be 'files.rename'

        # The base file did not change by one byte
        $after = [System.IO.File]::ReadAllBytes($script:SmallFile)
        [Convert]::ToHexString($after) | Should -Be ([Convert]::ToHexString($base))

        # Exact unlearning: without the adapter file the output is the output of the base, bit for bit
        Remove-Item -LiteralPath $script:SmallAdapter
        $model = InModuleScope Lambek -Parameters @{ File = $script:SmallFile; Adapter = $script:SmallAdapter } {
            param($File, $Adapter)
            Get-LambekProposerModel -Path $File -AdapterPath $Adapter
        }
        $model.Adapters.Count | Should -Be 0
        (Test-SameBit -Left $model.Predict('zorglub the thingies') -Right $before) | Should -BeTrue
    }

    It 'an adapter trained on another base is left aside' {
        $other = [LambekTransformer]::Load([System.IO.File]::ReadAllText($script:SmallFile))
        $other.Weights['head.bias'][0] += 1.0
        $stranger = $other.NewAdapter('user', 4, 8.0, 2021, $true)
        $file = Join-Path $script:Folder 'stranger.json'
        [System.IO.File]::WriteAllText($file, $stranger.Save())
        $model = InModuleScope Lambek -Parameters @{ File = $script:SmallFile; Adapter = $file } { param($File, $Adapter) Get-LambekProposerModel -Path $File -AdapterPath $Adapter }
        $model.Adapters.Count | Should -Be 0
    }
}

Describe 'Proposer: the trained file that comes with the module' {

    It 'is a proposer file with a fitted threshold and the actions of the packs' {
        if (-not (Test-Path -LiteralPath $script:ProposerFile)) { Set-ItResult -Skipped -Because 'Data/proposer.json is absent: the proposer is optional'; return }
        $model = [LambekTransformer]::Load([System.IO.File]::ReadAllText($script:ProposerFile))
        $model.Classes | Should -Contain 'files.delete'
        $model.Classes[-1] | Should -Be 'none'
        $model.Threshold | Should -BeGreaterThan 0
        $model.Threshold | Should -BeLessOrEqual 1
        [double]::Parse($model.Notes['HeldOutPrecision'], [cultureinfo]::InvariantCulture) | Should -BeGreaterOrEqual 0.9
    }

    It 'proposes <Action> for "<Text>"' -ForEach @(
        @{ Text = 'delet the fils in C:\Temp'; Action = 'files.delete'; Language = 'en' }
        @{ Text = 'suprime les fichiers .log dans C:\Temp'; Action = 'files.delete'; Language = 'fr' }
        @{ Text = 'copiar los archivos de C:\A a D:\B'; Action = 'files.copy'; Language = 'es' }
    ) {
        if (-not (Test-Path -LiteralPath $script:ProposerFile)) { Set-ItResult -Skipped -Because 'Data/proposer.json is absent: the proposer is optional'; return }
        $found = InModuleScope Lambek -Parameters @{ Text = $Text; Adapter = (Join-Path $TestDrive 'no-adapter.json') } {
            param($Text, $Adapter)
            Get-LambekProposal -Text $Text -Threshold 0 -AdapterPath $Adapter
        }
        $found.Action | Should -Be $Action
        $found.Example | Should -Not -BeNullOrEmpty
    }

    It 'proposes nothing for a request that asks for no action' {
        if (-not (Test-Path -LiteralPath $script:ProposerFile)) { Set-ItResult -Skipped -Because 'Data/proposer.json is absent: the proposer is optional'; return }
        $found = InModuleScope Lambek -Parameters @{ Adapter = (Join-Path $TestDrive 'no-adapter.json') } {
            param($Adapter)
            Get-LambekProposal -Text 'what is the weather today' -AdapterPath $Adapter
        }
        $found | Should -BeNullOrEmpty
    }

    It 'answers in well under 5 ms once loaded' {
        if (-not (Test-Path -LiteralPath $script:ProposerFile)) { Set-ItResult -Skipped -Because 'Data/proposer.json is absent: the proposer is optional'; return }
        $model = [LambekTransformer]::Load([System.IO.File]::ReadAllText($script:ProposerFile))
        for ($i = 0; $i -lt 20; $i++) { [void] $model.Predict('delete the .log files older than 30 days in C:\Temp') }
        # The best of several rounds: another program on the machine must not fail the test
        $best = [double]::MaxValue
        for ($round = 0; $round -lt 5; $round++) {
            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt 20; $i++) { [void] $model.Predict('delete the .log files older than 30 days in C:\Temp') }
            $best = [math]::Min($best, $clock.Elapsed.TotalMilliseconds / 20)
        }
        $best | Should -BeLessThan 5
    }
}
