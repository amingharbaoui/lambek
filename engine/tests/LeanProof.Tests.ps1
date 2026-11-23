BeforeDiscovery {
    $script:HasLean = [bool] (Get-Command -Name lean -CommandType Application -ErrorAction SilentlyContinue)
}

BeforeAll {
    # Written for Lean with nothing from Lambek: the file is loaded alone, without the module
    . "$PSScriptRoot/../../tools/ConvertTo-LambekLean.ps1"
    $script:Prove = {
        param([string] $Text)
        $file = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).lean"
        Set-Content -LiteralPath $file -Value $Text -Encoding utf8NoBOM
        $null = & lean $file 2>&1
        $LASTEXITCODE -eq 0
    }
}

Describe 'A proof written for Lean' {

    It 'gives the premises as hypotheses and the conclusion as the goal' {
        $lean = ConvertTo-LambekLean -Name 'M054' -Premises 'category(all|homme|mortel)|', 'category(is|name:socrate|homme)|' -Conclusions 'category(is|name:socrate|mortel)'
        $lean.Theorem | Should -BeLike '*theorem proof_M054 (T : Type) (c0 : T)*'
        $lean.Theorem | Should -BeLike '*(h0 : forall x, k1 x -> k0 x) (h1 : k1 c0) :*(k0 c0) := by*'
        $lean.Theorem | Should -BeLike '*-- k1: homme*'
        $lean.Opposite | Should -BeLike '*theorem opposite_M054*(Not (k0 c0)) := by*'
    }

    It 'writes a rule told with if, and the things told, as propositions' {
        $lean = ConvertTo-LambekLean -Name 'bus' -Premises 'if(cond(pleuvoir(agent("il"))), then(prendre(agent(speaker), object("le bus"))))|', 'pleuvoir(agent("il"))|' -Conclusions 'prendre(agent(speaker), object("le bus"))|'
        $lean.Theorem | Should -BeLike '*(h0 : p0 -> p1) (h1 : p0) :*(p1) := by*'
    }

    It 'makes one of a narrower kind an exception to a rule that holds normalement' {
        $premises = 'category(usual:all|oiseau|v:voler)|', 'category(no|pingouin|v:voler)|', 'category(all|pingouin|oiseau)|', 'category(usual:no|manchot|v:voler)|', 'category(all|manchot|oiseau)|', 'category(is|name:pingu|manchot)|'
        $lean = ConvertTo-LambekLean -Name 'pingu' -Premises $premises -Conclusions 'category(usual:isnot|name:pingu|v:voler)'
        $lean.Theorem | Should -BeLike '*forall x, k1 x -> Not (ab0 x) -> k0 x*'
        # (the rule about the narrower kind makes its members exceptions to the wider one; one is assumed no exception
        # to the rule that says what is concluded)
        $lean.Theorem | Should -BeLike '*forall x, k3 x -> ab0 x*'
        $lean.Theorem | Should -BeLike '*Not (ab1 c0)) :*'
    }

    It 'writes one more than another as an order, and links it to the kind of the same word' {
        $lean = ConvertTo-LambekLean -Name 'rex' -Premises 'compare(more|grand|name:rex|name:max)|', 'category(is|name:max|grand)|' -Conclusions 'category(is|name:rex|grand)'
        $lean.Theorem | Should -BeLike '*(r0 : T -> T -> Prop)*'
        $lean.Theorem | Should -BeLike '*(h0 : r0 c0 c1)*'
        $lean.Theorem | Should -BeLike '*forall x y z, r0 x y -> r0 y z -> r0 x z*'
        $lean.Theorem | Should -BeLike '*forall x y, r0 x y -> k0 y -> k0 x*'
    }

    It 'writes one of several kinds with or' {
        $lean = ConvertTo-LambekLean -Name 'rex' -Premises 'category(is|name:rex|or:chat&noir;chien)|', 'category(isnot|name:rex|chien)|' -Conclusions 'category(is|name:rex|chat)'
        $lean.Theorem | Should -BeLike '*(h0 : ((k0 c0 /\ k1 c0) \/ (k2 c0)))*'
        $lean.Theorem | Should -BeLike '*(h1 : Not (k2 c0))*'
    }

    It 'does not write what it cannot: <Name>' -ForEach @(
        @{ Name = 'some'; Premises = 'category(some|oiseau|v:voler)|'; Conclusion = 'category(some|oiseau|v:voler)' }
        @{ Name = 'no conclusion'; Premises = 'category(all|homme|mortel)|'; Conclusion = @() }
        @{ Name = 'a rule supposed'; Premises = 'category(usual:all|oiseau|v:voler)|'; Conclusion = 'category(usual:all|oiseau|v:voler)' }
        @{ Name = 'what one believes'; Premises = 'category(believe|name:alice|is~name:tom~chat)|'; Conclusion = 'category(believe|name:alice|is~name:tom~chat)' }
    ) {
        $lean = ConvertTo-LambekLean -Name 'x' -Premises $Premises -Conclusions $Conclusion
        $lean.Theorem | Should -BeNullOrEmpty
        $lean.Reason | Should -Not -BeNullOrEmpty
    }

    Context 'Judged by Lean' -Skip:(-not $HasLean) {

        It 'proves what follows, and not its opposite: <Name>' -ForEach @(
            @{ Name = 'a syllogism'; Premises = 'category(all|homme|mortel)|', 'category(is|name:socrate|homme)|'; Conclusion = 'category(is|name:socrate|mortel)' }
            @{ Name = 'what no one of a kind is'; Premises = 'category(no|poisson|mammifere)|', 'category(is|name:nemo|poisson)|'; Conclusion = 'category(isnot|name:nemo|mammifere)' }
            @{ Name = 'a kind in a wider kind'; Premises = 'category(all|chat|mammifere)|', 'category(all|mammifere|animal)|'; Conclusion = 'category(all|chat|animal)' }
            @{ Name = 'what is supposed'; Premises = 'category(usual:all|oiseau|v:voler)|', 'category(is|name:tweety|oiseau)|'; Conclusion = 'category(usual:is|name:tweety|v:voler)' }
            @{ Name = 'the narrower kind first'; Premises = 'category(usual:all|oiseau|v:voler)|', 'category(usual:no|pingouin|v:voler)|', 'category(all|pingouin|oiseau)|', 'category(is|name:pingu|pingouin)|'; Conclusion = 'category(usual:isnot|name:pingu|v:voler)' }
            @{ Name = 'a rule told with if'; Premises = 'if(cond(pleuvoir(agent("il"))), then(prendre(agent(speaker), object("le bus"))))|', 'pleuvoir(agent("il"))|'; Conclusion = 'prendre(agent(speaker), object("le bus"))|' }
            @{ Name = 'what one is not, from what its kind is'; Premises = 'category(all|chat|noir)|', 'category(isnot|speaker|noir)|'; Conclusion = 'category(isnot|speaker|chat)' }
            @{ Name = 'more than a third, through a second'; Premises = 'compare(more|grand|name:rex|name:max)|', 'compare(more|grand|name:max|name:tom)|'; Conclusion = 'compare(more|grand|name:rex|name:tom)' }
            @{ Name = 'not more than the one more than it'; Premises = 'compare(more|grand|name:rex|name:max)|', 'compare(more|grand|name:max|name:tom)|'; Conclusion = 'compare(notmore|grand|name:tom|name:rex)' }
            @{ Name = 'so, more so than one that is'; Premises = 'compare(more|grand|name:rex|name:max)|', 'category(is|name:max|grand)|'; Conclusion = 'category(is|name:rex|grand)' }
            @{ Name = 'not so, less so than one that is not'; Premises = 'compare(more|grand|name:rex|name:max)|', 'category(isnot|name:rex|grand)|'; Conclusion = 'category(isnot|name:max|grand)' }
            @{ Name = 'one of two, not the other'; Premises = 'category(is|name:rex|or:chat;chien)|', 'category(isnot|name:rex|chat)|'; Conclusion = 'category(is|name:rex|chien)' }
            @{ Name = 'what holds in each of two'; Premises = 'category(is|name:rex|or:chat;chien)|', 'category(all|chat|animal)|', 'category(all|chien|animal)|'; Conclusion = 'category(is|name:rex|animal)' }
            @{ Name = 'a rule of one of two, and not the one'; Premises = 'category(all|chat|or:blanc;noir)|', 'category(is|name:tom|chat)|', 'category(isnot|name:tom|noir)|'; Conclusion = 'category(is|name:tom|blanc)' }
            @{ Name = 'a rule told with if about one named'; Premises = 'category(if|is~name:rex~chien|does~name:rex~v:aboyer)|', 'category(is|name:rex|chien)|'; Conclusion = 'category(does|name:rex|v:aboyer)' }
            @{ Name = 'a rule told with if, the other way'; Premises = 'category(if|is~name:rex~chien|does~name:rex~v:aboyer)|', 'category(doesnot|name:rex|v:aboyer)|'; Conclusion = 'category(isnot|name:rex|chien)' }
            @{ Name = 'a rule told with if, from one to another'; Premises = 'category(if|is~name:rex~chien|is~name:max~chat)|', 'category(is|name:rex|chien)|'; Conclusion = 'category(is|name:max|chat)' }
            @{ Name = 'one of two told with or, not the first'; Premises = 'category(or|is~name:rex~chien|is~name:max~chat)|', 'category(isnot|name:rex|chien)|'; Conclusion = 'category(is|name:max|chat)' }
            @{ Name = 'one of two told with or, not the second'; Premises = 'category(or|does~name:rex~v:aboyer|does~name:max~v:dormir)|', 'category(doesnot|name:max|v:dormir)|'; Conclusion = 'category(does|name:rex|v:aboyer)' }
            @{ Name = 'one of two told with or, said not'; Premises = 'category(or|isnot~name:rex~chien|is~name:max~chat)|', 'category(is|name:rex|chien)|'; Conclusion = 'category(is|name:max|chat)' }
            @{ Name = 'one of two told with or, through a rule'; Premises = 'category(all|chien|v:aboyer)|', 'category(or|is~name:rex~chien|is~name:max~chat)|', 'category(isnot|name:max|chat)|'; Conclusion = 'category(does|name:rex|v:aboyer)' }
        ) {
            $lean = ConvertTo-LambekLean -Name 'case' -Premises $Premises -Conclusions $Conclusion
            & $Prove $lean.Theorem | Should -BeTrue -Because $lean.Theorem
            & $Prove $lean.Opposite | Should -BeFalse -Because $lean.Opposite
        }

        It 'does not prove what does not follow: <Name>' -ForEach @(
            @{ Name = 'a premise missing'; Premises = 'category(all|homme|mortel)|'; Conclusion = 'category(is|name:socrate|mortel)' }
            @{ Name = 'the opposite answer'; Premises = 'category(no|poisson|mammifere)|', 'category(is|name:nemo|poisson)|'; Conclusion = 'category(is|name:nemo|mammifere)' }
            @{ Name = 'a rule whose condition was not told'; Premises = 'if(cond(pleuvoir(agent("il"))), then(prendre(agent(speaker), object("le bus"))))|'; Conclusion = 'prendre(agent(speaker), object("le bus"))|' }
            @{ Name = 'what the narrower kind rules out'; Premises = 'category(usual:all|oiseau|v:voler)|', 'category(usual:no|pingouin|v:voler)|', 'category(all|pingouin|oiseau)|', 'category(is|name:pingu|pingouin)|'; Conclusion = 'category(usual:is|name:pingu|v:voler)' }
            @{ Name = 'more, the other way round'; Premises = 'compare(more|grand|name:rex|name:max)|'; Conclusion = 'compare(more|grand|name:max|name:rex)' }
            @{ Name = 'more in another way'; Premises = 'compare(more|grand|name:rex|name:max)|'; Conclusion = 'compare(more|fort|name:rex|name:max)' }
            @{ Name = 'so, less so than one that is'; Premises = 'compare(more|grand|name:max|name:rex)|', 'category(is|name:max|grand)|'; Conclusion = 'category(is|name:rex|grand)' }
            @{ Name = 'so, more so in another way'; Premises = 'compare(more|fort|name:rex|name:max)|', 'category(is|name:max|grand)|'; Conclusion = 'category(is|name:rex|grand)' }
            @{ Name = 'one of two, said as the first'; Premises = 'category(is|name:rex|or:chat;chien)|'; Conclusion = 'category(is|name:rex|chien)' }
            @{ Name = 'what holds in one of two only'; Premises = 'category(is|name:rex|or:chat;chien)|', 'category(all|chien|animal)|'; Conclusion = 'category(is|name:rex|animal)' }
            @{ Name = 'a rule told with if, from what follows'; Premises = 'category(if|is~name:rex~chien|does~name:rex~v:aboyer)|', 'category(does|name:rex|v:aboyer)|'; Conclusion = 'category(is|name:rex|chien)' }
            @{ Name = 'one of two told with or, neither ruled out'; Premises = 'category(or|is~name:rex~chien|is~name:max~chat)|'; Conclusion = 'category(is|name:max|chat)' }
            @{ Name = 'one of two told with or, the one ruled out'; Premises = 'category(or|is~name:rex~chien|is~name:max~chat)|', 'category(isnot|name:rex|chien)|'; Conclusion = 'category(is|name:rex|chien)' }
            @{ Name = 'one of two told with or, of the other one'; Premises = 'category(or|is~name:rex~chien|is~name:max~chien)|', 'category(all|chien|v:aboyer)|'; Conclusion = 'category(does|name:rex|v:aboyer)' }
        ) {
            $lean = ConvertTo-LambekLean -Name 'case' -Premises $Premises -Conclusions $Conclusion
            $proved = & $Prove $lean.Theorem
            $opposite = & $Prove $lean.Opposite
            # Refused: not proved, or proved only from premises that prove its opposite too
            ($proved -and -not $opposite) | Should -BeFalse -Because $lean.Theorem
        }
    }
}
