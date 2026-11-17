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
        @{ Name = 'one more than another, through a third'; Premises = 'compare(more|grand|name:rex|name:max)|', 'compare(more|grand|name:max|name:tom)|'; Conclusion = 'compare(more|grand|name:rex|name:tom)' }
        @{ Name = 'one not more than the one more than it'; Premises = 'compare(more|grand|name:rex|name:max)|', 'compare(more|grand|name:max|name:tom)|'; Conclusion = 'compare(notmore|grand|name:tom|name:rex)' }
        @{ Name = 'so, more so than one that is'; Premises = 'compare(more|grand|name:rex|name:max)|', 'compare(more|grand|name:max|name:tom)|', 'category(is|name:tom|grand)|'; Conclusion = 'category(is|name:rex|grand)' }
        @{ Name = 'not so, less so than one that is not'; Premises = 'compare(more|grand|name:rex|name:max)|', 'category(isnot|name:rex|grand)|'; Conclusion = 'category(isnot|name:max|grand)' }
        @{ Name = 'one of two, not the other'; Premises = 'category(is|name:rex|or:chat;chien)|', 'category(isnot|name:rex|chat)|'; Conclusion = 'category(is|name:rex|chien)' }
        @{ Name = 'at least so many, of fewer'; Premises = 'count(least|3|chat|noir)|'; Conclusion = 'count(least|2|chat|noir)' }
        @{ Name = 'at least so many of a narrower kind, of the wider'; Premises = 'count(least|3|siamois|noir)|', 'category(all|siamois|chat)|'; Conclusion = 'count(least|3|chat|noir)' }
        @{ Name = 'at most so many, not at least more'; Premises = 'count(most|2|chat|noir)|', 'category(all|siamois|chat)|'; Conclusion = 'count(notleast|3|siamois|noir)' }
        @{ Name = 'exactly so many, not more'; Premises = 'count(exactly|2|chat|noir)|'; Conclusion = 'count(notleast|3|chat|noir)' }
        @{ Name = 'at least so many, more than fewer'; Premises = 'count(least|3|chat|noir)|'; Conclusion = 'count(notmost|2|chat|noir)' }
        @{ Name = 'a rule told with if about one named'; Premises = 'category(if|is~name:rex~chien|does~name:rex~v:aboyer)|', 'category(is|name:rex|chien)|'; Conclusion = 'category(does|name:rex|v:aboyer)' }
        @{ Name = 'a rule told with if, the other way'; Premises = 'category(if|is~name:rex~chien|does~name:rex~v:aboyer)|', 'category(doesnot|name:rex|v:aboyer)|'; Conclusion = 'category(isnot|name:rex|chien)' }
        @{ Name = 'a rule told with if, from one to another'; Premises = 'category(if|is~name:rex~chien|is~name:max~chat)|', 'category(is|name:rex|chien)|'; Conclusion = 'category(is|name:max|chat)' }
        @{ Name = 'a rule told with if, through what a kind is'; Premises = 'category(if|is~name:rex~animal|does~name:rex~v:manger)|', 'category(all|chien|animal)|', 'category(is|name:rex|chien)|'; Conclusion = 'category(does|name:rex|v:manger)' }
        @{ Name = 'what one believes, from what that one believes'; Premises = 'category(believe|name:alice|all~chat~noir)|', 'category(believe|name:alice|is~name:tom~chat)|'; Conclusion = 'category(believe|name:alice|is~name:tom~noir)' }
        @{ Name = 'what holds in each of two'; Premises = 'category(is|name:rex|or:chat;chien)|', 'category(all|chat|animal)|', 'category(all|chien|animal)|'; Conclusion = 'category(is|name:rex|animal)' }
        @{ Name = 'a rule of one of two, and not the one'; Premises = 'category(all|chat|or:blanc;noir)|', 'category(is|name:tom|chat)|', 'category(isnot|name:tom|noir)|'; Conclusion = 'category(is|name:tom|blanc)' }
        @{ Name = 'one of two, asked of both'; Premises = 'category(is|name:rex|or:chat;chien)|'; Conclusion = 'category(is|name:rex|or:chat;chien)' }
        @{ Name = 'none of two'; Premises = 'category(no|chien|chat)|', 'category(is|name:rex|chien)|', 'category(no|chien|cheval)|'; Conclusion = 'category(isnot|name:rex|or:chat;cheval)' }
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
        @{ Name = 'more, the other way round'; Premises = 'compare(more|grand|name:rex|name:max)|'; Conclusion = 'compare(more|grand|name:max|name:rex)' }
        @{ Name = 'more in another way'; Premises = 'compare(more|grand|name:rex|name:max)|'; Conclusion = 'compare(more|fort|name:rex|name:max)' }
        @{ Name = 'a way broken in the middle'; Premises = 'compare(more|grand|name:rex|name:max)|', 'compare(more|grand|name:paul|name:tom)|'; Conclusion = 'compare(more|grand|name:rex|name:tom)' }
        @{ Name = 'so, less so than one that is'; Premises = 'compare(more|grand|name:max|name:rex)|', 'category(is|name:max|grand)|'; Conclusion = 'category(is|name:rex|grand)' }
        @{ Name = 'so, more so in another way'; Premises = 'compare(more|fort|name:rex|name:max)|', 'category(is|name:max|grand)|'; Conclusion = 'category(is|name:rex|grand)' }
        @{ Name = 'one of two, said as the first'; Premises = 'category(is|name:rex|or:chat;chien)|'; Conclusion = 'category(is|name:rex|chien)' }
        @{ Name = 'at least so many, of more'; Premises = 'count(least|3|chat|noir)|'; Conclusion = 'count(least|4|chat|noir)' }
        @{ Name = 'at least so many of a wider kind, of the narrower'; Premises = 'count(least|3|chat|noir)|', 'category(all|siamois|chat)|'; Conclusion = 'count(least|3|siamois|noir)' }
        @{ Name = 'at most so many of a narrower kind, of the wider'; Premises = 'count(most|2|siamois|noir)|', 'category(all|siamois|chat)|'; Conclusion = 'count(notleast|3|chat|noir)' }
        @{ Name = 'a rule told with if whose condition was not told'; Premises = 'category(if|is~name:rex~chien|does~name:rex~v:aboyer)|'; Conclusion = 'category(does|name:rex|v:aboyer)' }
        @{ Name = 'a rule told with if, from what follows'; Premises = 'category(if|is~name:rex~chien|does~name:rex~v:aboyer)|', 'category(does|name:rex|v:aboyer)|'; Conclusion = 'category(is|name:rex|chien)' }
        @{ Name = 'a rule told with if, about another'; Premises = 'category(if|is~name:rex~chien|is~name:max~chat)|', 'category(is|name:rex|chien)|'; Conclusion = 'category(is|name:rex|chat)' }
        @{ Name = 'what one believes, from what is so'; Premises = 'category(all|chat|noir)|', 'category(believe|name:alice|is~name:tom~chat)|'; Conclusion = 'category(believe|name:alice|is~name:tom~noir)' }
        @{ Name = 'what one believes, from what another believes'; Premises = 'category(believe|name:paul|all~chat~noir)|', 'category(believe|name:alice|is~name:tom~chat)|'; Conclusion = 'category(believe|name:alice|is~name:tom~noir)' }
        @{ Name = 'what is so, from what one believes'; Premises = 'category(believe|name:alice|is~name:tom~chat)|'; Conclusion = 'category(is|name:tom|chat)' }
        @{ Name = 'what holds in one of two only'; Premises = 'category(is|name:rex|or:chat;chien)|', 'category(all|chien|animal)|'; Conclusion = 'category(is|name:rex|animal)' }
        @{ Name = 'none of two, one of them left'; Premises = 'category(is|name:rex|chien)|', 'category(no|chien|chat)|'; Conclusion = 'category(isnot|name:rex|or:chat;cheval)' }
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
