import { useState } from "react";
import { ChevronDown } from "lucide-react";
import { chatMenuItems, chatName, PointMenu } from "./Sidebar.jsx";

// The name of the chat at the top left: a click renames it, the arrow opens its menu
export default function ChatHeading({ chat, onUpdate, onRemove }) {
  const [renaming, setRenaming] = useState(false);
  const [draft, setDraft] = useState("");
  const [menu, setMenu] = useState(null);
  const name = chatName(chat);

  function rename() {
    setDraft(name);
    setRenaming(true);
  }

  function save(value) {
    setRenaming(false);
    if (value && value.trim() && value.trim() !== name) onUpdate(chat.id, { name: value.trim() });
  }

  const items = chatMenuItems(chat, { onUpdate, onRemove, onRename: rename });

  return (
    <header className={`chat-heading ${renaming ? "renaming" : ""}`}>
      {renaming ? (
        // The field grows with the name, so the whole name stays in view
        <span className="chat-heading-edit" data-value={draft}>
          <input
            className="chat-heading-input"
            value={draft}
            autoFocus
            size={1}
            onChange={(event) => setDraft(event.target.value)}
            onFocus={(event) => event.target.select()}
            onKeyDown={(event) => {
              if (event.key === "Enter") save(draft);
              if (event.key === "Escape") setRenaming(false);
            }}
            onBlur={() => save(draft)}
            aria-label="Chat name"
          />
        </span>
      ) : (
        <button className="chat-heading-name" onClick={rename} title="Rename">
          {name}
        </button>
      )}
      <button
        className={`chat-heading-more ${menu ? "open" : ""}`}
        aria-label="Chat menu"
        onClick={(event) => {
          const box = event.currentTarget.getBoundingClientRect();
          setMenu(menu ? null : { x: box.left, y: box.bottom + 6 });
        }}
      >
        <ChevronDown size={14} />
      </button>
      {menu && <PointMenu at={menu} items={items} onClose={() => setMenu(null)} />}
    </header>
  );
}
