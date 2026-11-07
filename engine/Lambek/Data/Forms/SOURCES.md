# How Lambek reads the forms of words

The `<language>.forms.gz` files are what Lambek learned of the forms of words, made by `tools/Build-LambekForms.ps1`:
the rules of form that lead from a word to its lemma, two perceptrons in integers (one says the part of speech and the
features of a word, the other which rule of form to apply), the words seen, how written text is cut into words, and the
paradigms: the forms each lemma was seen with, by part of speech and features. With the paradigms Lambek says words as
well as it reads them (`Inflect`: "prendre", second person plural, is "prenez"), says by analogy the forms it never saw
("réussir": "réussissez", from the verbs seen that change as it does), and finds what a word never seen may be by saying
it again (`Analyze`: "aboient" is "aboyer", since "aboyer" said in the third person plural gives back "aboient").
No dictionary written by hand is read to make them or to use them.

Learned from the train and dev files of treebanks of Universal Dependencies, release 2.18: for French, written French
(GSD) and spoken French (ParisStories, Rhapsodie), where people say tu and ask questions; for the other languages, all
their treebanks of a free licence (no NC licence) that annotate their words in full:

| Treebank | Licence | Sentences | Words |
| --- | --- | --- | --- |
| [UD French-GSD](https://github.com/UniversalDependencies/UD_French-GSD) | CC BY-SA 4.0 | 15 926 | 390 368 |
| [UD French-ParisStories](https://github.com/UniversalDependencies/UD_French-ParisStories) | CC BY-SA 4.0 | 2 079 | 32 514 |
| [UD French-Rhapsodie](https://github.com/UniversalDependencies/UD_French-Rhapsodie) | CC BY-SA 4.0 | 2 369 | 32 045 |
| [UD English-EWT](https://github.com/UniversalDependencies/UD_English-EWT) | CC BY-SA 4.0 | 14 545 | 229 726 |
| [UD German-GSD](https://github.com/UniversalDependencies/UD_German-GSD) | CC BY-SA 4.0 | 14 612 | 276 257 |
| [UD Spanish-AnCora](https://github.com/UniversalDependencies/UD_Spanish-AnCora) | CC BY 4.0 | 15 941 | 506 515 |
| [UD Spanish-GSD](https://github.com/UniversalDependencies/UD_Spanish-GSD) | CC BY-SA 4.0 | 15 586 | 419 478 |
| [UD Dutch-Alpino](https://github.com/UniversalDependencies/UD_Dutch-Alpino) | CC BY-SA 4.0 | 13 007 | 197 568 |
| [UD Dutch-LassySmall](https://github.com/UniversalDependencies/UD_Dutch-LassySmall) | CC BY-SA 4.0 | 15 359 | 268 070 |
| [UD Portuguese-Bosque](https://github.com/UniversalDependencies/UD_Portuguese-Bosque) | CC BY-SA 4.0 | 8 190 | 200 223 |
| [UD Portuguese-PetroGold](https://github.com/UniversalDependencies/UD_Portuguese-PetroGold) | CC BY-SA 4.0 | 7 907 | 220 982 |
| [UD Portuguese-Porttinari](https://github.com/UniversalDependencies/UD_Portuguese-Porttinari) | CC BY 4.0 | 6 735 | 134 500 |
| [UD Portuguese-DANTEStocks](https://github.com/UniversalDependencies/UD_Portuguese-DANTEStocks) | CC BY 4.0 | 3 541 | 70 937 |
| [UD Italian-MarkIT](https://github.com/UniversalDependencies/UD_Italian-MarkIT) | CC BY 4.0 | 952 | 30 292 |
| [UD Italian-TWITTIRO](https://github.com/UniversalDependencies/UD_Italian-TWITTIRO) | CC BY-SA 4.0 | 1 282 | 26 626 |
| [UD Italian-ParlaMint](https://github.com/UniversalDependencies/UD_Italian-ParlaMint) | CC BY-SA 4.0 | 326 | 10 026 |

As models learned from these treebanks, they are shared under CC BY-SA 4.0, with credit to the authors of the
treebanks as given in their READMEs. Measured on the test files of the same treebanks, never learned from (`bench/forms`,
`Invoke-LambekFormBenchmark`), and on the test file of PUD, a treebank of the same sentences in every language
(CC BY-SA 3.0), read to measure only. A treebank is added only when no test file falls with it:

| Model | Part of speech | All tags | Lemma | Lemma of the words never seen |
| --- | --- | --- | --- | --- |
| German, GSD test / PUD | 94.02 % / 90.68 % | 81.33 % / 62.67 % | 96.69 % / 96.48 % | 82.93 % / 85.55 % |
| Spanish, AnCora test / GSD test / PUD | 97.44 % / 93.70 % / 92.96 % | 95.21 % / 90.49 % / 79.60 % | 98.83 % / 96.29 % / 95.92 % | 89.83 % / 82.95 % / 87.85 % |
| Dutch, Alpino test / LassySmall test | 95.40 % / 95.57 % | 92.78 % / 92.90 % | 93.87 % / 94.32 % | 55.64 % / 65.18 % |
| Portuguese, Bosque test / PetroGold test / PUD | 94.59 % / 97.73 % / 92.52 % | 90.15 % / 95.76 % / 60.00 % | 97.33 % / 98.96 % / 78.12 % | 88.43 % / 89.77 % / 70.33 % |
| Italian, MarkIT test / ParlaMint test / PUD | 93.65 % / 95.16 % / 91.02 % | 87.08 % / 89.64 % / 56.51 % | 86.42 % / 96.84 % / 94.38 % | 84.04 % / 83.88 % / 84.36 % |

Set aside, measured: French-ALTS (the ALTS test rises, Rhapsodie falls: all tags 92.45 % → 92.09 %); English-ATIS (the
ATIS test rises, 56.47 % → 83.74 % of all tags, but EWT, CTeTex, Pronouns and LittlePrince fall); German-HDT (one pass
over it took 94 minutes on two cores, ten passes are needed, and it annotates features otherwise than GSD). Set aside
unread: the treebanks that leave out the words, the lemmas or the features of most of their words (English-GUMReddit,
whose words are to be put back from Reddit, English-ESLSpok, English-CHILDES; Portuguese-GSD leaves out the features
of 77 % of its words and the lemmas of 18 %); `tools/Build-LambekForms.ps1` refuses a file that leaves out those of
more than nine words in ten. The great treebanks of Italian (ISDT, VIT, PoSTWITA) are under an NC licence: never
learned from, so the Italian model is small. A word's ends never cut a character in two: the emoji of
Portuguese-DANTEStocks would otherwise have given two halves written alike.

Tried and set aside (step 4.5): reading the tags of a whole sentence at once, by a beam over the tags (3 and 6
readings kept), instead of word after word. The perceptron learned word after word, and the beam read a little worse
(French GSD, all tags: 95.07 % word after word, 95.06 % and 95.01 % with the beam; English EWT: 93.16 %, 92.99 %).

## Italian sentences confirmed by English

The Italian treebanks free to learn from are small (66 944 words). The tagger of Italian is also taught 9 604 of the
Italian sentences of Tatoeba translated from English (the English-Italian pairs listed under "Words of logic and
copulas", CC BY 2.0 FR): 66 942 words, as many as the treebanks have. They are chosen by
`tools/Build-LambekForms.ps1 -English -Translated` (`Native/Projection.cs`), never by hand:

- the model of the treebanks alone, with the Italian lexicon, reads the Italian side, and the English model the English
  side; their words are aligned by IBM Model 1 both ways (`Native/Aligner.cs`; Brown et al. 1993), a link kept where
  each word is the other's best;
- the part of speech of an English word is believed of the word it is aligned with as often as the words the treebanks
  saw with one part of speech carry it over right, learned on the same pairs: PUNCT 100 %, DET 98 %, ADP 95 %, NOUN
  90 %, VERB 86 %, PRON 78 %, ADJ 75 %, AUX 69 %, PROPN 43 %, INTJ 17 %, SCONJ 11 %, PART 0 %;
- a sentence is kept when every word carried over by a part of speech believed 60 % of the time agrees with the model,
  or, believed 90 % of the time, is set right by a tag the treebanks or the lexicon give the word; when every word the
  treebanks never met is carried over, or read as the lexicon reads it; and when it has one such word (Yarowsky & Ngai
  2001, Das & Petrov 2011, Tackstrom et al. 2013): 96 756 of 483 415 pairs, the first of them taught, in the order of
  the file;
- they teach the tags of words in context only, after the treebanks in each pass: the words known, their lemmas and
  their rules of form are the treebanks'.

How many to teach was measured on the dev files of ISDT and VIT (CC BY-NC-SA, read to measure only, never learned from):
all tags 87.64 % → 88.22 % and 84.18 % → 84.88 %. 30 000 sentences and all of them read worse than 10 000 (the short
sentences of Tatoeba then weigh more than the treebanks), and sentences chosen for their new words read no better. On
the test files:

| Test file | Part of speech | All tags | Lemma |
| --- | --- | --- | --- |
| MarkIT | 94.07 % → 94.09 % | 87.16 % → 86.47 % | 86.79 % → 86.83 % |
| ParlaMint | 95.52 % → 95.62 % | 89.71 % → 90.60 % | 97.21 % → 97.21 % |
| TWITTIRO | 92.14 % → 92.47 % | 88.00 % → 88.31 % | 92.51 % → 92.27 % |
| PUD | 91.77 % → 91.80 % | 56.69 % → 56.45 % | 95.04 % → 94.97 % |
| VALICO | 91.94 % → 92.39 % | 86.47 % → 87.01 % | 85.92 % → 86.04 % |

The features of MarkIT fall (90.03 % → 89.27 %): its words are mostly those of the treebanks, and the sentences of
Tatoeba draw the tagger to their own.

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

## Words of logic and copulas (step 3)

The `<language>.logic` files are the words of logic of each language, the words that say of how many things a sentence
is (`all`: "tous", "chaque"; `some`: "certains"; `no`: "aucun"), and its copulas, the verbs that only join ("être",
"be"), made by `tools/Learn-LambekLogicWords.ps1`. Nothing is written by hand: the reader of general rules
(`Read-LambekCategoryTagged`) reads a sentence by the tags of its words and these words only, the same in every language.

- The copulas are the lemmas the treebanks of the language tag with the relation `cop`, those of at least a tenth of
  them all (the train files of the treebanks of its forms model; UD French-GSD for French).
- The article of a negation, from the same treebanks: among the indefinite articles of objects, the one at least four
  times more often after a word tagged `Polarity=Neg` than in sentences with none ("n'a pas de poils"), and the first
  letters before which it is cut ("pas d'ailes"). French learns "de" (72 of 252 objects after a negation); the other
  languages learn none, their negation keeps its article ("does not have a tail").
- For English, the words of logic are those UD English-EWT tags `PronType=Tot`, `PronType=Ind` or `PronType=Neg`.
- For another language, they are learned from sentences translated from and to English: both sides are read by the
  forms models, and a word the treebanks of the language saw as a determiner or a pronoun takes a kind when it is met
  in at least 20 pairs with that kind on the English side, and with it in most of the pairs it is met in (sentences of
  at most 12 words). Under a negation, the English side says none for "some" and for "a": "I don't have anything" is
  "non ho niente", "a bee is not a bird" is "eine Biene ist kein Vogel" (not at least one is none). Counts only, in
  integers.

| Pairs | Licence | Pairs read |
| --- | --- | --- |
| [Tatoeba](https://tatoeba.org), release v2023-04-12 of [OPUS](https://opus.nlpl.eu/Tatoeba.php), English-French | [CC BY 2.0 FR](https://creativecommons.org/licenses/by/2.0/fr/) | 275 413 |
| Tatoeba, the same release, English-German | CC BY 2.0 FR | 322 413 |
| Tatoeba, the same release, English-Spanish | CC BY 2.0 FR | 222 073 |
| Tatoeba, the same release, English-Dutch | CC BY 2.0 FR | 79 548 |
| Tatoeba, the same release, English-Portuguese | CC BY 2.0 FR | 227 657 |
| Tatoeba, the same release, English-Italian | CC BY 2.0 FR | 502 269 |

The sentences of Tatoeba are by its contributors (see https://tatoeba.org/eng/terms_of_use); the pairs are not kept
here, only the words learned from them, with the counts they were learned with and the SHA-256 of the files read, in
the first line of each file. As in the treebanks, the English side anchors what a word means: "another" and "such" are
tagged PronType=Ind in English-EWT, so "autre" and "telle" are learned as words of `some`.

## The dialogues learned (`<language>.dialogue.json`)

German, Spanish, Dutch, Portuguese and Italian have no dialogue written for them: Lambek learned the one it reasons
with (`tools/Learn-LambekDialogue.ps1`, Native/DialogueWords.cs), nothing in it written by hand.

- The small words, from the tags of the forms model of the language (the articles are the words most often tagged DET
  with PronType=Art, the speaker the pronouns tagged Person=1 and Number=Sing...), kept only when said at least 100
  times in the sentences of the language in Tatoeba, so that a word of another language quoted in its treebanks ("the"
  in German) is not one of them. Where a language does not tag the number of its pronouns (Dutch), the speaker is the
  pronoun of the first person met more with "I" or "me" than with "we" or "us" in the translated sentences.
- The word that says whose ("von", "de", "van", "di"): the preposition met the most often where English says "of".
- What it answers: the sentences Tatoeba gives for "Yes.", "No.", "I don't know." and "I understand." ("Ja.", "Nein.",
  "Ich weiß nicht.", "Ich verstehe."); among several, the one whose rarest word the language says the most, then the
  one it says most often. Short answers, with what they rest on after them: a sentence not in the translated
  sentences is not said.
- How it says that one is of a kind: the form of the copula found after a name where English says "<name> is a ...".

From the same pairs of Tatoeba (release v2023-04-12 of OPUS, CC BY 2.0 FR) and the same treebanks as the forms models
and the words of logic above. What the dialogue of French or English says that these cannot say yet (the times, the
counts, "pourquoi", what is imagined) is not said in these languages.

## The lexicons (`<language>.lexicon.gz`)

The words of each language as Wiktionary says them, to read the words its treebanks never met ("abbaia" is
"abbaiare", "frisst" is "fressen", "pesce" a noun): `tools/Learn-LambekLexicon.ps1`, Native/Lexicon.cs. Nothing in
them is written by hand.

| Source | Licence | Words read |
| --- | --- | --- |
| [Wiktionary](https://en.wiktionary.org), English edition, dump of 1 October 2026, as [Wiktextract](https://github.com/tatuylonen/wiktextract) reads it ([kaikki.org](https://kaikki.org/dictionary/rawdata.html), Tatu Ylonen, "Wiktextract: Wiktionary as Machine-Readable Structured Data", LREC 2022) | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) and GFDL | French 929 177, English 1 784 859, German 2 074 714, Spanish 2 564 888, Dutch 539 773, Portuguese 1 050 719, Italian 1 610 372 |

- How the names of Wiktionary turn into the tags of the treebanks is learned once for every language, from the words
  Wiktionary and the treebanks of the forms models both have: a part of speech of Wiktionary is the UPOS most of its
  words are tagged with ("noun" NOUN, "verb" VERB, "name" PROPN...); a tag is the one feature that tells its words apart
  the most, met with nine in ten of them and at most half as often without it, learned from the forms Wiktionary gives
  one reading of ("plural" Number=Plur, "first-person" Person=1, "future" Tense=Fut...); a tag that is no feature is kept
  when most of its words are the forms of the lemma it gives them ("form-of"), and a word with any other tag is left
  out ("diminutive": another word).
- A word is kept when its language is seen written so in its sentences of Tatoeba (above): French 33 243 forms, English
  26 585, German 38 061, Spanish 30 668, Dutch 15 251, Portuguese 32 003, Italian 31 307.
- When the forms model reads a word as one of the parts of speech the lexicon gives it, the word takes the lemma the
  lexicon gives it if the treebanks never met it: a word they met keeps its lemma unless that lemma is a guess they
  never met; a word they never met keeps a lemma its rule of form found among theirs, and takes the lexicon's in place of
  one guessed from another verb. A word they never met, read as none of the lexicon's parts of speech, takes the
  lexicon's reading nearest to the tagger's.
- Measured on the test files of the treebanks and PUD: the lemma rises on every file of the seven languages (Italian
  +0.4 to +0.8 points, the words never seen +2.8 to +4.5; German +0.2 to +0.6, the words never seen +1.2 to +3.3).

As derived from Wiktionary, the lexicons are shared under CC BY-SA 4.0, with credit to the authors of Wiktionary.
