import { useRef, useState } from "react";
import { ChevronRight } from "lucide-react";
import ProofLine from "./ProofLine.jsx";
import { parseTypes, placeImplied, reduce } from "../reduction.js";
import { language, parameterName, t } from "../i18n.js";

const plurals = new Intl.PluralRules(language);

// Why a step stopped after it was read: blocked by the checks, refused, or failed while running
function stopOf(step, message) {
  if (["Blocked", "Invalid"].includes(step.status)) return t("Blocked by the checks");
  const run = message.execution?.steps?.find((item) => item.step === step.step);
  if (run?.status === "Failed") return run.error ? t("Failed: {0}", run.error) : t("Failed");
  if (run?.status === "Refused" || message.execution?.status === "Refused") return t("Refused");
  if (message.error) return t("Stopped with an error");
  return null;
}

// Every step that was read, understood or not, under the answer that created or changed the plan;
// under a later answer, only a step that stopped. Without a plan, what was read before the error.
export function readings(message, every = false) {
  const steps = message.plan?.steps ?? [];
  if (steps.length > 0) {
    const all = steps
      .filter((step) => step.types || step.clause)
      .map((step) => ({ step: step.step, types: step.types, words: step.clause, failed: stopOf(step, message) }));
    return every || ["new", "edit"].includes(message.kind) ? all : all.filter((step) => step.failed);
  }
  return Object.entries(message.reading ?? {}).map(([step, types]) => ({ step: Number(step), types, failed: message.error ? t("Stopped with an error") : null }));
}

function complete(step) {
  if (step.failed || !step.types) return false;
  const types = placeImplied(parseTypes(step.types));
  const { leftover } = reduce(types);
  return leftover.length === 1 && types[leftover[0]].base === "s" && !types[leftover[0]].marks;
}


// Why a choice is not reliable
const REASONS = { protection: t("one signal decides alone"), chisquare: t("contradictory signals"), probability: t("probability too low") };

function integrityLines(integrity) {
  if (!integrity) return [];
  if (integrity.available) return [t("Reliable")];
  return [t("Not reliable: {0}", (integrity.reasons ?? []).map((reason) => REASONS[reason] ?? reason).join(", "))];
}

function listOf(words) {
  return words.length > 1 ? t("{0} and {1}", words.slice(0, -1).join(", "), words.at(-1)) : (words[0] ?? "");
}

// Each stage of the engine says in a sentence what it did; some keep more under their arrow
function describe(row, message) {
  const steps = message.plan?.steps ?? [];
  const step = steps.find((item) => item.step === row.step);
  const values = Object.entries(step?.parameters ?? {});

  switch (row.stage) {
    case "Split": {
      if (steps.length < 2) return { title: t("One task") };
      return { title: t("{0} tasks", steps.length), lines: steps.map((item) => item.title ?? t("Something to clarify")) };
    }
    case "Read":
      if (values.length === 0) return { title: t("No parameters") };
      return {
        title: t("Parameters: {0}", listOf(values.map(([name]) => parameterName(name).toLocaleLowerCase(language)))),
        lines: values.map(([name, value]) => t("{0}: {1}", parameterName(name), value)),
      };
    case "Match":
      if (!step?.action) return { title: t("No action matches these words") };
      return {
        title: t("Action: {0}", step.title ?? step.action),
        lines: [
          t("Confidence {0}%", Math.round((step.confidence ?? 0) * 100)),
          ...integrityLines(step.integrity),
          ...(step.questions ?? []).map((question) => t("Missing: {0}", question.replace(/^Step \d+: /, ""))),
        ],
      };
    case "Check":
      if (!step?.script) return null;
      return {
        title: step.safe ? t("Script checked") : t("Script blocked"),
        code: step.script,
        lines: (step.violations ?? []).map((item) => t("Line {0}: {1}", item.line, item.text)),
      };
    case "Order": {
      const edges = message.plan?.edges ?? [];
      if (steps.length < 2) return null;
      return { title: edges.length > 0 ? t("Tasks in order") : t("Independent tasks"), lines: edges.map((edge) => edge.reason).filter(Boolean) };
    }
    case "Simulate": {
      const affected = (message.simulation?.steps ?? []).flatMap((item) => item.affected ?? []);
      const count = (message.simulation?.steps ?? []).reduce((sum, item) => sum + (item.count ?? 0), 0);
      return { title: count > 0 ? t(plurals.select(count) === "one" ? "{0} change" : "{0} changes", count) : t("Nothing changes"), lines: affected.slice(0, 12) };
    }
    case "Approve":
      return { title: t("Approved") };
    case "Run": {
      const done = message.execution?.status === "Completed";
      return { title: done ? t("Done") : t("Stopped"), lines: message.execution?.reason ? [message.execution.reason] : [] };
    }
    case "Edit":
      return { title: t("Value changed"), lines: row.detail ? [row.detail] : [] };
    case "Stop":
      return { title: row.detail, failed: true, lines: row.error ? [row.error] : [] };
    default:
      return row.detail ? { title: row.detail } : null;
  }
}

