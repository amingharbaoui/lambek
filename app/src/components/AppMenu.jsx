import { useEffect, useRef, useState } from "react";
import { Check, ChevronRight, Menu as MenuIcon } from "lucide-react";
import { keys } from "../platform.js";

// The application menu: File, View, and Help, each with its own list
export default function AppMenu({ sections }) {
  const [open, setOpen] = useState(false);
  const [section, setSection] = useState(null);
  const box = useRef(null);

  useEffect(() => {
    if (!open) return;
    const close = (event) => {
      if (event.type === "keydown" ? event.key === "Escape" : !box.current?.contains(event.target)) {
        setOpen(false);
        setSection(null);
      }
    };
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("keydown", close);
    };
  }, [open]);

  function run(item) {
    setOpen(false);
    setSection(null);
    item.onSelect();
  }

  return (
    // Clicks in the menu keep the focus where it was, so Copy and Paste reach the text field
    <div className="app-menu" ref={box} onMouseDown={(event) => event.preventDefault()}>
      <button className="icon-button" onClick={() => setOpen(!open)} aria-label="Menu" aria-expanded={open}>
        <MenuIcon size={18} />
      </button>
      {open && (
        <div className="menu-list" role="menu">
          {sections.map((entry) => (
            <div key={entry.label} className="menu-entry" onMouseEnter={() => setSection(entry.label)}>
              <button className={`menu-row ${section === entry.label ? "hover" : ""}`} onClick={() => setSection(entry.label)}>
                <span>{entry.label}</span>
                <ChevronRight size={14} />
              </button>
              {section === entry.label && (
                <div className="menu-list sub" role="menu">
                  {entry.items.map((item) =>
                    item.separator ? (
                      <hr key={item.separator} />
                    ) : (
                      <button key={item.label} className="menu-row" role="menuitem" disabled={item.disabled} onClick={() => run(item)}>
                        <span className="menu-check">{item.checked && <Check size={13} />}</span>
                        <span>{item.label}</span>
                        {item.keys && <kbd>{keys(item.keys)}</kbd>}
                      </button>
                    ),
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
