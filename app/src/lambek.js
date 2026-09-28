import { convertFileSrc, invoke } from "@tauri-apps/api/core";

export const isDesktop = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

// Version of the app, set by Vite from package.json
export const appVersion = __APP_VERSION__;

// Engine
export function lambek(method, params = {}) {
  return invoke("lambek", { method, params });
}

// Stops the engine and whatever it runs; it starts again on the next request
export function stopEngine() {
  return invoke("stop");
}

export function engineStatus() {
  if (!isDesktop) return Promise.reject("it only runs in the Lambek window, not in a web browser.");
  return invoke("status");
}

// Opens a file with the default app (the MCP config)
export async function openPath(path) {
  if (!isDesktop) return;
  const { openPath: open } = await import("@tauri-apps/plugin-opener");
  await open(path);
}

// Files
const IMAGE_EXTENSIONS = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"];

export function toAttachment(path, folder = false) {
  const name = path.replace(/[\\/]+$/, "").split(/[\\/]/).pop();
  const extension = !folder && name.includes(".") ? name.split(".").pop().toLowerCase() : "";
  const isImage = IMAGE_EXTENSIONS.includes(extension);
  return { path, name, extension, isImage, isFolder: folder, preview: isImage && isDesktop ? convertFileSrc(path) : null };
}

const DOCUMENTS = ["pdf", "doc", "docx", "odt", "rtf", "txt", "md", "xls", "xlsx", "ods", "csv", "ppt", "pptx", "odp"];

// Files and photos, documents only, or one folder
export async function pickFiles(kind = "files") {
  if (!isDesktop) return [];
  const { open } = await import("@tauri-apps/plugin-dialog");
  const options =
    kind === "folder"
      ? { multiple: false, directory: true }
      : kind === "documents"
        ? { multiple: true, directory: false, filters: [{ name: "Documents", extensions: DOCUMENTS }] }
        : { multiple: true, directory: false };
  const selected = await open(options);
  if (!selected) return [];
  return (Array.isArray(selected) ? selected : [selected]).map((path) => toAttachment(path, kind === "folder"));
}

// Stages the engine reports while it works
export async function onProgress(handler) {
  if (!isDesktop) return () => {};
  const { listen } = await import("@tauri-apps/api/event");
  return listen("lambek-progress", (event) => handler(event.payload));
}

export async function onFileDrop(handler) {
  if (!isDesktop) return () => {};
  const { getCurrentWebview } = await import("@tauri-apps/api/webview");
  return getCurrentWebview().onDragDropEvent((event) => handler(event.payload));
}

// Request text with attached files as quoted paths
export function withAttachments(text, attachments) {
  const paths = attachments.map((file) => `"${file.path}"`).join(" ");
  return [text.trim(), paths].filter(Boolean).join(" ");
}

// Updates: the latest release on GitHub, compared with this version
export const REPOSITORY = "amingharbaoui/lambek";

function isNewer(latest, current) {
  const a = latest.split(/[.-]/).map(Number);
  const b = current.split(/[.-]/).map(Number);
  for (let index = 0; index < 3; index++) {
    const difference = (a[index] || 0) - (b[index] || 0);
    if (difference !== 0) return difference > 0;
  }
  return false;
}

export async function checkForUpdates() {
  const response = await fetch(`https://api.github.com/repos/${REPOSITORY}/releases/latest`, { headers: { Accept: "application/vnd.github+json" } });
  if (response.status === 404) return { state: "none" };
  if (!response.ok) throw new Error(`GitHub answered ${response.status}.`);
  const release = await response.json();
  const latest = String(release.tag_name ?? "").replace(/^v/i, "");
  return { state: isNewer(latest, appVersion) ? "newer" : "current", latest, url: release.html_url };
}

export async function openUrl(url) {
  if (!isDesktop) return window.open(url, "_blank", "noopener");
  const { openUrl: open } = await import("@tauri-apps/plugin-opener");
  await open(url);
}

// Window
async function currentWindow() {
  const { getCurrentWindow } = await import("@tauri-apps/api/window");
  return getCurrentWindow();
}

export async function toggleFullscreen() {
  if (!isDesktop) return;
  const window = await currentWindow();
  await window.setFullscreen(!(await window.isFullscreen()));
}

export async function closeWindow() {
  if (isDesktop) await (await currentWindow()).close();
}
