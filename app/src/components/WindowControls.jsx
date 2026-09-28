import { useEffect, useState } from "react";
import { isDesktop } from "../lambek.js";
import { platform } from "../platform.js";

function currentWindow() {
  return import("@tauri-apps/api/window").then(({ getCurrentWindow }) => getCurrentWindow());
}

// Minimize, maximize, and close, drawn by the app because the window has no title bar
export default function WindowControls() {
  const [maximized, setMaximized] = useState(false);

  useEffect(() => {
    if (!isDesktop || platform === "mac") return;
    let live = true;
    let stop = () => {};
    currentWindow().then(async (window) => {
      const update = async () => {
        const value = await window.isMaximized().catch(() => false);
        if (live) setMaximized(Boolean(value));
      };
      update();
      const unlisten = await window.onResized(update).catch(() => () => {});
      if (live) stop = unlisten;
      else unlisten();
    });
    return () => {
      live = false;
      stop();
    };
  }, []);

  // macOS draws its own traffic lights
  if (!isDesktop || platform === "mac") return null;

  const act = (name) => currentWindow().then((window) => window[name]());

  return (
    <div className="window-controls">
      <button onClick={() => act("minimize")} title="Minimize" aria-label="Minimize">
        <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true">
          <path d="M0 5h10" />
        </svg>
      </button>
      <button onClick={() => act("toggleMaximize")} title={maximized ? "Restore" : "Maximize"} aria-label={maximized ? "Restore" : "Maximize"}>
        {maximized ? (
          <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true">
            <path d="M2.5 2.5V.5h7v7h-2M.5 2.5h7v7h-7z" />
          </svg>
        ) : (
          <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true">
            <path d="M.5.5h9v9h-9z" />
          </svg>
        )}
      </button>
      <button className="close" onClick={() => act("close")} title="Close" aria-label="Close">
        <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true">
          <path d="M.5.5l9 9M9.5.5l-9 9" />
        </svg>
      </button>
    </div>
  );
}
