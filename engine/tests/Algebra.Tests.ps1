BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null

    function Get-TestAnswer {
        param([string] $Text)
        (InModuleScope Lambek -Parameters @{ Text = $Text } { param($Text) Resolve-LambekCalculation -Text $Text }).Answer
    }
    function Show-Expression {
        param([object] $Expression)
        [LambekAlgebra]::Show($Expression)
    }
}

Describe 'Symbolic algebra' {

    It 'simplifies by folding numbers and collecting like terms: <Text>' -ForEach @(
        @{ Text = '2(x+1) - 2x'; Shown = '2' }
        @{ Text = 'x*x*x + 3x^2 - x^2'; Shown = 'x^3 + 2x^2' }
        @{ Text = 'sqrt(8)'; Shown = '2√2' }
        @{ Text = '8^(1/3)'; Shown = '2' }
        @{ Text = 'exp(ln(x))'; Shown = 'x' }
    ) {
        Show-Expression ([LambekAlgebra]::Simplify([LambekAlgebra]::Parse($Text))) | Should -Be $Shown
    }

    It 'derives by the chain rule: <Text>' -ForEach @(
        @{ Text = 'x^3 + 2x'; Shown = '3x^2 + 2' }
        @{ Text = 'sin(x^2)'; Shown = '2x × cos(x^2)' }
        @{ Text = 'ln(x)'; Shown = '1/x' }
    ) {
        Show-Expression ([LambekAlgebra]::Derive([LambekAlgebra]::Parse($Text), 'x')) | Should -Be $Shown
    }

    It 'finds a primitive whose derivative gives the function back: <Text>' -ForEach @(
        @{ Text = '3x^2 + 2x + 1' }
        @{ Text = 'cos(2x)' }
        @{ Text = '(x+1)^2' }
        @{ Text = 'exp(3x)' }
    ) {
        $f = [LambekAlgebra]::Parse($Text)
        $primitive = [LambekAlgebra]::Integrate($f, 'x')
        $primitive | Should -Not -BeNullOrEmpty
        $back = [LambekAlgebra]::Derive($primitive, 'x')
        $difference = [LambekAlgebra]::Simplify([LambekAlgebra]::Expand([LambekAlgebra]::Add($back, [LambekAlgebra]::Neg($f))))
        Show-Expression $difference | Should -Be '0'
    }

    It 'integrates exactly between bounds, or says it is an approximation' {
        $exact = $false
        [LambekAlgebra]::Definite([LambekAlgebra]::Parse('x^2'), 'x', [LambekAlgebra]::Parse('0'), [LambekAlgebra]::Parse('1'), [ref] $exact) | Should -Be '1/3'
        $exact | Should -BeTrue
        [LambekAlgebra]::Definite([LambekAlgebra]::Parse('exp(-x^2)'), 'x', [LambekAlgebra]::Parse('0'), [LambekAlgebra]::Parse('1'), [ref] $exact) | Should -Be '≈ 0.7468241328'
        $exact | Should -BeFalse
    }

    It 'reduces a rational function by the polynomial GCD' {
        Show-Expression ([LambekAlgebra]::ReduceFraction([LambekAlgebra]::Parse('(x^2 - 1)/(x - 1)'), 'x')) | Should -Be 'x + 1'
    }

    It 'expands a power of a sum' {
        Show-Expression ([LambekAlgebra]::Expand([LambekAlgebra]::Parse('(x+1)^3'))) | Should -Be 'x^3 + 3x^2 + 3x + 1'
    }
}

Describe 'Polynomials and certified roots' {

    It 'isolates every real root with Sturm''s theorem' {
        $p = [LambekAlgebra]::ToPolynomial([LambekAlgebra]::Parse('x^5 - 4x + 2'), 'x')
        $roots = [LambekPolynomials]::RealRoots($p, [LambekRational]::new(1, [System.Numerics.BigInteger]::Pow(10, 12)))
        $roots.Count | Should -Be 3
        # Each interval holds a sign change of p: a root is certainly inside
        foreach ($interval in $roots) { ($p.Evaluate($interval[0]).Sign * $p.Evaluate($interval[1]).Sign) | Should -BeLessOrEqual 0 }
    }

    It 'factors over the rationals' {
        $p = [LambekAlgebra]::ToPolynomial([LambekAlgebra]::Parse('x^3 - 6x^2 + 11x - 6'), 'x')
        [LambekMath]::FactorPolynomial($p, 'x') | Should -Be '(x - 1)(x - 2)(x - 3)'
    }

    It 'solves a cubic with no rational root, certified' {
        Get-TestAnswer 'résous x^3 - x - 1 = 0' | Should -BeLike '*1,3247179572*Sturm*'
    }
}

Describe 'Linear algebra' {

    It 'solves a linear system: <Kind>' -ForEach @(
        @{ Equations = @('2x + y = 5', 'x - y = 1'); Kind = 'unique' }
        @{ Equations = @('x + y + z = 6', 'x - y = 0'); Kind = 'many' }
        @{ Equations = @('x + y = 1', 'x + y = 2'); Kind = 'none' }
    ) {
        ([LambekLinear]::Solve([string[]] $Equations)).Kind | Should -Be $Kind
    }

    It 'computes the determinant by Bareiss, the inverse, and checks A times its inverse' {
        $m = [LambekMatrix]::Parse('[[1,2,3],[4,5,6],[7,8,10]]')
        $m.Determinant().Exact() | Should -Be '-3'
        ($m * $m.Inverse()).Show() | Should -Be '[[1, 0, 0], [0, 1, 0], [0, 0, 1]]'
    }

    It 'finds the characteristic polynomial by Faddeev-LeVerrier' {
        [LambekPolynomials]::Show(([LambekMatrix]::Parse('[[2, 1], [1, 3]]')).Characteristic(), 'x') | Should -Be 'x^2 - 5x + 5'
    }
}

