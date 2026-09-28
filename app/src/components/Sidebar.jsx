import { useEffect, useMemo, useRef, useState } from "react";
import { Check, ChevronDown, Ellipsis, Info, Keyboard, Pencil, Pin, PinOff, Plug, Plus, RefreshCw, Search, Trash2 } from "lucide-react";

const DAY = 86400000;
const SHOWN = 20;

export function chatName(chat) {
  return chat.name ?? chat.summary ?? chat.title;
}

function groupOf(chat) {
  if (chat.pinned) return "Pinned";
  const today = new Date().setHours(0, 0, 0, 0);
  if (chat.updatedAt >= today) return "Today";
  if (chat.updatedAt >= today - DAY) return "Yesterday";
  if (chat.updatedAt >= today - 6 * DAY) return new Date(chat.updatedAt).toLocaleDateString("en-US", { month: "short", day: "numeric" });
  return "Older";
}

function plural(count, word) {
  return `${count} ${word}${count === 1 ? "" : "s"}`;
}

function ago(time) {
  const minutes = Math.floor((Date.now() - time) / 60000);
  if (minutes < 1) return "Just now";
  if (minutes < 60) return `${minutes}m ago`;
  if (minutes < 1440) return `${Math.floor(minutes / 60)}h ago`;
  return new Date(time).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

// A small list at a point, closed by a click outside or Escape; letters run their item
export function PointMenu({ at, items, onClose }) {
  const box = useRef(null);

  useEffect(() => {
    const close = (event) => {
      if (event.type === "keydown") {
        const item = items.find((entry) => entry.key && entry.key.toLowerCase() === event.key.toLowerCase());
        if (item) {
          event.preventDefault();
          onClose();
          item.onSelect();
        } else if (event.key === "Escape") onClose();
      } else if (!box.current?.contains(event.target)) onClose();
    };
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("keydown", close);
    };
  }, [items, onClose]);

  return (
    <div className="menu-list point" role="menu" ref={box} style={{ left: at.x, top: at.y }}>
      {items.map((item) =>
        item.separator ? (
          <hr key={item.separator} />
        ) : (
          <button
            key={item.label}
            className={`menu-row ${item.danger ? "danger" : ""}`}
            role="menuitem"
            onClick={() => {
              onClose();
              item.onSelect();
            }}
          >
            {item.icon}
            <span>{item.label}</span>
            {item.key && <kbd>{item.key}</kbd>}
          </button>
        ),
      )}
    </div>
  );
}

function ChatItem({ chat, active, onOpen, onMenu, renaming, onRename }) {
  const [card, setCard] = useState(null);
  const timer = useRef(null);
  const row = useRef(null);
  const name = chatName(chat);

  // A card with the name and the date after a short hover
  function hover(on) {
    clearTimeout(timer.current);
    if (!on) return setCard(null);
    timer.current = setTimeout(() => {
      const box = row.current?.getBoundingClientRect();
      if (box) setCard({ x: box.right + 10, y: box.top });
    }, 700);
  }
  useEffect(() => () => clearTimeout(timer.current), []);

  if (renaming) {
    return (
      <input
        className="chat-rename"
        defaultValue={name}
        autoFocus
        onFocus={(event) => event.target.select()}
        onKeyDown={(event) => {
          if (event.key === "Enter") onRename(event.target.value);
          if (event.key === "Escape") onRename(null);
        }}
        onBlur={(event) => onRename(event.target.value)}
        aria-label="Chat name"
      />
    );
  }

  return (
    <div
      ref={row}
      role="button"
      tabIndex={0}
      className={`chat-item ${active ? "active" : ""}`}
      onClick={() => {
        hover(false);
        onOpen(chat.id);
      }}
      onKeyDown={(event) => event.key === "Enter" && onOpen(chat.id)}
      onContextMenu={(event) => {
        event.preventDefault();
        hover(false);
        onMenu(chat, { x: event.clientX, y: event.clientY });
      }}
      onMouseEnter={() => hover(true)}
      onMouseLeave={() => hover(false)}
    >
      <span className="chat-title">{name}</span>
      <button
        className="chat-more"
        aria-label={`More for ${name}`}
        onClick={(event) => {
          event.stopPropagation();
          hover(false);
          const box = event.currentTarget.getBoundingClientRect();
          onMenu(chat, { x: box.left, y: box.bottom + 4 });
        }}
      >
        <Ellipsis size={15} />
      </button>
      {card && (
        <div className="chat-card" style={{ left: card.x, top: card.y }}>
          <b>{name}</b>
          <span>{ago(chat.updatedAt)}</span>
          <span>{plural(chat.messages.filter((message) => message.role === "user").length, "message")}</span>
        </div>
      )}
    </div>
  );
}

