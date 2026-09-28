import { useEffect, useRef, useState } from "react";
import { ChevronDown, Lightbulb, Plug } from "lucide-react";
import { GhostNodes } from "./Icons.jsx";


// A small button with a list that closes on a click outside or Escape
function Menu({ label, icon, align, children }) {
  const [open, setOpen] = useState(false);
  const box = useRef(null);

  useEffect(() => {
    if (!open) return;
    const close = (event) => {
      if (event.type === "keydown" ? event.key === "Escape" : !box.current?.contains(event.target)) setOpen(false);
    };
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("keydown", close);
    };
  }, [open]);

  return (
    <div className="menu" ref={box}>
      <button className="menu-button" onClick={() => setOpen(!open)} aria-expanded={open}>
        {icon}
        {label}
        <ChevronDown size={13} />
      </button>
      {open && (
        <div className={`popover ${align === "right" ? "right" : ""}`} onClick={() => setOpen(false)}>
          {children}
        </div>
      )}
    </div>
  );
}

// A greeting that follows the user's own clock: a few human words for the moment of the day
function greeting(name) {
  const hour = new Date().getHours();
  const words = hour >= 5 && hour < 12 ? "A fresh start" : hour >= 12 && hour < 18 ? "Afternoon focus" : hour >= 18 && hour < 23 ? "Winding down" : "Quiet hours";
  return name ? `${words}, ${name}` : words;
}

// New chat: a greeting, the composer, and one line of menus
export default function Home({ name, incognito, categories, engineError, onExample, onTools, children }) {
  return (
    <section className="home">
      <div className="home-inner">
        <h1 className="greeting">
          {incognito && <GhostNodes size={32} strokeWidth={1.6} className="greeting-icon" />}
          {incognito ? "You're incognito" : greeting(name)}
        </h1>

        {children}

        <div className="home-bar">
          <Menu label="Examples" icon={<Lightbulb size={14} />}>
            {categories.map((category) => (
              <div key={category.pack}>
                <div className="popover-group">{category.title}</div>
                {category.examples.slice(0, 3).map((example) => (
                  <button key={example} className="popover-item" onClick={() => onExample(example)}>
                    {example}
                  </button>
                ))}
              </div>
            ))}
          </Menu>
          <span className="spacer" />
          <Menu label="Connectors" icon={<Plug size={14} />} align="right">
            {categories.map((category) => (
              <div key={category.pack} className="popover-item" title={category.summary}>
                {category.title}{" "}
                <span className="status-time">
                  · {category.pack.startsWith("mcp-") ? "MCP" : "built in"} · {category.actions.length} action{category.actions.length === 1 ? "" : "s"}
                </span>
              </div>
            ))}
            <button className="popover-item" onClick={onTools}>
              Manage connectors…
            </button>
          </Menu>
        </div>

        {incognito && <p className="home-note">This chat stays out of your history. Runs are still written to the audit log.</p>}
        {engineError && <p className="notice">The engine did not start: {engineError}</p>}
      </div>
    </section>
  );
}
