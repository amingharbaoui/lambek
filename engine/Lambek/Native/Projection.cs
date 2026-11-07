using System;
using System.Collections.Generic;
using System.Linq;

// More sentences for a language whose treebanks are small, from its sentences translated from English: each is read
// by the forms model of the language, and its words are aligned with the English words read by the model of English
// (IBM Model 1 both ways, LambekAligner). The part of speech of an English word is carried over to the word it is
// aligned with (Yarowsky & Ngai 2001; Das & Petrov 2011), as far as it is carried over right: how often the words the
// treebanks know carry over to their own part of speech, as learned on the same pairs. A sentence is kept when every
// word carried over by a part of speech right `doubt` of the time agrees with the reading of the model, or, carried
// over by one right `trust` of the time, is set right by what the treebanks or the lexicon say of the word; and when every word the treebanks never met is either carried over or
// read as the lexicon reads it; and when it has one such word at least, the words a small treebank is missing
// (Tackstrom et al. 2013: the words' tags, and the tokens carried over, constrain each other). They teach the tagger
// only (LambekForms.Train). Every pair is read in the order given, so the same sentences give the same ones kept
public static class LambekProjection
{
    public sealed class Result
    {
        public List<LambekTreebankWord[]> Sentences = new List<LambekTreebankWord[]>();
        // The parts of speech carried over, each with how often the known words carried over to their own
        public SortedDictionary<string, double> Trust = new SortedDictionary<string, double>(StringComparer.Ordinal);
        public int Pairs, Linked, Agreed, SetRight, Refused, Unsure, Known;
    }

    public static Result Project(LambekForms english, LambekForms other, IList<string> englishSide, IList<string> otherSide, int longest, int passes, double trust, double doubt, int least)
    {
        Result result = new Result();
        List<string[]> englishForms = new List<string[]>(), otherForms = new List<string[]>();
        List<string[]> englishTags = new List<string[]>();
        List<LambekFormReading[]> readings = new List<LambekFormReading[]>();
        int count = Math.Min(englishSide.Count, otherSide.Count);
        for (int i = 0; i < count; i++)
        {
            LambekFormReading[] first = english.ReadText(englishSide[i] ?? "");
            if (first.Length == 0 || first.Length > longest) continue;
            LambekFormReading[] second = other.ReadText(otherSide[i] ?? "");
            if (second.Length == 0 || second.Length > longest) continue;
            englishForms.Add(first.Select(r => r.Form).ToArray());
            englishTags.Add(first.Select(r => r.Upos).ToArray());
            otherForms.Add(second.Select(r => r.Form).ToArray());
            readings.Add(second);
        }
        result.Pairs = readings.Count;
        LambekAligner aligner = new LambekAligner(englishForms, otherForms);
        englishForms = null; otherForms = null;
        aligner.Train(passes);
        List<int[]> links = new List<int[]>(readings.Count);
        for (int s = 0; s < readings.Count; s++) links.Add(aligner.Links(s));
        aligner = null;

        // Which parts of speech carry over right: on the words the treebanks saw with one part of speech only
        Dictionary<string, int> agree = new Dictionary<string, int>(StringComparer.Ordinal), met = new Dictionary<string, int>(StringComparer.Ordinal);
        for (int s = 0; s < readings.Count; s++)
        {
            for (int j = 0; j < readings[s].Length; j++)
            {
                int i = links[s][j];
                if (i < 0) continue;
                string own = Own(other, readings[s][j].Form);
                if (own == null) continue;
                string carried = englishTags[s][i];
                int n; met.TryGetValue(carried, out n); met[carried] = n + 1;
                if (own == carried) { agree.TryGetValue(carried, out n); agree[carried] = n + 1; }
            }
        }
        HashSet<string> trusted = new HashSet<string>(StringComparer.Ordinal), weighed = new HashSet<string>(StringComparer.Ordinal);
        foreach (KeyValuePair<string, int> pair in met)
        {
            int n; agree.TryGetValue(pair.Key, out n);
            result.Trust[pair.Key] = (double) n / pair.Value;
            if (pair.Value >= least && n >= trust * pair.Value) trusted.Add(pair.Key);
            if (pair.Value >= least && n >= doubt * pair.Value) weighed.Add(pair.Key);
        }

        HashSet<string> classes = new HashSet<string>(other.Tagger.Classes, StringComparer.Ordinal);
        for (int s = 0; s < readings.Count; s++)
        {
            LambekTreebankWord[] words = new LambekTreebankWord[readings[s].Length];
            bool keep = true, fresh = false;
            int linked = 0, agreed = 0, setRight = 0;
            for (int j = 0; j < words.Length && keep; j++)
            {
                LambekFormReading reading = readings[s][j];
                string lower = (reading.Form ?? "").ToLowerInvariant();
                bool known = other.Tags.ContainsKey(lower);
                LambekLexiconEntry[] entries = null;
                bool listed = other.Lexicon != null && other.Lexicon.TryGet(lower, out entries);
                int i = links[s][j];
                string carried = i >= 0 && weighed.Contains(englishTags[s][i]) ? englishTags[s][i] : null;
                LambekTreebankWord word = new LambekTreebankWord { Form = reading.Form, Lemma = reading.Lemma, Upos = reading.Upos, Feats = reading.Feats };
                if (carried != null)
                {
                    linked++;
                    if (carried == reading.Upos) agreed++;
                    else if (trusted.Contains(carried) && SetRight(other, classes, lower, carried, entries, word)) setRight++;
                    else { keep = false; result.Refused++; }
                }
                else if (!known && !(listed && entries.Any(e => e.Upos == reading.Upos))) { keep = false; result.Unsure++; }
                if (!known) fresh = true;
                words[j] = word;
            }
            if (!keep) continue;
            if (!fresh) { result.Known++; continue; }
            result.Linked += linked; result.Agreed += agreed; result.SetRight += setRight;
            result.Sentences.Add(words);
        }
        return result;
    }

    // The one part of speech the treebanks saw a word with; null for a word never seen, or seen with several
    static string Own(LambekForms model, string form)
    {
        string[] tags;
        if (!model.Tags.TryGetValue((form ?? "").ToLowerInvariant(), out tags) || tags.Length == 0) return null;
        string upos = tags[0].Split('|')[0];
        foreach (string tag in tags) if (tag.Split('|')[0] != upos) return null;
        return upos;
    }

    // A word carried over to another part of speech than the model read: the tag the treebanks saw it with most in that
    // part of speech, or the reading the lexicon gives it in it (whole, a tag of the model)
    static bool SetRight(LambekForms model, HashSet<string> classes, string lower, string upos, LambekLexiconEntry[] entries, LambekTreebankWord word)
    {
        LambekLexiconEntry entry = entries == null ? null : entries.FirstOrDefault(e => e.Upos == upos);
        string[] tags;
        string tag = model.Tags.TryGetValue(lower, out tags) ? tags.FirstOrDefault(t => t.Split('|')[0] == upos) : null;
        if (tag == null && entry != null && classes.Contains(upos + "|" + (string.IsNullOrEmpty(entry.Feats) ? "_" : entry.Feats))) tag = upos + "|" + (string.IsNullOrEmpty(entry.Feats) ? "_" : entry.Feats);
        if (tag == null) return false;
        int bar = tag.IndexOf('|');
        word.Upos = tag.Substring(0, bar);
        word.Feats = tag.Substring(bar + 1);
        return true;
    }
}
