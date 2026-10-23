# What Lambek knows of the world

`wikidata.facts.gz` is what Lambek read in [Wikidata](https://www.wikidata.org), made by
`tools/Get-LambekFacts.ps1` from the questions of `tools/facts.json`, asked to the SPARQL endpoint
[QLever](https://qlever.dev/wikidata) (University of Freiburg), which answers questions on all of Wikidata. Its first
line names the endpoint and the day the data was read.

| Kind | Which things | Facts |
| --- | --- | --- |
| country | sovereign states and countries that still exist | capital, official languages, currency, population (with its year), continent, area, what it is a member of today |
| city | cities of 100 000 people or more, and every capital | country, population (with its year) |
| person | people with a page in 30 Wikipedias or more | sex or gender (for "né" or "née"), birth and death (day and place), citizenship |
| book | literary works with an author and a page in 12 Wikipedias or more | author, first publication, series |
| film | films with a page in 20 Wikipedias or more | director, first release, producers, series, actors with a page in 15 Wikipedias or more |
| painting | paintings with a page in 10 Wikipedias or more | painter, when it was painted |
| album | albums with a page in 10 Wikipedias or more | performer, first release |
| videogame | video games with a page in 15 Wikipedias or more | first release, series, developer |
| river | rivers with a page in 20 Wikipedias or more | length (km), countries |
| mountain | mountains with a page in 20 Wikipedias or more | height (m), countries |
| ocean | the oceans that make up the World Ocean | area (km²) |
| planet | the eight planets of the Solar System | radius (km) |

The things these facts point at (a language, a currency, a place of birth, an author) are written too, with their
names. Every thing has its labels, other names and descriptions in French and English (and the name Wikidata gives for
every language at once, mul: Victor Hugo has no French label of his own), and how many Wikipedias have a page on it: when a name is shared, the far better known one is meant, else nothing is said.

Only the values Wikidata prefers are kept (its best rank; a deprecated value never); a membership with an end is left
out (the United Kingdom is no longer in the European Union). A measure is kept in one unit, converted from those
Wikidata gives (a length in miles, a height in feet), and a measure in a unit not listed is left out. A date keeps its precision, so a
year is never said as a day, and a date known only to the decade or less is not said at all. Two dates given for the
same birth, and nothing is said.

The file is plain text (gzip), one line a thing: `K` the kinds of a thing and how many Wikipedias have a page on it,
`L` a label, `A` another name, `D` a description, `F` a fact (property, value, then the precision of a date or the year
of a count).

Wikidata is under [CC0](https://creativecommons.org/publicdomain/zero/1.0/): its facts may be copied without asking.
Lambek still says where each answer comes from ("d'après Wikidata"), puts what it read on its board as read, with its
source and the day, and says it when asked why.
