BeforeAll {
    Import-Module "$PSScriptRoot/../Lambek/Lambek.psd1" -Force
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/files" | Out-Null
    Import-LambekPack -Path "$PSScriptRoot/../../dsl/code" | Out-Null

    function Ask {
        param([string] $Text)
        New-LambekPlan $Text | ConvertTo-LambekAnswer
    }
    function Tell {
        param([string[]] $Text)
        foreach ($line in $Text) { New-LambekPlan $line | Out-Null }
    }
}

Describe 'Why: what explains a thing told' {

    BeforeEach {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Incognito = $false; $script:Now = [datetime] '2026-10-06 10:00' }
    }
    AfterAll {
        & (Get-Module Lambek) { Clear-LambekTold; $script:Told = $null; $script:Now = $null }
    }

    It 'says what a thing told follows from, when the condition of a rule told holds' {
        Tell "s'il pleut, je prends le bus", 'je prends le bus', 'il pleut'
        Ask 'pourquoi est-ce que je prends le bus ?' | Should -Be (@(
                "Je le déduis de ce que vous m'avez dit :"
                "- S'il pleut, vous prenez le bus."
                '- Il pleut.'
            ) -join "`n")
    }

    It 'gives the explanations it could have, the one that explains the most first' {
        Tell "s'il pleut, la route est mouillée", "si l'arrosage marche, la route est mouillée", "s'il pleut, les toits sont mouillés", 'les toits sont mouillés', 'la route est mouillée'
        Ask 'pourquoi la route est mouillée ?' | Should -Be (@(
                "Vous ne m'avez pas dit pourquoi. Je vois 2 explications possibles, en commençant par celle qui explique le plus de choses :"
                "- peut-être parce qu'il pleut (vous m'avez dit : S'il pleut, la route est mouillée)"
                '  cela expliquerait aussi : les toits sont mouillés'
                "- peut-être parce que l'arrosage marche (vous m'avez dit : Si l'arrosage marche, la route est mouillée)"
            ) -join "`n")
    }

    It 'leaves out what was told false, and asks what would check what is left' {
        Tell "s'il pleut, la route est mouillée", "si l'arrosage marche, la route est mouillée", "s'il pleut, mon parapluie est mouillé", "l'arrosage ne marche pas", 'la route est mouillée'
        Ask 'pourquoi la route est-elle mouillée ?' | Should -Be (@(
                "Vous ne m'avez pas dit pourquoi. Je vois une explication possible :"
                "- peut-être parce qu'il pleut (vous m'avez dit : S'il pleut, la route est mouillée)"
                "- pas parce que l'arrosage marche : vous m'avez dit le contraire."
                'Pour le vérifier : est-ce que votre parapluie est mouillé ?'
                "Si non, ce n'est pas parce qu'il pleut."
            ) -join "`n")
    }

    It 'asks the question that tells two explanations apart' {
        Tell "s'il pleut, la route est mouillée", "si l'arrosage marche, la route est mouillée", "s'il pleut, mon parapluie est mouillé", 'la route est mouillée'
        $lines = @((Ask 'pourquoi la route est mouillée ?') -split "`n")
        $lines | Should -Contain 'Une question les départagerait : est-ce que votre parapluie est mouillé ?'
        $lines[-1] | Should -Be "Si non, ce n'est pas parce qu'il pleut."
    }

    It 'explains in English too' {
        Tell 'if it rains, the road is wet', 'if the sprinkler works, the road is wet', 'the road is wet'
        Ask 'why is the road wet?' | Should -Be (@(
                'You did not tell me why. 2 explanations could fit, starting with the one that explains the most:'
                '- maybe because it rains (you told me: If it rains, the road is wet)'
                '- maybe because the sprinkler works (you told me: If the sprinkler works, the road is wet)'
            ) -join "`n")
    }

    It 'explains with a rule about every one, then says it follows once told' {
        Tell 'tous les chats sont noirs', 'Minou est noir'
        Ask 'pourquoi Minou est noir ?' | Should -Be (@(
                "Vous ne m'avez pas dit pourquoi. Je vois une explication possible :"
                "- peut-être parce que Minou est un chat (vous m'avez dit : Tous les chats sont noirs)"
            ) -join "`n")
        Tell 'Minou est un chat'
        Ask 'pourquoi Minou est-il noir ?' | Should -Be (@(
                "Je le déduis de ce que vous m'avez dit :"
                '- Tous les chats sont noirs.'
                '- Minou est un chat.'
            ) -join "`n")
    }

    It 'never invents a cause' {
        Tell 'la route est mouillée'
        Ask 'pourquoi la route est mouillée ?' | Should -Not -BeLike '*peut-être*'
    }

    It 'says a participle after être as it was told' {
        Ask 'la route est mouillée' | Should -Be "C'est noté. La route est mouillée. Je m'en souviendrai."
    }
}
