import { useEffect, useState } from "react";
import { load, save } from "./storage.js";

const KEY = "lambek.chats.v1";

function newId() {
  return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
}

// Work that was running when the app closed is shown as stopped
function settle(chat) {
  return { ...chat, messages: chat.messages.map((message) => (message.busy ? { ...message, busy: null, error: "Stopped when the app closed." } : message)) };
}

function titleFrom(text) {
  return text.replace(/\s+/g, " ").trim();
}

// Saved chats, plus one incognito list that lives in memory only
export default function useChats(incognito) {
  const [saved, setSaved] = useState(() => load(KEY, []).map(settle));
  const [hidden, setHidden] = useState([]);
  const [currentId, setCurrentId] = useState(null);

  useEffect(() => {
    save(KEY, saved);
  }, [saved]);

  // Leaving incognito forgets its chats
  useEffect(() => {
    setCurrentId(null);
    if (!incognito) setHidden([]);
  }, [incognito]);

  const chats = incognito ? hidden : saved;
  const setChats = incognito ? setHidden : setSaved;
  const current = chats.find((chat) => chat.id === currentId) ?? null;

  // A chat is created by its first request and named after it
  function addMessage(message, chatId = currentId) {
    const id = newId();
    const entry = { ...message, id, at: Date.now() };

    if (!chatId) {
      const first = message.text || message.attachments?.map((file) => file.name).join(", ") || "New chat";
      const chat = { id: newId(), title: titleFrom(first), createdAt: Date.now(), updatedAt: Date.now(), messages: [entry] };
      setChats((all) => [chat, ...all]);
      setCurrentId(chat.id);
      return { chatId: chat.id, messageId: id };
    }

    setChats((all) =>
      all.map((chat) => (chat.id === chatId ? { ...chat, updatedAt: Date.now(), messages: [...chat.messages, entry] } : chat)),
    );
    return { chatId, messageId: id };
  }

  function updateMessage(chatId, messageId, patch) {
    setChats((all) =>
      all.map((chat) =>
        chat.id === chatId
          ? {
              ...chat,
              messages: chat.messages.map((message) =>
                message.id === messageId ? { ...message, ...(typeof patch === "function" ? patch(message) : patch) } : message,
              ),
            }
          : chat,
      ),
    );
  }

  function updateChat(chatId, patch) {
    setChats((all) => all.map((chat) => (chat.id === chatId ? { ...chat, ...patch } : chat)));
  }

  // An edited request replaces itself and everything after it
  function truncateFrom(chatId, messageId) {
    setChats((all) =>
      all.map((chat) => {
        if (chat.id !== chatId) return chat;
        const index = chat.messages.findIndex((message) => message.id === messageId);
        if (index < 0) return chat;
        return { ...chat, messages: chat.messages.slice(0, index), compactedUpTo: Math.min(chat.compactedUpTo ?? 0, index) };
      }),
    );
  }

  function removeChat(chatId) {
    setChats((all) => all.filter((chat) => chat.id !== chatId));
    if (chatId === currentId) setCurrentId(null);
  }

  return {
    chats,
    current,
    currentId,
    open: setCurrentId,
    addMessage,
    updateMessage,
    updateChat,
    truncateFrom,
    removeChat,
  };
}
