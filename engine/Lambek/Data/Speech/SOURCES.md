# How Lambek's languages sound

`fr.fluency.gz` and `en.fluency.gz` are Kneser-Ney models (order 3) of the shapes of sentences, made by
`tools/Build-LambekFluency.ps1`. They keep the 1000 most frequent words of each language as themselves and every other
word as its kind (a name, a noun, an adjective, a verb, a number): they say how a sentence is built, never what it says.

Learned from, deduplicated, one sentence in fifty kept aside to measure them:

| Corpus | Licence | Lines (fr / en) |
| --- | --- | --- |
| Mozilla Common Voice, sentences of `server/data/fr` and `server/data/en` (addresses and single words left out) | CC0 1.0 | 1 735 808 / 1 586 660 |
| Europarl, the sample distributed with NLTK (`europarl_raw`), French and English | no copyright restriction known (European Parliament proceedings) | 21 203 / 19 980 |

Perplexity on the sentences kept aside: 19.9 in French, 23.5 in English.

`fr.speech.json` and `en.speech.json` are the fusions of the scores (the satellites) that choose among the ways of
saying an answer, fitted by `Optimize-LambekSpeech` on `bench/speech.json`.
