# Test files of the forms of words

The test files of two treebanks of Universal Dependencies, release 2.18, to measure the forms models of Lambek
(`engine/Lambek/Data/Forms`) with `Invoke-LambekFormBenchmark`. The models never learn from them: they learn from the
train and dev files of the same treebanks (`tools/Build-LambekForms.ps1`).

| File | Treebank | Licence | Sentences | Words | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| `fr_gsd-ud-test.conllu` | [UD French-GSD](https://github.com/UniversalDependencies/UD_French-GSD) r2.18 | CC BY-SA 4.0 | 416 | 10 017 | `eee5a599b429658b6ee8582fae9993eb07161247fc64bad57d16b2050ed4eb1a` |
| `en_ewt-ud-test.conllu` | [UD English-EWT](https://github.com/UniversalDependencies/UD_English-EWT) r2.18 | CC BY-SA 4.0 | 2 077 | 25 094 | `fa024f43dc5da3c5ac02563bc9bd0e974f46cbb1560823976a8f342a37dc494a` |

Both are distributed unchanged, under their licence (https://creativecommons.org/licenses/by-sa/4.0/), with credit to
their authors as given in the README of each treebank.
