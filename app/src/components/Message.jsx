import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { FileText, Folder, Info } from "lucide-react";
import { TbEdit, TbReload } from "react-icons/tb";
import { CheckArc, CopySlot } from "./Icons.jsx";
import { Working } from "./Status.jsx";
import Reading from "./Reading.jsx";
import PlanActions from "./PlanActions.jsx";

const REPLY = /(replied:|a répondu :)$/;

// Plain text from the engine: numbered steps, bullets, and server replies
function AnswerText({ text }) {
  const lines = text.split("\n");
  const blocks = [];

  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    const last = blocks.at(-1);

    if (REPLY.test(line)) {
      blocks.push({ kind: "p", lines: [line] });
      blocks.push({ kind: "reply", lines: lines.slice(index + 1) });
      break;
    }
    if (/^\d+\.\s/.test(line)) {
      if (last?.kind === "ol") last.lines.push(line.replace(/^\d+\.\s/, ""));
      else blocks.push({ kind: "ol", lines: [line.replace(/^\d+\.\s/, "")] });
    } else if (/^-\s/.test(line)) {
      if (last?.kind === "ul") last.lines.push(line.slice(2));
      else blocks.push({ kind: "ul", lines: [line.slice(2)] });
    } else if (line.trim()) {
      blocks.push({ kind: "p", lines: [line] });
    }
  }

  return (
    <div className="answer-text">
      {blocks.map((block, index) => {
        if (block.kind === "ol") return <ol key={index}>{block.lines.map((item, i) => <li key={i}><span className="words">{item}</span></li>)}</ol>;
        if (block.kind === "ul") return <ul key={index}>{block.lines.map((item, i) => <li key={i}><span className="words">{item}</span></li>)}</ul>;
        if (block.kind === "reply") return <div key={index} className="reply">{block.lines.join("\n")}</div>;
        return (
          <p key={index}>
            <span className="words">{block.lines[0]}</span>
          </p>
        );
      })}
    </div>
  );
}

