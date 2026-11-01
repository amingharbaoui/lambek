import { useEffect, useRef, useState } from "react";
import { ChevronDown, Lightbulb, Plug } from "lucide-react";
import { GhostNodes } from "./Icons.jsx";
import ProofLine from "./ProofLine.jsx";
import { Disclaimer } from "./Composer.jsx";
import { language, t } from "../i18n.js";

const plurals = new Intl.PluralRules(language);

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

// Under the name, a sentence read as Lambek reads every sentence: its types written one letter after the other
// until they cancel and leave s, the sentence that holds
const MARK = "n n^r s o^l o";

// New chat: the name, the composer, and one line of menus
export default function Home({ incognito, categories, engineError, onExample, onTools, children }) {
  return (
    <section className="home">
      <div className="home-inner">
        {incognito ? (
          <div className="mark">
            <h1 className="wordmark incognito-mark">
              <GhostNodes size={28} strokeWidth={1.6} className="greeting-icon" />
              <span>{t("You're incognito")}</span>
            </h1>
          </div>
        ) : (
          <div className="mark">
            <h1 className="wordmark">Lambek</h1>
            <div className="mark-proof" aria-hidden="true">
              <ProofLine types={MARK} typing />
            </div>
          </div>
        )}

        {children}

        <div className="home-bar">
          <Menu label={t("Examples")} icon={<Lightbulb size={14} />}>
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
          <Disclaimer />
          <Menu label={t("Connectors")} icon={<Plug size={14} />} align="right">
            {categories.map((category) => (
              <div key={category.pack} className="popover-item" title={category.summary}>
                {category.title}{" "}
                <span className="status-time">
                  {t("{0}, {1}", category.pack.startsWith("mcp-") ? "MCP" : t("Built in"), t(plurals.select(category.actions.length) === "one" ? "{0} action" : "{0} actions", category.actions.length))}
                </span>
              </div>
            ))}
            <button className="popover-item" onClick={onTools}>
              {t("Manage connectors…")}
            </button>
          </Menu>
        </div>

        {engineError && <p className="notice">{t("The engine did not start:")} {engineError}</p>}
      </div>
    </section>
  );
}
