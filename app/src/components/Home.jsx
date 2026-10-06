import { useEffect, useRef, useState } from "react";
import { ChevronDown, Lightbulb, Plug } from "lucide-react";
import { GhostNodes } from "./Icons.jsx";
import { load, save } from "../storage.js";


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

// Greetings for each moment of the day, and for a few days of the week
const MOMENTS = {
  morning: ["A fresh start", "Early and ready", "New day, clean slate", "Coffee and a plan", "Morning, clear desk"],
  afternoon: ["Afternoon focus", "Midday momentum", "Back at it", "Halfway there", "Steady afternoon"],
  evening: ["Winding down", "Evening tidy-up", "Last tasks of the day", "Calm evening", "One more thing"],
  night: ["Quiet hours", "Late session", "Still up", "Night shift", "While the house sleeps"],
};
const DAYS = {
  "1-morning": ["New week, new order", "Monday, fresh folders"],
  "5-afternoon": ["Almost the weekend", "Friday clean-up"],
  "6": ["Saturday sort-out", "Weekend mode"],
  "0": ["Slow Sunday", "Sunday reset"],
};

function moment(date) {
  const hour = date.getHours();
  if (hour >= 5 && hour < 12) return "morning";
  if (hour >= 12 && hour < 18) return "afternoon";
  if (hour >= 18 && hour < 23) return "evening";
  return "night";
}

// One greeting for this moment, never the same as the last one shown
function pickGreeting(date) {
  const now = moment(date);
  const day = date.getDay();
  const choices = [...MOMENTS[now], ...(DAYS[`${day}-${now}`] ?? []), ...(now !== "night" ? DAYS[`${day}`] ?? [] : [])];
  const last = load("lambek.greeting", null);
  const fresh = choices.filter((words) => words !== last);
  const words = fresh[Math.floor(Math.random() * fresh.length)];
  save("lambek.greeting", words);
  return { moment: now, words };
}

// A new greeting for each new chat, and again when the moment of the day changes
function useGreeting(name) {
  const [current, setCurrent] = useState(() => pickGreeting(new Date()));

  useEffect(() => {
    const timer = setInterval(() => {
      if (moment(new Date()) !== current.moment) setCurrent(pickGreeting(new Date()));
    }, 60000);
    return () => clearInterval(timer);
  }, [current.moment]);

  return name ? `${current.words}, ${name}` : current.words;
}

// New chat: a greeting, the composer, and one line of menus
export default function Home({ name, incognito, categories, engineError, onExample, onTools, children }) {
  const greeting = useGreeting(name);

  return (
    <section className="home">
      <div className="home-inner">
        <h1 className="greeting">
          {incognito && <GhostNodes size={32} strokeWidth={1.6} className="greeting-icon" />}
          {incognito ? "You're incognito" : greeting}
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
