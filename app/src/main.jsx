import React from "react";
import ReactDOM from "react-dom/client";
import "@fontsource-variable/stix-two-text";
import "@fontsource-variable/stix-two-text/wght-italic.css";
import App from "./App.jsx";
import { isDesktop } from "./lambek.js";
import { platform } from "./platform.js";
import "./styles.css";

// The system decides the fonts and the window buttons
document.documentElement.dataset.platform = platform;

// Like a native app: no web menu on right click, except to copy selected text or edit a field
document.addEventListener("contextmenu", (event) => {
  const editable = event.target.closest?.("input, textarea, [contenteditable='true']");
  const selected = String(window.getSelection?.() ?? "").trim().length > 0;
  if (!editable && !selected) event.preventDefault();
});

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);

// The window stays hidden until the first frame is painted
if (isDesktop) {
  requestAnimationFrame(() =>
    import("@tauri-apps/api/window").then(({ getCurrentWindow }) => getCurrentWindow().show()),
  );
}
