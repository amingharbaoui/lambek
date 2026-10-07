BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null
    $benchmark = "$PSScriptRoot/../../bench/requests.json"

    function New-TestBenchmark {
        param([object[]] $Cases)

        $path = Join-Path $TestDrive "$([guid]::NewGuid()).json"
        @{ Version = '1.0'; Cases = $Cases } | ConvertTo-Json -Depth 10 | Set-Content -Path $path
        return $path
    }
}

Describe 'Benchmark guarantees on the test split' {

    BeforeAll {
        $report = Invoke-LambekBenchmark -Path $benchmark -Split test
    }

    It 'never accepts a wrong action' {
        $details = ($report.Failures | Where-Object Outcome -EQ 'Wrong' | ForEach-Object { $_.Text }) -join ' | '
        $report.WrongActionRate | Should -Be 0 -Because $details
    }

    It 'gives the same card on every run' {
        $report.Determinism | Should -Be 1
    }

    It 'recognizes at least 90 percent of the requests it should run' {
        $report.RecognitionRate | Should -BeGreaterOrEqual 0.9
    }

    It 'never runs an out-of-domain request' {
        $outside = $report.ByTag | Where-Object Tag -EQ 'out-of-domain'
        $outside.Wrong | Should -Be 0
    }
}

Describe 'Benchmark scoring' {

    It 'counts a right card as Correct' {
        $path = New-TestBenchmark @(@{
                Id = 'T1'; Split = 'test'; Text = 'delete the .log files in C:\Temp'; Tags = @('delete')
                Expected = @{ Status = 'Ready'; Action = 'files.delete'; Parameters = @{ Path = 'C:\Temp'; Extension = '.log' } }
            })
        (Invoke-LambekBenchmark -Path $path).Correct | Should -Be 1
    }

    It 'counts another action as Wrong' {
        $path = New-TestBenchmark @(@{
                Id = 'T1'; Split = 'test'; Text = 'delete the .log files in C:\Temp'; Tags = @('delete')
                Expected = @{ Status = 'Ready'; Action = 'files.list'; Parameters = @{ Path = 'C:\Temp'; Extension = '.log' } }
            })
        (Invoke-LambekBenchmark -Path $path).Wrong | Should -Be 1
    }

    It 'counts a wrong parameter as Wrong' {
        $path = New-TestBenchmark @(@{
                Id = 'T1'; Split = 'test'; Text = 'delete the .log files in C:\Temp'; Tags = @('delete')
                Expected = @{ Status = 'Ready'; Action = 'files.delete'; Parameters = @{ Path = 'C:\Other'; Extension = '.log' } }
            })
        (Invoke-LambekBenchmark -Path $path).Wrong | Should -Be 1
    }

    It 'counts a question as Clarified, not Wrong' {
        $path = New-TestBenchmark @(@{
                Id = 'T1'; Split = 'test'; Text = 'zap the .log files in C:\Temp'; Tags = @('paraphrase')
                Expected = @{ Status = 'Ready'; Action = 'files.delete'; Parameters = @{ Path = 'C:\Temp'; Extension = '.log' } }
            })
        $report = Invoke-LambekBenchmark -Path $path
        $report.Clarified | Should -Be 1
        $report.Wrong | Should -Be 0
    }

    It 'counts acting on an unknown request as Wrong' {
        $path = New-TestBenchmark @(@{
                Id = 'T1'; Split = 'test'; Text = 'delete the .log files in C:\Temp'; Tags = @('x')
                Expected = @{ Status = 'Unknown' }
            })
        (Invoke-LambekBenchmark -Path $path).Wrong | Should -Be 1
    }

    It 'rejects a split without cases' {
        $path = New-TestBenchmark @(@{
                Id = 'T1'; Split = 'test'; Text = 'hello'; Tags = @('x'); Expected = @{ Status = 'Unknown' }
            })
        { Invoke-LambekBenchmark -Path $path -Split calibration } | Should -Throw '*No benchmark case*'
    }
}

Describe 'Optimize-LambekScoring' {

    BeforeAll {
        $path = New-TestBenchmark @(
            @{ Id = 'C1'; Split = 'calibration'; Text = 'delete the .log files in C:\Temp'; Tags = @('x')
                Expected = @{ Status = 'Ready'; Action = 'files.delete'; Parameters = @{ Path = 'C:\Temp'; Extension = '.log' } } }
            @{ Id = 'C2'; Split = 'calibration'; Text = 'what is the weather'; Tags = @('x'); Expected = @{ Status = 'Unknown' } }
        )
    }

    It 'finds settings without wrong actions' {
        $result = Optimize-LambekScoring -Path $path -GrammarWeight 0.4 -CosineShare 0.3 -Threshold 0.4, 0.5 -Margin 0.05
        $result.Tried | Should -Be 2
        $result.Metrics.Wrong | Should -Be 0
    }

    It 'prefers the most cautious threshold when results are equal' {
        $result = Optimize-LambekScoring -Path $path -GrammarWeight 0.4 -CosineShare 0.3 -Threshold 0.4, 0.5 -Margin 0.05
        $result.Scoring.Threshold | Should -Be 0.5
    }

    It 'writes weights that add up to 1' {
        $out = Join-Path $TestDrive 'scoring.json'
        Optimize-LambekScoring -Path $path -GrammarWeight 0.35 -CosineShare 0.4 -Threshold 0.45 -Margin 0.05 -OutFile $out | Out-Null

        $saved = Get-Content $out -Raw | ConvertFrom-Json
        $total = $saved.Weights.Grammar + $saved.Weights.Cosine + $saved.Weights.WordJaccard + $saved.Weights.NGramJaccard + $saved.Weights.Edit
        [math]::Round($total, 4) | Should -Be 1
    }
}
