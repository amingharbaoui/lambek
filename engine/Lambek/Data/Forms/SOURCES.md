# How Lambek reads the forms of words

`fr.forms.gz` and `en.forms.gz` are what Lambek learned of the forms of words, made by `tools/Build-LambekForms.ps1`:
the rules of form that lead from a word to its lemma, two perceptrons in integers (one says the part of speech and the
features of a word, the other which rule of form to apply), the words seen, and how written text is cut into words.
No dictionary written by hand is read to make them or to use them.

Learned from the train and dev files of treebanks of Universal Dependencies, release 2.18: for French, written French
(GSD) and spoken French (ParisStories, Rhapsodie), where people say tu and ask questions:

| Treebank | Licence | Sentences | Words |
| --- | --- | --- | --- |
| [UD French-GSD](https://github.com/UniversalDependencies/UD_French-GSD) | CC BY-SA 4.0 | 15 926 | 390 368 |
| [UD French-ParisStories](https://github.com/UniversalDependencies/UD_French-ParisStories) | CC BY-SA 4.0 | 2 079 | 32 514 |
| [UD French-Rhapsodie](https://github.com/UniversalDependencies/UD_French-Rhapsodie) | CC BY-SA 4.0 | 2 369 | 32 045 |
| [UD English-EWT](https://github.com/UniversalDependencies/UD_English-EWT) | CC BY-SA 4.0 | 14 545 | 229 726 |

As models learned from these treebanks, they are shared under the same licence (CC BY-SA 4.0), with credit to the
authors of the treebanks as given in their READMEs. Measured on the test files of the same treebanks, never learned
from (`bench/forms`, `Invoke-LambekFormBenchmark`).
