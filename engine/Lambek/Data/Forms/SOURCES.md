# How Lambek reads the forms of words

`fr.forms.gz` and `en.forms.gz` are what Lambek learned of the forms of words, made by `tools/Build-LambekForms.ps1`:
the rules of form that lead from a word to its lemma, two perceptrons in integers (one says the part of speech and the
features of a word, the other which rule of form to apply), the words seen, how written text is cut into words, and the
paradigms: the forms each lemma was seen with, by part of speech and features. With the paradigms Lambek says words as
well as it reads them (`Inflect`: "prendre", second person plural, is "prenez"), says by analogy the forms it never saw
("réussir": "réussissez", from the verbs seen that change as it does), and finds what a word never seen may be by saying
it again (`Analyze`: "aboient" is "aboyer", since "aboyer" said in the third person plural gives back "aboient").
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

Tried and set aside (step 4.5): reading the tags of a whole sentence at once, by a beam over the tags (3 and 6
readings kept), instead of word after word. The perceptron learned word after word, and the beam read a little worse
(French GSD, all tags: 95.07 % word after word, 95.06 % and 95.01 % with the beam; English EWT: 93.16 %, 92.99 %).