// Search, actions, chats by day, and the account. The chat sits above it like a sheet of paper.
export default function Sidebar({ onEnter, onLeave, onNew, onTools, toolsActive, chats, currentId, onOpen, onRemove, onUpdate, searchRef, account }) {
  const [filter, setFilter] = useState("");
  const [closed, setClosed] = useState([]);
  const [all, setAll] = useState(false);
  const [menu, setMenu] = useState(null);
  const [renaming, setRenaming] = useState(null);
  const [accountOpen, setAccountOpen] = useState(false);
  const accountBox = useRef(null);

  const shown = useMemo(
    () => chats.filter((chat) => chatName(chat).toLowerCase().includes(filter.toLowerCase())).sort((a, b) => Number(Boolean(b.pinned)) - Number(Boolean(a.pinned)) || b.updatedAt - a.updatedAt),
    [chats, filter],
  );

  const groups = useMemo(() => {
    const result = [];
    for (const chat of all || filter ? shown : shown.slice(0, SHOWN)) {
      const name = groupOf(chat);
      if (result.at(-1)?.name !== name) result.push({ name, chats: [] });
      result.at(-1).chats.push(chat);
    }
    return result;
  }, [shown, all, filter]);

  useEffect(() => {
    if (!accountOpen) return;
    const close = (event) => {
      if (event.type === "keydown" ? event.key === "Escape" : !accountBox.current?.contains(event.target)) setAccountOpen(false);
    };
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("keydown", close);
    };
  }, [accountOpen]);

  const menuItems = menu
    ? [
        {
          label: menu.chat.pinned ? "Unpin" : "Pin",
          key: "P",
          icon: menu.chat.pinned ? <PinOff size={15} /> : <Pin size={15} />,
          onSelect: () => onUpdate(menu.chat.id, { pinned: !menu.chat.pinned }),
        },
        { label: "Rename", key: "R", icon: <Pencil size={15} />, onSelect: () => setRenaming(menu.chat.id) },
        { separator: "delete" },
        { label: "Delete", key: "D", icon: <Trash2 size={15} />, danger: true, onSelect: () => onRemove(menu.chat.id) },
      ]
    : [];

  const initial = (account.name || "?").charAt(0).toUpperCase();

  return (
    <aside className="sidebar" aria-label="Sidebar" onMouseEnter={onEnter} onMouseLeave={() => !menu && !accountOpen && onLeave()}>
      <div className="sidebar-inner">
        <label className="nav-search">
          <Search size={15} />
          <input ref={searchRef} value={filter} onChange={(event) => setFilter(event.target.value)} placeholder="Search" aria-label="Search chats" />
        </label>

        <nav className="sidebar-nav">
          <button className="nav-item" onClick={onNew}>
            <Plus size={17} /> New chat
          </button>
          <button className={`nav-item ${toolsActive ? "active" : ""}`} onClick={onTools}>
            <Plug size={16} /> Connectors
          </button>
        </nav>

        <div className="chat-list">
          {groups.map((group) => {
            const isClosed = closed.includes(group.name);
            return (
              <section key={group.name}>
                <button
                  className="chat-group"
                  onClick={() => setClosed((names) => (isClosed ? names.filter((name) => name !== group.name) : [...names, group.name]))}
                  aria-expanded={!isClosed}
                >
                  {group.name} <ChevronDown size={12} className={isClosed ? "turned" : ""} />
                </button>
                {!isClosed &&
                  group.chats.map((chat) => (
                    <ChatItem
                      key={chat.id}
                      chat={chat}
                      active={chat.id === currentId}
                      onOpen={onOpen}
                      onMenu={(item, at) => setMenu({ chat: item, at })}
                      renaming={renaming === chat.id}
                      onRename={(value) => {
                        setRenaming(null);
                        if (value && value.trim()) onUpdate(chat.id, { name: value.trim() });
                      }}
                    />
                  ))}
              </section>
            );
          })}
          {!all && !filter && shown.length > SHOWN && (
            <button className="chat-group view-all" onClick={() => setAll(true)}>
              View all
            </button>
          )}
        </div>

        <div className="sidebar-foot" ref={accountBox}>
          {accountOpen && (
            <div className="menu-list account-menu" role="menu">
              {["system", "light", "dark"].map((value) => (
                <button key={value} className="menu-row" role="menuitemradio" aria-checked={account.theme === value} onClick={() => account.onTheme(value)}>
                  <span className="menu-check">{account.theme === value && <Check size={13} />}</span>
                  <span>{`${value[0].toUpperCase()}${value.slice(1)} theme`}</span>
                </button>
              ))}
              <hr />
              <button className="menu-row" role="menuitem" onClick={() => (setAccountOpen(false), account.onShortcuts())}>
                <Keyboard size={15} />
                <span>Keyboard shortcuts</span>
              </button>
              <button className="menu-row" role="menuitem" onClick={() => (setAccountOpen(false), account.onUpdates())}>
                <RefreshCw size={15} />
                <span>Check for updates…</span>
              </button>
              <button className="menu-row" role="menuitem" onClick={() => (setAccountOpen(false), account.onAbout())}>
                <Info size={15} />
                <span>About Lambek</span>
              </button>
            </div>
          )}
          <button className="account" onClick={() => setAccountOpen(!accountOpen)} aria-expanded={accountOpen}>
            <span className="avatar">{initial}</span>
            <span className="account-name">{account.name || "You"}</span>
            <ChevronDown size={14} />
          </button>
        </div>
      </div>

      {menu && (
        <PointMenu
          at={menu.at}
          items={menuItems}
          onClose={() => {
            setMenu(null);
          }}
        />
      )}
    </aside>
  );
}
