import { useEffect, useRef } from "react";
import { ArrowUp, CircleStop, FileText, Folder, X } from "lucide-react";
import PlusMenu from "./PlusMenu.jsx";
import { PiArrowElbowDownLeftBold } from "react-icons/pi";
import { keys } from "../platform.js";
import { t } from "../i18n.js";
import { openUrl, REPOSITORY } from "../lambek.js";

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
    <span className="focus-chip" title={t("Your next message is about this step")}>
      {t("step")} {focus.step} · {focus.action}
      <button onClick={onClearFocus} aria-label={t("Clear step")}>
        <X size={11} />
      </button>
    </span>
  );

  // Send: an arrow while empty; once there is something to send, the return that sends it
  const action = busy ? (
    <button className="stop" onClick={onStop} data-tip={t("Stop")} data-keys={keys("Esc")} aria-label={t("Stop")}>
      <CircleStop size={18} />
    </button>
  ) : (
    <button className={`send ${compact ? "quiet" : ""}`} onClick={send} disabled={!canSend} data-tip={t("Send message")} data-keys={keys("Enter")} aria-label={t("Send message")}>
      {compact ? <PiArrowElbowDownLeftBold size={15} /> : <ArrowUp size={16} />}
    </button>
  );

  const field_ = (
    <textarea
      ref={field}
      value={text}
      rows={1}
      placeholder={placeholder}
      aria-label={t("Request")}
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
              <button className="file-remove" onClick={() => onDetach(file.path)} title={t("Remove")} aria-label={t("Remove {0}", file.name)}>
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

  // In a chat: a slim composer, and below it the + and one small line
  return (
    <div className="composer-wrap">
      {box}
      <div className="composer-foot">
        <PlusMenu onAttach={onAttach} onInsert={onInsert} onTools={onTools} />
        {focusChip}
        <Disclaimer />
      </div>
    </div>
  );
}

// One small line under the composer: Lambek can be wrong, and where to read how it works
export function Disclaimer() {
  const page = `https://github.com/${REPOSITORY}`;
  return (
    <p className="disclaimer">
      <a
        href={page}
        onClick={(event) => {
          event.preventDefault();
          openUrl(page);
        }}
      >
        {t("Lambek can make mistakes. Check the proof.")}
      </a>
    </p>
  );
}
