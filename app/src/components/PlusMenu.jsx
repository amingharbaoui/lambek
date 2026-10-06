import { useEffect, useRef, useState } from "react";
import { ChevronRight, FolderPlus, Paperclip, Plug, Plus, Settings2 } from "lucide-react";
import { isDesktop, lambek, openPath, pickFiles } from "../lambek.js";
import { keys } from "../platform.js";

const STATUS = { Connected: "on", Ready: "ready", Failed: "failed", Disabled: "off" };

// The + of the composer: files, a folder, and the connectors (MCP servers)
export default function PlusMenu({ onAttach, onInsert, onTools }) {
  const [open, setOpen] = useState(false);
  const [servers, setServers] = useState([]);
  const [sub, setSub] = useState(false);
  const [room, setRoom] = useState({ height: 420, down: false });
  const box = useRef(null);
  const entry = useRef(null);

  // The list of connectors opens where there is more room, never past the title bar; it scrolls when long
  useEffect(() => {
    if (!sub || !entry.current) return;
    const box = entry.current.getBoundingClientRect();
    const above = box.bottom - 52;
    const below = window.innerHeight - box.top - 12;
    setRoom(below > above ? { height: below, down: true } : { height: above, down: false });
  }, [sub]);

  useEffect(() => {
    if (!open) return;
    const close = (event) => {
      if (event.type === "keydown" ? event.key === "Escape" : !box.current?.contains(event.target)) {
        setOpen(false);
        setSub(false);
      }
    };
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("keydown", close);
    };
  }, [open]);

  // The connectors are read when the menu opens, so the list is never stale
  useEffect(() => {
    if (!open) return;
    lambek("mcp")
      .then((data) => setServers(data.servers))
      .catch(() => setServers([]));
  }, [open]);


  function close() {
    setOpen(false);
    setSub(false);
  }

  async function add(kind) {
    close();
    const files = await pickFiles(kind);
    if (files.length > 0) onAttach(files);
  }

  async function addServer() {
    close();
    const result = await lambek("mcp", { create: true });
    await openPath(result.config);
    onTools();
  }

  return (
    <div className="plus-menu" ref={box}>
      <button className="icon-button" onClick={() => setOpen(!open)} aria-label="Add" aria-expanded={open} aria-haspopup="menu" data-tip={open ? undefined : "Add"}>
        <Plus size={16} />
      </button>

      {open && (
        <div className="menu-list up" role="menu">
          <button className="menu-row" role="menuitem" disabled={!isDesktop} onClick={() => add("files")} onMouseEnter={() => setSub(false)}>
            <Paperclip size={15} />
            <span>Add files or photos</span>
            <kbd>{keys("Ctrl+O")}</kbd>
          </button>
          <button className="menu-row" role="menuitem" disabled={!isDesktop} onClick={() => add("folder")} onMouseEnter={() => setSub(false)}>
            <FolderPlus size={15} />
            <span>Add folder</span>
          </button>
          <hr />
          <div className="menu-entry" ref={entry} onMouseEnter={() => setSub(true)}>
            <button className={`menu-row ${sub ? "hover" : ""}`} role="menuitem" aria-haspopup="menu" aria-expanded={sub} onClick={() => setSub(!sub)}>
              <Plug size={15} />
              <span>Connectors</span>
              <ChevronRight size={14} />
            </button>

            {sub && (
              <div className={`menu-list sub ${room.down ? "down" : "up"}`} role="menu" style={{ maxHeight: room.height }}>
                {servers.length === 0 && <p className="menu-note">No connectors yet</p>}
                {servers.map((server) => (
                  <p key={server.name} className="menu-connector" title={server.error || server.status}>
                    <i className={`server-dot ${STATUS[server.status] ?? "off"}`} />
                    <span>{server.name}</span>
                    <small>
                      {server.tools.length} tool{server.tools.length === 1 ? "" : "s"}
                    </small>
                  </p>
                ))}
                <hr />
                <button className="menu-row" role="menuitem" disabled={!isDesktop} onClick={addServer}>
                  <Plus size={15} />
                  <span>Add a connector…</span>
                </button>
                <button
                  className="menu-row"
                  role="menuitem"
                  onClick={() => {
                    close();
                    onTools();
                  }}
                >
                  <Settings2 size={15} />
                  <span>Manage connectors</span>
                </button>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
