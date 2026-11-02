BeforeAll {
    # The checker shares no code with Lambek: it is loaded alone, without the module
    . "$PSScriptRoot/../Lambek/Checker/Test-LambekProof.ps1"
}

Describe 'The checker of proofs' {

    It 'accepts what follows: <Name>' -ForEach @(
        @{ Name = 'a syllogism'; Premises = 'category(all|homme|mortel)|', 'category(is|name:socrate|homme)|'; Conclusion = 'category(is|name:socrate|mortel)' }
        @{ Name = 'what no one of a kind is'; Premises = 'category(no|poisson|mammifere)|', 'category(is|name:nemo|poisson)|'; Conclusion = 'category(isnot|name:nemo|mammifere)' }
        @{ Name = 'a kind in a wider kind'; Premises = 'category(all|chat|mammifere)|', 'category(all|mammifere|animal)|'; Conclusion = 'category(all|chat|animal)' }
        @{ Name = 'what is supposed'; Premises = 'category(usual:all|oiseau|v:voler)|', 'category(is|name:tweety|oiseau)|'; Conclusion = 'category(usual:is|name:tweety|v:voler)' }
        @{ Name = 'a rule told with if'; Premises = 'if(cond(pleuvoir(agent("il"))), then(prendre(agent(speaker), object("le bus"))))|', 'pleuvoir(agent("il"))|'; Conclusion = 'prendre(agent(speaker), object("le bus"))|' }
        @{ Name = 'a thing told, recalled'; Premises = 'habiter(agent("ma soeur"), a("Lyon"))|'; Conclusion = 'habiter(agent("ma soeur"), a("Lyon"))|' }
        @{ Name = 'what one is not, from what its kind is'; Premises = 'category(all|chat|noir)|', 'category(isnot|speaker|noir)|'; Conclusion = 'category(isnot|speaker|chat)' }
        @{ Name = 'no one of a kind, from what it is'; Premises = 'category(all|chat|noir)|', 'category(no|corbeau|noir)|'; Conclusion = 'category(no|corbeau|chat)' }
        @{ Name = 'what one does not do, recalled'; Premises = 'category(doesnot|name:tweety|v:voler)|'; Conclusion = 'category(isnot|name:tweety|v:voler)' }
        @{ Name = 'a rule with a condition in the negative'; Premises = 'if(cond(not(pleuvoir(agent("il")))), then(prendre(agent(speaker), object("le velo"))))|', 'not(pleuvoir(agent("il")))|'; Conclusion = 'prendre(agent(speaker), object("le velo"))|' }
    ) {
        $check = Test-LambekProof -Premises $Premises -Conclusions $Conclusion -Each
        $check.Holds | Should -BeTrue -Because $check.Reason
        $check.Unneeded | Should -BeNullOrEmpty
    }

    It 'refuses what does not follow: <Name>' -ForEach @(
        @{ Name = 'a premise missing'; Premises = 'category(all|homme|mortel)|'; Conclusion = 'category(is|name:socrate|mortel)' }
        @{ Name = 'the opposite answer'; Premises = 'category(no|poisson|mammifere)|', 'category(is|name:nemo|poisson)|'; Conclusion = 'category(is|name:nemo|mammifere)' }
        @{ Name = 'what is only supposed, said as sure'; Premises = 'category(usual:all|oiseau|v:voler)|', 'category(is|name:tweety|oiseau)|'; Conclusion = 'category(is|name:tweety|v:voler)' }
        @{ Name = 'what a narrower kind rules out'; Premises = 'category(usual:all|oiseau|v:voler)|', 'category(no|pingouin|v:voler)|', 'category(all|pingouin|oiseau)|', 'category(is|name:pingu|pingouin)|'; Conclusion = 'category(usual:is|name:pingu|v:voler)' }
        @{ Name = 'a rule whose condition was not told'; Premises = 'if(cond(pleuvoir(agent("il"))), then(prendre(agent(speaker), object("le bus"))))|'; Conclusion = 'prendre(agent(speaker), object("le bus"))|' }
        @{ Name = 'another thing than the one told'; Premises = 'habiter(agent("ma soeur"), a("Lyon"))|'; Conclusion = 'habiter(agent("ma soeur"), a("Paris"))|' }
        @{ Name = 'what one is not, from what it is not'; Premises = 'category(all|chat|noir)|', 'category(isnot|name:tom|chat)|'; Conclusion = 'category(isnot|name:tom|noir)' }
        @{ Name = 'a condition in the negative, from its opposite'; Premises = 'if(cond(not(pleuvoir(agent("il")))), then(prendre(agent(speaker), object("le velo"))))|', 'pleuvoir(agent("il"))|'; Conclusion = 'prendre(agent(speaker), object("le velo"))|' }
    ) {
        (Test-LambekProof -Premises $Premises -Conclusions $Conclusion).Holds | Should -BeFalse
    }

    It 'lets the rule about a narrower kind go first' {
        $premises = 'category(usual:all|oiseau|v:voler)|', 'category(usual:no|pingouin|v:voler)|', 'category(all|pingouin|oiseau)|', 'category(is|name:pingu|pingouin)|'
        (Test-LambekProof -Premises $premises -Conclusions 'category(usual:isnot|name:pingu|v:voler)').Holds | Should -BeTrue
    }

    It 'says which premise was not needed' {
        $premises = 'category(all|homme|mortel)|', 'category(is|name:socrate|homme)|', 'category(is|name:tom|chat)|'
        (Test-LambekProof -Premises $premises -Conclusions 'category(is|name:socrate|mortel)' -Each).Unneeded | Should -Be @('category(is|name:tom|chat)|')
    }

    It 'says what it does not check, instead of passing it' {
        (Test-LambekProof -Premises 'category(some|oiseau|v:voler)|' -Conclusions 'category(some|oiseau|v:voler)').Holds | Should -BeNullOrEmpty
        (Test-LambekProof -Premises 'category(all|homme|mortel)|' -Conclusions @()).Holds | Should -BeNullOrEmpty
    }
}