// One stage: its sentence lights up under the pointer, and the arrow opens what it did
function Stage({ item }) {
  const [open, setOpen] = useState(false);
  const more = Boolean(item.code) || (item.lines ?? []).length > 0;

  return (
    <li className={`stage ${item.failed ? "failed" : ""} ${more ? "more" : ""} ${open ? "open" : ""}`}>
      {more ? (
        <button className="stage-title" onClick={() => setOpen(!open)} aria-expanded={open}>
          {item.title}
          <ChevronRight size={13} />
        </button>
      ) : (
        <span className="stage-title">{item.title}</span>
      )}
      {open && (
        <div className="stage-body">
          {item.lines?.map((line, index) => (
            <p key={index}>{line}</p>
          ))}
          {item.code && <pre className="stage-code">{item.code}</pre>}
        </div>
      )}
    </li>
  );
}

// The stages of the engine: its trace, or, for a plan changed after it was read, one reading per step
function stagesOf(message, steps) {
  const trace = message.plan?.trace ?? [];
  const read = trace.length > 0 ? trace : (message.plan?.steps ?? []).flatMap((step) => ["Read", "Match", "Check"].map((stage) => ({ stage, step: step.step })));
  const rows = [
    ...read.filter((row) => row.stage !== "Type"),
    ...(message.events ?? []).map((event) => ({ stage: event.stage, detail: event.detail })),
    ...steps.filter((step) => step.failed).map((step) => ({ stage: "Stop", detail: step.failed })),
    ...(message.error && steps.every((step) => !step.failed) ? [{ stage: "Stop", detail: t("Stopped with an error"), error: message.error }] : []),
  ];
  return rows.map((row) => describe(row, message)).filter(Boolean);
}

// Everything behind the line: what each stage of the engine did, and where it stopped
function Process({ items }) {
  return (
    <ol className="process">
      {items.map((item, index) => (
        <Stage key={index} item={item} />
      ))}
    </ol>
  );
}

// The status of Lambek, on one line: the proof writes itself, the mark works at its end,
// and the arrow opens every other step and stage
export default function Reading({ message, onOpenStep }) {
  const busy = Boolean(message.busy);
  const fresh = useRef(busy || Date.now() - (message.at ?? 0) < 8000).current;
  const typed = useRef(new Set());
  const [open, setOpen] = useState(false);

  // While Lambek reads, the step being typed; while it checks or runs, the reading it already has
  const live = busy ? Object.entries(message.busy.types ?? {}).map(([step, types]) => ({ step: Number(step), types })) : [];
  const steps = live.length > 0 ? live : readings(message, busy);
  const main = live.length > 0 ? live.at(-1) : (steps.find((step) => !complete(step)) ?? steps.at(-1));
  // Every status has its arrow once Lambek is done
  const items = busy ? [] : stagesOf(message, steps);
  const more = items.length > 0;
  const key = main ? `${main.step}|${main.types ?? ""}` : "";

  // Small talk, or words without a single type: nothing to prove, so no status
  if (!busy && (!main || message.plan?.talk || steps.every((step) => !step.types))) return null;

  return (
    <div className="reading">
      <div className="reading-line" role="status" aria-live="polite">
        {main ? (
          <ProofLine
            key={key}
            step={main.step}
            types={main.types}
            words={main.words}
            failed={main.failed}
            numbered={steps.length > 1 || main.step > 1}
            typing={fresh && !typed.current.has(key)}
            onTyped={() => typed.current.add(key)}
            working={busy}
            onOpen={!busy && message.plan ? () => onOpenStep?.(main.step) : null}
          />
        ) : (
          // Before the first type: only the goal, s, under the light
          <span className="reading-goal working" aria-hidden="true">
            ⊢ <i>s</i>
          </span>
        )}
        {busy && <span className="visually-hidden">{message.busy.word}</span>}
        {more && (
          <button className={`reading-more ${open ? "open" : ""}`} onClick={() => setOpen(!open)} aria-expanded={open} aria-label={open ? t("Hide the steps") : t("Show every step")}>
            {steps.length > 1 && <span>{steps.length} {t("steps")}</span>}
            <ChevronRight size={14} />
          </button>
        )}
      </div>
      {open && more && <Process items={items} />}
    </div>
  );
}