Describe 'Numbers' {

    It 'factors with Pollard''s rho and tests primes with Miller-Rabin' {
        [LambekNumbers]::Factor([System.Numerics.BigInteger]::Parse('1000000016000000063')) -join ' ' | Should -Be '1000000007 1000000009'
        [LambekNumbers]::IsPrime([System.Numerics.BigInteger]::Parse('170141183460469231731687303715884105727')) | Should -BeTrue
        [LambekNumbers]::IsPrime(91) | Should -BeFalse
    }

    It 'counts and describes exactly' {
        [LambekNumbers]::Choose(10, 3) | Should -Be 120
        [LambekNumbers]::ModInverse(3, 11) | Should -Be 4
        $stats = [LambekNumbers]::Statistics([LambekRational[]] @(2, 4, 4, 4, 5, 5, 7, 9 | ForEach-Object { [LambekRational]::new($_, 1) }))
        $stats['mean'] | Should -Be '5'
        $stats['stddev'] | Should -Be '2'
        $stats['samplevariance'] | Should -Be '32/7'
    }

    It 'writes and reads numbers in words: <Language>' -ForEach @(
        @{ Language = 'fr'; Number = 71; Words = 'soixante et onze' }
        @{ Language = 'fr'; Number = 80; Words = 'quatre-vingts' }
        @{ Language = 'en'; Number = 2024; Words = 'two thousand twenty-four' }
        @{ Language = 'es'; Number = 21; Words = 'veintiuno' }
        @{ Language = 'de'; Number = 324; Words = 'dreihundertvierundzwanzig' }
        @{ Language = 'it'; Number = 28; Words = 'ventotto' }
        @{ Language = 'nl'; Number = 22; Words = 'tweeëntwintig' }
        @{ Language = 'pt'; Number = 1990; Words = 'mil novecentos e noventa' }
    ) {
        [LambekNumberWords]::Write($Number, $Language) | Should -Be $Words
        [LambekNumberWords]::Digitize($Words, $Language) | Should -Be "$Number"
    }

    It 'reads a written number from 0 to 9999 back to itself in every language' {
        foreach ($language in [LambekNumberWords]::Languages) {
            # One is also an article ("un fichier", "een bestand"): read alone it stays a word, except in English
            foreach ($n in 0, 7, 16, 21, 70, 71, 80, 81, 91, 99, 100, 101, 110, 200, 999, 1000, 1001, 1100, 2000, 2024, 9999) {
                [LambekNumberWords]::Digitize([LambekNumberWords]::Write($n, $language), $language) | Should -Be "$n" -Because "$language $n"
            }
        }
    }

    It 'keeps an article as a word' {
        [LambekNumberWords]::Digitize('supprime un fichier', 'fr') | Should -Be 'supprime un fichier'
    }
}

Describe 'Math asked in words' {

    It 'answers: <Text>' -ForEach @(
        @{ Text = 'dérivée de x^3 + 2x'; Like = 'd/dx (x^3 + 2x) = 3x^2 + 2' }
        @{ Text = 'intégrale de x^2 entre 0 et 1'; Like = '*= 1/3' }
        @{ Text = 'pgcd de 12 et 18'; Like = 'PGCD(12, 18) = 6' }
        @{ Text = 'écris 255 en binaire'; Like = '*11111111' }
        @{ Text = 'combinaisons de 3 parmi 10'; Like = 'C(10, 3) = 120' }
        @{ Text = 'résous le système 2x + y = 5 et x - y = 1'; Like = '*x = 2, y = 1*' }
        @{ Text = 'déterminant de [[1,2],[3,4]]'; Like = 'det = -2' }
        @{ Text = 'combien font trois cent vingt et un plus quatre-vingt-dix-neuf ?'; Like = '*= 420' }
        @{ Text = 'is 2147483647 prime?'; Like = '2147483647 is a prime number.' }
        @{ Text = 'ableitung von x^2 + 3x'; Like = '*= 2x + 3' }
        @{ Text = 'mcd de 12 y 18'; Like = 'mcd(12, 18) = 6' }
        @{ Text = 'derivata di x^3'; Like = '*= 3x^2' }
        @{ Text = 'afgeleide van x^2'; Like = '*= 2x' }
        @{ Text = 'escreve 1990 por extenso'; Like = '*mil novecentos e noventa*' }
    ) {
        Get-TestAnswer $Text | Should -BeLike $Like
    }

    It 'never takes a request on files for math: <Text>' -ForEach @(
        @{ Text = 'supprime les fichiers en double dans C:\Temp' }
        @{ Text = 'liste les fichiers premiers dans C:\Data' }
        @{ Text = 'moyenne des fichiers dans C:\Data' }
    ) {
        Get-TestAnswer $Text | Should -BeNullOrEmpty
    }
}