Describe 'The checker of sums' {

    It 'works out again a sum an answer shows: <Text>' -ForEach @(
        @{ Text = '2 + 3 = 5'; Holds = $true }
        @{ Text = '2 + 3 = 6'; Holds = $false }
        @{ Text = '2,5 + 1 = 3,5'; Holds = $true }
        @{ Text = '0.33 + 0.33 = 0.67'; Holds = $true }
        @{ Text = '0.33 + 0.33 = 0.7'; Holds = $false }
        @{ Text = '1 000 + 24 = 1 024'; Holds = $true }
    ) {
        Test-LambekCalculation -Text $Text | Should -Be $Holds
    }

    It 'says what is not a sum, instead of passing it' {
        Test-LambekCalculation -Text 'deux plus trois' | Should -BeNullOrEmpty
        Test-LambekCalculation -Text '5 = 5' | Should -BeNullOrEmpty
    }
}

Describe 'An answer the checker refuses' {

    BeforeAll {
        Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    }

    It 'is not said: Lambek says it cannot prove it, and keeps no proof' {
        InModuleScope Lambek {
            $script:Told = $null; $script:LastProofs = $null
            $facts = @(
                [pscustomobject]@{ Core = 'category(all|homme|mortel)|' }
                [pscustomobject]@{ Core = 'category(is|name:socrate|homme)|' }
            )
            Set-LambekLastProof -Facts $facts -Conclusion 'category(isnot|name:socrate|mortel)'
            Confirm-LambekProof -Reply 'Non : Socrate n''est pas mortel.' -Language fr | Should -BeLike 'Je ne sais pas*prouver*'
            Get-LambekLastProof | Should -BeNullOrEmpty

            Set-LambekLastProof -Facts $facts -Conclusion 'category(is|name:socrate|mortel)'
            Confirm-LambekProof -Reply 'Oui : Socrate est mortel.' -Language fr | Should -Be 'Oui : Socrate est mortel.'
            Get-LambekLastProof | Should -Not -BeNullOrEmpty
        }
    }

    It 'is not said when its sum is wrong' {
        InModuleScope Lambek {
            $script:Told = $null; $script:LastProofs = $null
            Set-LambekLastProof -Facts @([pscustomobject]@{ Core = 'avoir(agent("ma soeur"), object("2 chats"))|' }) -Calculation '2 + 3 = 6'
            Confirm-LambekProof -Reply '6 chats en tout.' -Language fr | Should -BeLike 'Je ne sais pas*'
        }
    }

    It 'still says what the checker does not know how to check' {
        InModuleScope Lambek {
            $script:Told = $null; $script:LastProofs = $null
            Set-LambekLastProof -Facts @([pscustomobject]@{ Core = 'category(some|oiseau|v:voler)|' }) -Conclusion 'category(some|oiseau|v:voler)'
            Confirm-LambekProof -Reply 'Oui : certains oiseaux volent.' -Language fr | Should -Be 'Oui : certains oiseaux volent.'
        }
    }
}
