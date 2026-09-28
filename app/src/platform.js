// The desktop system, for its fonts, shortcuts, and window buttons
function detect() {
  const agent = navigator.userAgent;
  if (/Mac/.test(agent)) return "mac";
  if (/Windows/.test(agent)) return "windows";
  return "linux";
}

export const platform = detect();

export const PLATFORM_NAMES = { windows: "Windows", mac: "macOS", linux: "Linux" };

// "Ctrl+Shift+N" as each system writes it: ⇧⌘N on macOS, modifiers in the order ⌃⌥⇧⌘
const MAC_KEYS = { Control: "⌃", Alt: "⌥", Shift: "⇧", Ctrl: "⌘", Enter: "↩", Esc: "⎋", Tab: "⇥" };
const MAC_ORDER = ["⌃", "⌥", "⇧", "⌘"];

export function keys(text) {
  if (!text || platform !== "mac") return text;
  return text
    .split(" / ")
    .map((combo) => {
      const parts = combo.split("+").map((part) => MAC_KEYS[part] ?? part);
      const modifiers = parts.filter((part) => MAC_ORDER.includes(part)).sort((a, b) => MAC_ORDER.indexOf(a) - MAC_ORDER.indexOf(b));
      return [...modifiers, ...parts.filter((part) => !MAC_ORDER.includes(part))].join("");
    })
    .join(" / ");
}
