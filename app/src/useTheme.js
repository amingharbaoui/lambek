import { useEffect, useState } from "react";
import { load, save } from "./storage.js";
import { isDesktop } from "./lambek.js";

const query = "(prefers-color-scheme: dark)";
const ORDER = ["system", "light", "dark"];

// "system", "light", or "dark"; incognito follows it with its own frame
export default function useTheme(incognito) {
  const [preference, setPreference] = useState(() => load("lambek.theme", "system"));
  const [systemDark, setSystemDark] = useState(() => window.matchMedia(query).matches);

  useEffect(() => {
    const media = window.matchMedia(query);
    const listener = (event) => setSystemDark(event.matches);
    media.addEventListener("change", listener);
    return () => media.removeEventListener("change", listener);
  }, []);

  const theme = preference === "system" ? (systemDark ? "dark" : "light") : preference;

  useEffect(() => {
    const root = document.documentElement;
    root.dataset.theme = theme;
    if (incognito) root.dataset.mode = "incognito";
    else delete root.dataset.mode;
  }, [theme, incognito]);

  // The glass of the window follows the chosen theme, so a light page is not laid on a dark blur. With "system" the
  // window is given back to the system: pinning it would also pin what the page reads as the system theme
  useEffect(() => {
    if (!isDesktop) return;
    import("@tauri-apps/api/window")
      .then(({ getCurrentWindow }) => getCurrentWindow().setTheme(preference === "system" ? null : preference))
      .catch(() => {});
  }, [preference]);

  function choose(value) {
    setPreference(value);
    save("lambek.theme", value);
  }

  function next() {
    choose(ORDER[(ORDER.indexOf(preference) + 1) % ORDER.length]);
  }

  return { preference, theme, choose, next };
}
