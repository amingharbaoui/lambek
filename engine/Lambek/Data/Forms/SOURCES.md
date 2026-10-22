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

## Words learned from plain text (step 4.6)

`fr.learned.gz` and `en.learned.gz` are the notebooks of the words Lambek learned on its own, made by
`tools/Learn-LambekWords.ps1` from the plain texts of `tools/corpus.json` (downloaded by `tools/Get-LambekCorpus.ps1`
into a folder outside the repository: the texts themselves are never kept here). Every sentence is read with the forms
model above; a word the treebanks never had is written down only when it was met in at least three sentences, read as
the same part of speech and lemma in most of them (60 %), seldom with a capital (no name), and its lemma is sure: a lemma
of the treebanks, a lemma two of its forms lead to, or one found again by saying the word (`Analyze`). A lemma that is no
word of the texts ("éteigner") is made up and refused. A noun takes the gender the treebanks give its lemma, else the one
the determiners before its forms give ("une étagère"), when two in three of them agree. Nothing is learned from what
Lambek itself says.

A notebook is written only when it earns its place: the forms models are measured with it and without it on treebanks
they never learned from (the test files of `bench/forms`, UD French-FQB and French-Sequoia), and on the conjugations of
UniMorph for the verbs met in the texts; when a figure falls, the notebook is refused. Each notebook is plain text
(gzip), one word a line, with how often it was met, in how many sentences it was read so, why it was kept, and where it
was met. Its first line names the files it was learned from, with their SHA-256.

| Source | Language | Licence | Credit |
| --- | --- | --- | --- |
| [Tatoeba](https://tatoeba.org) sentences | fr, en | CC BY 2.0 FR | The contributors of Tatoeba |
| [Leipzig Corpora Collection](https://wortschatz.uni-leipzig.de), news 2023, 1M sentences | fr, en | CC BY | Universität Leipzig |
| [Mozilla Common Voice](https://commonvoice.mozilla.org), sentence collector | fr, en | CC0 | The contributors of Common Voice |
| [Project Gutenberg](https://www.gutenberg.org): Madame Bovary, Les misérables (I-V), Le comte de Monte-Cristo (I), Notre-Dame de Paris, Voyage au centre de la Terre, Vingt mille lieues sous les mers | fr | Public domain | Project Gutenberg |
| [Project Gutenberg](https://www.gutenberg.org): Alice's Adventures in Wonderland, Pride and Prejudice, The Adventures of Sherlock Holmes, Moby Dick, The Adventures of Tom Sawyer, Adventures of Huckleberry Finn, Frankenstein, A Tale of Two Cities | en | Public domain | Project Gutenberg |

Judges, read to measure only: [UD French-FQB](https://github.com/UniversalDependencies/UD_French-FQB) and
[UD French-Sequoia](https://github.com/UniversalDependencies/UD_French-Sequoia) r2.18 (LGPL-LR), and
[UniMorph](https://unimorph.github.io) French and English (CC BY-SA 3.0).

What the notebooks hold and what they gave, measured when they were written (before → with the notebook):

| | French | English |
| --- | --- | --- |
| Sentences read, words read | 1 892 508, 32.9 million | 3 141 940, 43.1 million |
| Words written down | 43 025 | 39 835 |
| GSD / EWT test: lemma of the words never seen | 85.89 % → 87.53 % | 79.34 % → 80.61 % |
| GSD / EWT test: part of speech of the words never seen | 90.59 % → 91.62 % | 83.32 % → 83.50 % |
| GSD / EWT test: saying the words never seen | 95.20 % → 95.76 % | 94.72 % → 96.01 % |
| ParisStories test: lemma, saying the words never seen | 87.32 % → 89.20 %, 88.36 % → 90.52 % | |
| Sequoia test: lemma of the words never seen | 88.21 % → 89.74 % | |
| UniMorph, verbs met in the texts, lemma never in the treebanks | 93.37 % → 94.94 % | 85.89 % → 90.92 % |

No figure fell. The texts are read again with `tools/Learn-LambekWords.ps1` (French: 22 minutes, English: 19, on a
cloud machine of two cores); a text that changed since gives another notebook, measured the same way.
