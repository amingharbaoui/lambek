import { useEffect, useRef } from "react";
import { X } from "lucide-react";

// A small window over the app: it takes the focus, closes with Escape or a click outside, and gives the focus back
export default function Dialog({ title, onClose, children }) {
  const box = useRef(null);
  const closing = useRef(onClose);
  closing.current = onClose;

  useEffect(() => {
    const before = document.activeElement;
    box.current?.focus();
    const close = (event) => event.key === "Escape" && closing.current();
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("keydown", close);
      before?.focus?.();
    };
  }, []);

  return (
    <div className="dialog-backdrop" onMouseDown={onClose}>
      <div className="dialog" role="dialog" aria-modal="true" aria-label={title} tabIndex={-1} ref={box} onMouseDown={(event) => event.stopPropagation()}>
        <header>
          <h2>{title}</h2>
          <button className="icon-button small" onClick={onClose} aria-label="Close">
            <X size={14} />
          </button>
        </header>
        {children}
      </div>
    </div>
  );
}
