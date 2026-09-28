import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { parseTypes, placeImplied, reduce } from "../reduction.js";

const LETTER_MS = 34;

function show(type) {
  return type.base + (type.marks ? `^${type.marks}` : "");
}

// Where a type that did not cancel still needs a partner: x^l on its right, anything else on its left
function sideOf(type) {
  return type.order < 0 ? "right" : "left";
}

// How Lambek read a step, written letter by letter: its pregroup types, the pairs that cancel
// (x^l x and x x^r), and s when the sentence is complete. A letter or a link that did not hold changes color.
export default function ProofLine({ step, types, numbered, onOpen, onTyped, failed, typing = false, working = false }) {
  const parsed = useMemo(() => placeImplied(parseTypes(types ?? "")), [types]);
  const { pairs, leftover } = useMemo(() => reduce(parsed), [parsed]);
  const row = useRef(null);
  const [arcs, setArcs] = useState([]);

  // The sentence type s is the one type allowed to stay
  const { kept, loose } = useMemo(() => {
    const sentence = leftover.find((index) => parsed[index].base === "s" && !parsed[index].marks);
    return { kept: sentence, loose: leftover.filter((index) => index !== sentence) };
  }, [parsed, leftover]);
  const reduced = kept !== undefined && loose.length === 0;
  const untyped = parsed.length === 0;

  // Letter by letter
  const total = untyped ? 0 : parsed.reduce((sum, type) => sum + type.base.length + type.marks.length, 0);
  const [shown, setShown] = useState(typing ? 0 : total);
  const done = shown >= total;
  useEffect(() => {
    if (done) {
      onTyped?.();
      return;
    }
    const timer = setTimeout(() => setShown((count) => count + 1), LETTER_MS);
    return () => clearTimeout(timer);
  }, [shown, done]);

  // Arcs under the types once they are written: an arc that holds others goes deeper; a link that let go hangs, dashed
  useLayoutEffect(() => {
    const box = row.current;
    if (!box || !done) return setArcs([]);
    const origin = box.getBoundingClientRect().left;
    const centers = [...box.querySelectorAll(".type")].map((cell) => {
      const rect = cell.getBoundingClientRect();
      return rect.left - origin + rect.width / 2;
    });
    const held = pairs.map(([left, right]) => {
      const inside = pairs.filter(([a, b]) => a > left && b < right).length;
      return { d: `M${centers[left]} 1 C${centers[left]} ${6 + 4 * Math.min(inside, 4)}, ${centers[right]} ${6 + 4 * Math.min(inside, 4)}, ${centers[right]} 1`, depth: 6 + 4 * Math.min(inside, 4) };
    });
    const hanging = loose.map((index) => {
      const x = centers[index];
      const reach = sideOf(parsed[index]) === "right" ? 12 : -12;
      return { d: `M${x} 1 C${x} 8, ${x + reach * 0.6} 9, ${x + reach} 7`, depth: 9, broken: true, end: { x: x + reach, y: 7 } };
    });
    setArcs([...held, ...hanging]);
  }, [pairs, loose, parsed, done]);

  const depth = Math.max(10, ...arcs.map((arc) => arc.depth + 2));
  const reading = untyped ? "no type" : parsed.map(show).join(" ");
  const waits = loose.map((index) => show(parsed[index]));
  const label = [
    `Step ${step}: ${reading}`,
    reduced ? "reduces to s" : "does not reduce to s",
    waits.length > 0 ? `${waits.join(", ")} left alone` : "",
    failed ?? "",
  ]
    .filter(Boolean)
    .join(", ");

  // The letters written so far, cell by cell
  let left = shown;
  const cells = parsed.map((type, index) => {
    const text = type.base + type.marks;
    const count = Math.max(0, Math.min(text.length, left));
    left -= text.length;
    return { index, base: text.slice(0, Math.min(count, type.base.length)), marks: text.slice(type.base.length, count) };
  });
  const tone = failed ? "failed" : reduced ? "" : "open";

  return (
    <button className={`proof ${tone} ${working || !done ? "working" : ""}`} onClick={onOpen} disabled={!onOpen || !done} aria-label={onOpen ? `${label}. Show the nodes.` : label} title={failed ?? undefined}>
      {numbered && <span className="proof-step">{step}</span>}
      <span className="proof-types" ref={row} aria-hidden="true">
        {cells.map(
          (cell) =>
            cell.base && (
              <span
                key={cell.index}
                className={`type ${cell.index === kept ? "kept" : ""} ${loose.includes(cell.index) ? "loose" : ""} ${parsed[cell.index].implied ? "implied" : ""}`}
                title={parsed[cell.index].implied ? "Supplied by the folder you named" : undefined}
              >
                {cell.base}
                {cell.marks && <sup>{cell.marks}</sup>}
              </span>
            ),
        )}
        <svg className="proof-arcs" height={depth} aria-hidden="true">
          {arcs.map((arc, index) => (
            <g key={index}>
              <path className={arc.broken ? "broken" : ""} pathLength="1" d={arc.d} />
              {/* The partner that never came: an empty node at the loose end */}
              {arc.end && <circle className="broken" cx={arc.end.x} cy={arc.end.y} r="2.2" />}
            </g>
          ))}
        </svg>
      </span>
      {done && (
        <span className="proof-result" aria-hidden="true">
          {reduced ? "⊢" : "⊬"} <i>s</i>
        </span>
      )}
    </button>
  );
}
