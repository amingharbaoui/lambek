import { useEffect, useRef } from "react";
import { ArrowUp, CircleStop, FileText, Folder, X } from "lucide-react";
import PlusMenu from "./PlusMenu.jsx";
import { PiArrowElbowDownLeftBold } from "react-icons/pi";
import { keys } from "../platform.js";

// Under the composer of a chat: the one thing to keep in mind
const NOTICE = "Lambek can misread requests.";

export default function Composer({ text, onText, busy, onStop, attachments, onAttach, onDetach, onSend, onInsert, onTools, focus, onClearFocus, placeholder, focusToken, compact = false }) {
  const field = useRef(null);

  // The field grows with its text, and takes the focus when a text is set from outside
  useEffect(() => {
    const element = field.current;
    if (!element) return;
    element.style.height = "auto";
    element.style.height = `${Math.min(element.scrollHeight, 233)}px`;
  }, [text]);

  useEffect(() => {
    field.current?.focus();
  }, [focus, focusToken]);

  const canSend = !busy && (text.trim() || attachments.length > 0);

  function send() {
    if (canSend) onSend(text);
  }

  const focusChip = focus && (
    <span className="focus-chip" title="Your next message is about this step">
      step {focus.step} · {focus.action}
      <button onClick={onClearFocus} aria-label="Clear step">
        <X size={11} />
      </button>
    </span>
  );

  // Send: an arrow while empty; once there is something to send, the return that sends it
  const action = busy ? (
    <button className="stop" onClick={onStop} data-tip="Stop" data-keys={keys("Esc")} aria-label="Stop">
      <CircleStop size={18} />
    </button>
  ) : (
    <button className={`send ${compact ? "quiet" : ""}`} onClick={send} disabled={!canSend} data-tip="Send message" data-keys={keys("Enter")} aria-label="Send message">
      {compact ? <PiArrowElbowDownLeftBold size={15} /> : <ArrowUp size={16} />}
    </button>
  );

  const field_ = (
    <textarea
      ref={field}
      value={text}
      rows={1}
      placeholder={placeholder}
      aria-label="Request"
      onChange={(event) => onText(event.target.value)}
      onKeyDown={(event) => {
        if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
          event.preventDefault();
          send();
        }
      }}
      autoFocus
    />
  );

  const box = (
    <div className={`composer ${compact ? "compact" : ""}`}>
      {attachments.length > 0 && (
        <div className="files">
          {attachments.map((file) => (
            <div key={file.path} className={`file ${file.isImage ? "image" : ""}`} title={file.path}>
              {file.isImage && file.preview ? (
                <img src={file.preview} alt={file.name} />
              ) : (
                <>
                  {file.isFolder ? <Folder size={15} /> : <FileText size={15} />}
                  <span className="file-name">{file.name}</span>
                  <span className="file-type">{file.isFolder ? "folder" : file.extension}</span>
                </>
              )}
              <button className="file-remove" onClick={() => onDetach(file.path)} title="Remove" aria-label={`Remove ${file.name}`}>
                <X size={11} strokeWidth={2} />
              </button>
            </div>
          ))}
        </div>
      )}

      {compact ? (
        <div className="composer-row">
          {field_}
          {action}
        </div>
      ) : (
        field_
      )}

      {!compact && (
        <div className="composer-bar">
          <PlusMenu onAttach={onAttach} onInsert={onInsert} onTools={onTools} />
          {focusChip}
          <span className="spacer" />
          {action}
        </div>
      )}
    </div>
  );

  if (!compact) return box;

  // In a chat: a slim composer, and below it the + and a line of mathematics
  return (
    <div className="composer-wrap">
      {box}
      <div className="composer-foot">
        <PlusMenu onAttach={onAttach} onInsert={onInsert} onTools={onTools} />
        {focusChip}
        <span className="signature">{NOTICE}</span>
      </div>
    </div>
  );
}
