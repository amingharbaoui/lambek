BeforeAll {
    # The checker shares no code with Lambek: it is loaded alone, without the module
    . "$PSScriptRoot/../../tools/Test-LambekProof.ps1"
}

Describe 'The checker of proofs' {

    It 'accepts what follows: <Name>' -ForEach @(
        @{ Name = 'a syllogism'; Premises = 'category(all|homme|mortel)|', 'category(is|name:socrate|homme)|'; Conclusion = 'category(is|name:socrate|mortel)' }
        @{ Name = 'what no one of a kind is'; Premises = 'category(no|poisson|mammifere)|', 'category(is|name:nemo|poisson)|'; Conclusion = 'category(isnot|name:nemo|mammifere)' }
        @{ Name = 'a kind in a wider kind'; Premises = 'category(all|chat|mammifere)|', 'category(all|mammifere|animal)|'; Conclusion = 'category(all|chat|animal)' }
        @{ Name = 'what is supposed'; Premises = 'category(usual:all|oiseau|v:voler)|', 'category(is|name:tweety|oiseau)|'; Conclusion = 'category(usual:is|name:tweety|v:voler)' }
        @{ Name = 'a rule told with if'; Premises = 'if(cond(pleuvoir(agent("il"))), then(prendre(agent(speaker), object("le bus"))))|', 'pleuvoir(agent("il"))|'; Conclusion = 'prendre(agent(speaker), object("le bus"))|' }
        @{ Name = 'a thing told, recalled'; Premises = 'habiter(agent("ma soeur"), a("Lyon"))|'; Conclusion = 'habiter(agent("ma soeur"), a("Lyon"))|' }
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
