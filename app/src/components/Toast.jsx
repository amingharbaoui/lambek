import { useEffect, useState } from "react";
import { Info, X } from "lucide-react";

const EVENT = "lambek-toast";

// Say one short thing at the bottom right of the window, from anywhere in the app
export function notify(text) {
  window.dispatchEvent(new CustomEvent(EVENT, { detail: text }));
}

// The notification: it leaves by itself after a few seconds, or at once with its cross
export default function Toast() {
  const [toast, setToast] = useState(null);

  useEffect(() => {
    const show = (event) => setToast({ text: event.detail, id: Date.now() });
    window.addEventListener(EVENT, show);
    return () => window.removeEventListener(EVENT, show);
  }, []);

  useEffect(() => {
    if (!toast) return;
    const timer = setTimeout(() => setToast(null), 3400);
    return () => clearTimeout(timer);
  }, [toast]);

  return (
    <div className="toast-area" role="status" aria-live="polite">
      {toast && (
        <div className="toast" key={toast.id}>
          <Info size={15} />
          <span>{toast.text}</span>
          <button className="icon-button small" onClick={() => setToast(null)} aria-label="Dismiss">
            <X size={13} />
          </button>
        </div>
      )}
    </div>
  );
}