// "Just now", "5 minutes ago", "3 hours ago", "Yesterday", then the date
function sentAgo(time, now) {
  const minutes = Math.floor((now - time) / 60000);
  if (minutes < 1) return "Just now";
  if (minutes < 60) return `${minutes} minute${minutes === 1 ? "" : "s"} ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  if (hours < 48) return "Yesterday";
  return new Date(time).toLocaleDateString("en-US", { month: "short", day: "numeric", year: new Date(time).getFullYear() === new Date(now).getFullYear() ? undefined : "numeric" });
}

// The time of every request moves on together, once a minute
const clocks = new Set();
setInterval(() => clocks.forEach((tick) => tick(Date.now())), 30000);
function useNow() {
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    clocks.add(setNow);
    return () => clocks.delete(setNow);
  }, []);
  return now;
}

// Edit in place: Enter sends the new words as a new request, Escape keeps the old ones
// Edit in place, in the bubble itself: Enter sends the new words, Escape keeps the old ones
function EditBox({ text, width, onSend, onCancel, busy }) {
  const [value, setValue] = useState(text);
  const box = useRef(null);

  useEffect(() => {
    const field = box.current;
    if (!field) return;
    field.focus();
    field.setSelectionRange(field.value.length, field.value.length);
  }, []);

  useLayoutEffect(() => {
    const field = box.current;
    if (!field) return;
    field.style.height = "auto";
    field.style.height = `${field.scrollHeight}px`;
  }, [value]);

  const canSend = !busy && value.trim() && value.trim() !== text.trim();

  return (
    <>
      <div className="bubble editing" style={{ width }}>
        <textarea
          ref={box}
          value={value}
          rows={1}
          onChange={(event) => setValue(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Escape") onCancel();
            if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
              event.preventDefault();
              if (canSend) onSend(value.trim());
            }
          }}
          aria-label="Edit request"
        />
      </div>
      <div className="edit-actions">
        <span className="edit-info" data-tip="Sending replaces this message and starts again from here" aria-label="Sending replaces this message and starts again from here" tabIndex={0}>
          <Info size={14} />
        </span>
        <button className="edit-cancel" onClick={onCancel}>
          Cancel
        </button>
        <button className="edit-send" disabled={!canSend} onClick={() => onSend(value.trim())}>
          Send
        </button>
      </div>
    </>
  );
}

export function Request({ message, busy, onEdit }) {
  const [editing, setEditing] = useState(false);
  const [width, setWidth] = useState(null);
  const bubble = useRef(null);
  const [copied, setCopied] = useState(false);
  const timer = useRef(null);
  useEffect(() => () => clearTimeout(timer.current), []);

  function copy() {
    navigator.clipboard
      ?.writeText(message.text)
      .then(() => {
        setCopied(true);
        clearTimeout(timer.current);
        timer.current = setTimeout(() => setCopied(false), 1500);
      })
      .catch(() => {});
  }

  const now = useNow();
  const exact = new Date(message.at).toLocaleString("en-US", { dateStyle: "full", timeStyle: "short" });

  return (
    <div className={`request ${editing ? "is-editing" : ""}`}>
      {/* Only the message itself reacts to the pointer, not the empty width beside it */}
      <div className="request-body">
        {message.attachments?.length > 0 && (
          <div className="request-files">
            {message.attachments.map((file) =>
              file.isImage && file.preview ? (
                <img key={file.path} src={file.preview} alt={file.name} title={file.path} />
              ) : (
                <div key={file.path} className="file" title={file.path}>
                  {file.isFolder ? <Folder size={16} /> : <FileText size={16} />}
                  <span className="file-name">{file.name}</span>
                  {(file.isFolder || file.extension) && <span className="file-type">{file.isFolder ? "folder" : file.extension}</span>}
                </div>
              ),
            )}
          </div>
        )}
        {message.text &&
          (editing ? (
            <EditBox
              text={message.text}
              width={width}
              busy={busy}
              onCancel={() => setEditing(false)}
              onSend={(text) => {
                setEditing(false);
                onEdit?.(text, message.attachments ?? []);
              }}
            />
          ) : (
            <div className="bubble" ref={bubble}>
              {message.text}
            </div>
          ))}

        {/* On hover: when it was sent, then edit and copy */}
        {!editing && (
          <div className="request-actions">
            <time dateTime={new Date(message.at).toISOString()} title={exact}>
              {sentAgo(message.at, now)}
            </time>
            {message.text && (
              <>
                <button
                  onClick={() => {
                    // The edit box keeps the size of the bubble, a little wider for the caret
                    setWidth(bubble.current ? bubble.current.offsetWidth + 24 : null);
                    setEditing(true);
                  }}
                  data-tip="Edit"
                  aria-label="Edit"
                >
                  <TbEdit size={16} />
                </button>
                <button onClick={copy} data-tip={copied ? "Copied" : "Copy"} aria-label="Copy">
                  {copied ? <CheckArc size={15} /> : <CopySlot size={15} />}
                </button>
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// Copy a text, with a check for a moment
function useCopy() {
  const [copied, setCopied] = useState(false);
  const timer = useRef(null);
  useEffect(() => () => clearTimeout(timer.current), []);
  function copy(text) {
    navigator.clipboard
      ?.writeText(text)
      .then(() => {
        setCopied(true);
        clearTimeout(timer.current);
        timer.current = setTimeout(() => setCopied(false), 1500);
      })
      .catch(() => {});
  }
  return [copied, copy];
}

export function Answer({ message, onOpenStep, onRetry, canRetry }) {
  const now = useNow();
  const [copied, copy] = useCopy();
  const { plan, simulation, execution } = message;
  // After an error, the plan's own words, not an invitation to go on
  const text = message.error ? (plan?.answer ?? message.answer) : (execution?.answer ?? simulation?.answer ?? plan?.answer ?? message.answer);
  const busy = Boolean(message.busy);

  // What Copy takes: the words, or else the rows of the result, one path per line
  const rows = (execution?.steps ?? []).flatMap((step) => (Array.isArray(step.output) ? step.output : []));
  const copyText =
    text ||
    rows
      .map((row) => (row && typeof row === "object" ? (row.FullName ?? row.Path ?? row.Name ?? Object.values(row).join("\t")) : String(row)))
      .join("\n");

  return (
    <div className="answer">
      {text && <AnswerText text={text} />}
      {message.error && <p className="error">{message.error}</p>}
      {message.note && <p className="note">{message.note}</p>}
      {!busy && <PlanActions message={message} />}

      {/* The status: one line that writes itself while Lambek works, then stays as the reading of the request */}
      {busy && message.busy.progress ? (
        <Working word={message.busy.word} percent={message.busy.percent} progress />
      ) : (
        <Reading message={message} onOpenStep={onOpenStep} />
      )}

      {/* On hover: when it answered, then copy and retry */}
      {!busy && (
        <div className="answer-actions">
          <time dateTime={new Date(message.at).toISOString()} title={new Date(message.at).toLocaleString("en-US", { dateStyle: "full", timeStyle: "short" })}>
            {sentAgo(message.at, now)}
          </time>
          {copyText && (
            <button onClick={() => copy(copyText)} data-tip={copied ? "Copied" : "Copy"} aria-label="Copy">
              {copied ? <CheckArc size={15} /> : <CopySlot size={15} />}
            </button>
          )}
          {onRetry && (
            <button onClick={onRetry} disabled={!canRetry} data-tip="Retry" aria-label="Retry">
              <TbReload size={16} />
            </button>
          )}
        </div>
      )}
    </div>
  );
}
