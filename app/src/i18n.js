// The words of the app in the language the user chose, or else in the language of the system when the app has it,
// otherwise in English: each table
// (src/locales/<language>.json) gives, for an English sentence of the app, the same sentence in its language. A
// sentence a table does not have stays in English. "{0}", "{1}": the values put in the sentence
import fr from "./locales/fr.json";
import { load, save } from "./storage.js";

const TABLES = { fr };

function pick() {
  const said = typeof navigator === "undefined" ? [] : (navigator.languages?.length ? navigator.languages : [navigator.language]);
  for (const tag of said) {
    const code = String(tag ?? "").slice(0, 2).toLowerCase();
    if (code === "en" || TABLES[code]) return code;
  }
  return "en";
}

// "system", or a language of the app, each named in itself, as every system lists them (from the data of Unicode)
function nameOf(code) {
  const name = new Intl.DisplayNames([code], { type: "language" }).of(code) ?? code;
  return name.charAt(0).toLocaleUpperCase(code) + name.slice(1);
}
export const LANGUAGES = Object.fromEntries(["en", ...Object.keys(TABLES)].map((code) => [code, nameOf(code)]));
export const chosen = load("lambek.language", "system");
export const language = LANGUAGES[chosen] ? chosen : pick();

// Right to left or left to right, from the data of the language, not from a list written here
export const direction = new Intl.Locale(language).getTextInfo?.().direction ?? new Intl.Locale(language).textInfo?.direction ?? "ltr";

// The words are set when the app starts, so a new language takes a reload
export function chooseLanguage(value) {
  save("lambek.language", value);
  location.reload();
}

// The spaces each language sets around its punctuation, so a sentence is written as its readers expect: French puts a
// no-break space before a colon and inside guillemets, a narrow one before ; ! ? and a no-break space before %
const SPACING = {
  fr: [
    [/ (:)/g, "\u00a0$1"],
    [/ ([;!?])/g, "\u202f$1"],
    [/« /g, "«\u00a0"],
    [/ »/g, "\u00a0»"],
    [/ %/g, "\u00a0%"],
  ],
};

export function typeset(text, said = language) {
  let out = String(text ?? "");
  for (const [pattern, spaced] of SPACING[said] ?? []) out = out.replace(pattern, spaced);
  return out;
}

export function t(text, ...values) {
  const said = TABLES[language]?.[text] ?? text;
  return typeset(said.replace(/\{(\d+)\}/g, (whole, index) => (values[Number(index)] ?? whole)));
}

// The name of a parameter of an action as people read it: "OlderThan" is "Older than"; a parameter no table knows
// (one from an MCP server) is cut at its capitals the same way
const PARAMETERS = {
  Path: "Folder",
  Name: "Name",
  Kind: "Kind",
  Extension: "Type",
  OlderThan: "Older than",
  NewerThan: "Newer than",
  MinSize: "Minimum size",
  MaxSize: "Maximum size",
  ExceptName: "Except the name",
  ExceptKind: "Except the kind",
  ExceptExtension: "Except the type",
  Order: "Order",
  Count: "Count",
  Source: "Source",
  Destination: "Destination",
  Permanent: "Permanently",
  Parent: "Parent folder",
  NewName: "New name",
  Language: "Language",
  FreeSize: "Free space",
};

export function parameterName(name) {
  const words = String(name).replace(/([a-z0-9])([A-Z])/g, "$1 $2").toLowerCase();
  return t(PARAMETERS[name] ?? words.charAt(0).toUpperCase() + words.slice(1));
}
