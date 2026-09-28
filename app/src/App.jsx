import { Fragment, lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ArrowLeft, ArrowRight, PanelLeft, Upload, X } from "lucide-react";
import { ReductionMark } from "./components/Status.jsx";
import { GhostNodes } from "./components/Icons.jsx";
import AppMenu from "./components/AppMenu.jsx";
import WindowControls from "./components/WindowControls.jsx";
import Dialog from "./components/Dialog.jsx";
import { appVersion, checkForUpdates, closeWindow, engineStatus, lambek, onFileDrop, onProgress, openUrl, pickFiles, REPOSITORY, stopEngine, toAttachment, toggleFullscreen, withAttachments } from "./lambek.js";
import useTheme from "./useTheme.js";
import { keys as keyLabel, platform, PLATFORM_NAMES } from "./platform.js";
import useChats from "./useChats.js";
import { load, save } from "./storage.js";
import Sidebar from "./components/Sidebar.jsx";
import ChatHeading from "./components/ChatHeading.jsx";
import Home from "./components/Home.jsx";
import Composer from "./components/Composer.jsx";
import Tools from "./components/Tools.jsx";
import { Answer, Request } from "./components/Message.jsx";

const loadGraph = () => import("./components/Graph3D.jsx");
const Graph3D = lazy(loadGraph);

const SHORTCUTS = [
  ["Enter", "Send"],
  ["Shift+Enter", "New line"],
  ["Esc", "Stop, or back to the chat"],
  ["Ctrl+N", "New chat"],
  ["Ctrl+Shift+N", "Incognito"],
  ["Ctrl+O", "Add files"],
  ["Ctrl+B", "Sidebar"],
  ["Ctrl+K", "Search chats"],
  ["Ctrl+Tab", "Next chat"],
  [platform === "mac" ? "Ctrl+[ / Ctrl+]" : "Alt+Left / Alt+Right", "Back, forward"],
  ["Ctrl+G", "Nodes"],
  ["Ctrl+= / Ctrl+-", "Zoom in, zoom out"],
  [platform === "mac" ? "Control+Ctrl+F" : "F11", "Full screen"],
];

const ZOOMS = [0.8, 0.9, 1, 1.1, 1.25, 1.5];
const BACK_KEYS = keyLabel(platform === "mac" ? "Ctrl+[" : "Alt+Left");
const FORWARD_KEYS = keyLabel(platform === "mac" ? "Ctrl+]" : "Alt+Right");


// Results keep at most this many rows; a chat above these sizes is compacted
const KEPT_ROWS = 500;
const LONG_CHAT_BYTES = 1500000;
const LONG_CHAT_MESSAGES = 80;
const RECENT_MESSAGES = 20;

function keepRows(execution) {
  return {
    ...execution,
    steps: execution.steps.map((step) =>
      Array.isArray(step.output) && step.output.length > KEPT_ROWS ? { ...step, output: step.output.slice(0, KEPT_ROWS), total: step.output.length } : step,
    ),
  };
}

// An old answer keeps its text, but not its rows, files, and details
function shrink(message) {
  const patch = { compacted: true, events: [] };
  if (message.execution) {
    patch.execution = {
      ...message.execution,
      steps: message.execution.steps.map((step) =>
        Array.isArray(step.output) ? { ...step, output: step.output.slice(0, 20), total: step.total ?? step.output.length } : step,
      ),
    };
  }
  if (message.simulation) patch.simulation = { ...message.simulation, steps: message.simulation.steps.map((step) => ({ ...step, affected: step.affected.slice(0, 20) })) };
  if (message.plan?.trace) patch.plan = { ...message.plan, trace: [] };
  return patch;
}

// Undo, copy, paste... on the text field that has the focus
function editCommand(command) {
  if (command === "paste") {
    navigator.clipboard
      ?.readText()
      .then((text) => document.execCommand("insertText", false, text))
      .catch(() => {});
    return;
  }
  document.execCommand(command);
}

// The name of a chat, from what its first plan does; the whole text, the screen cuts it where it must
function summarize(plan) {
  const sentences = plan.sentences ?? [];
  if (sentences.length === 0) return plan.steps?.find((step) => step.title)?.title ?? "New chat";
  const text = sentences[0].replace(/\s+/g, " ").trim();
  const first = text.charAt(0).toUpperCase() + text.slice(1);
  return sentences.length > 1 ? `${first} + ${sentences.length - 1} more` : first;
}

// An answer whose plan gave the chat its name
function namesChat(message) {
  return message.plan?.status === "Ready" && message.plan.steps?.some((step) => step.action);
}

// What the status under a message says for each stage the engine reports
const STAGE_WORDS = {
  Split: () => "Reading your request",
  Read: (step) => `Reading step ${step}`,
  Match: (step) => `Matching step ${step} to an action`,
  Check: (step) => `Checking step ${step}`,
  Order: () => "Ordering the steps",
  Simulate: (step) => `Simulating step ${step}`,
  Run: (step) => `Running step ${step}`,
};

function simulationDetail(simulation) {
  const count = simulation.steps.reduce((sum, step) => sum + step.count, 0);
  return `${simulation.status.toLowerCase()}, ${count} item(s)${simulation.confirmationCode ? `, code ${simulation.confirmationCode}` : ""}`;
}

export default function App() {
  const [incognito, setIncognito] = useState(false);
  const theme = useTheme(incognito);
  const chats = useChats(incognito);
  const [sidebarOpen, setSidebarOpen] = useState(() => load("lambek.sidebar", true));
  const [view, setView] = useState("chat");
  const [engine, setEngine] = useState(null);
  const [categories, setCategories] = useState([]);
  const [draft, setDraft] = useState("");
  const [focusToken, setFocusToken] = useState(0);
  const [attachments, setAttachments] = useState([]);
  const [dragging, setDragging] = useState(false);
  const [selectedStep, setSelectedStep] = useState(null);
  const [graphMessageId, setGraphMessageId] = useState(null);
  const [peek, setPeek] = useState(false);
  const [dialog, setDialog] = useState(null);
  const [update, setUpdate] = useState(null);
  const [zoom, setZoom] = useState(() => load("lambek.zoom", 1));
  const history = useRef({ stack: [{ chatId: null, view: "chat" }], index: 0 });
  const [canGo, setCanGo] = useState({ back: false, forward: false });
  const bottom = useRef(null);
  const conversation = useRef(null);
  const atBottom = useRef(true);
  const lastTop = useRef(0);
  const [following, setFollowing] = useState(true);
  const search = useRef(null);
  const peekTimer = useRef(null);
  const running = useRef(null);
  const stopped = useRef(new Set());
  const latestSetProgress = useRef(null);

  const messages = chats.current?.messages ?? [];
  const busyMessage = messages.find((message) => message.busy);
  const busy = Boolean(busyMessage);
  const lastPlanMessage = useMemo(() => [...messages].reverse().find((message) => message.plan?.steps.some((step) => step.action)), [messages]);
  const graphMessage = messages.find((message) => message.id === graphMessageId && message.plan) ?? lastPlanMessage;
  const lastAnswer = [...messages].reverse().find((message) => message.role === "lambek" && !message.busy);
  const focus = selectedStep && graphMessage ? graphMessage.plan.steps.find((step) => step.step === selectedStep) : null;

  // Engine, then what it can do
  const loadCategories = useCallback(() => {
    lambek("categories", { language: "en" })
      .then(setCategories)
      .catch(() => setCategories([]));
  }, []);

  useEffect(() => {
    engineStatus()
      .then((ready) => {
        setEngine({ ok: true, version: ready.version, user: ready.user, error: ready.mcpError });
        loadCategories();
      })
      .catch((error) => setEngine({ ok: false, error: String(error) }));

    // The 3D view is loaded while the app is idle, so it opens at once
    const idle = window.requestIdleCallback ?? ((callback) => setTimeout(callback, 1597));
    idle(() => loadGraph());
  }, [loadCategories]);

  // Live stages from the engine
  useEffect(() => {
    let stopListening = () => {};
    onProgress((event) => {
      const current = running.current;
      const word = STAGE_WORDS[event.stage];
      if (current && word) latestSetProgress.current(current.chatId, current.messageId, word(event.step), event.percent, event.types ? { [event.step]: event.types } : null);
    }).then((unlisten) => (stopListening = unlisten));
    return () => stopListening();
  }, []);

  // Files dropped on the window
  useEffect(() => {
    let stop = () => {};
    onFileDrop((payload) => {
      if (payload.type === "enter" || payload.type === "over") setDragging(true);
      if (payload.type === "leave") setDragging(false);
      if (payload.type === "drop") {
        setDragging(false);
        addAttachments(payload.paths.map((path) => toAttachment(path)));
      }
    }).then((unlisten) => (stop = unlisten));
    return () => stop();
  }, []);

  useEffect(() => {
    save("lambek.sidebar", sidebarOpen);
  }, [sidebarOpen]);

  useEffect(() => {
    document.documentElement.style.zoom = String(zoom);
    save("lambek.zoom", zoom);
  }, [zoom]);

  // A selected node only matters while the nodes are shown
  useEffect(() => {
    if (view !== "graph") setSelectedStep(null);
  }, [view]);

  // The newest message and its status stay in view, unless the user reads higher up
  const lastBusy = Boolean(messages.at(-1)?.busy);
  const busyStage = `${busyMessage?.busy.word ?? ""}${Object.keys(busyMessage?.busy.types ?? {}).length}`;
  const shownChat = useRef(null);
  useEffect(() => {
    if (view !== "chat") return;
    const opened = shownChat.current !== chats.currentId;
    shownChat.current = chats.currentId;
    if (opened) {
      atBottom.current = true;
      setFollowing(true);
    }
    if (atBottom.current) bottom.current?.scrollIntoView({ behavior: opened ? "auto" : "smooth", block: "end" });
  }, [messages.length, lastBusy, busyStage, chats.currentId, view]);

  // Scrolling up leaves the bottom; coming back near it follows again
  function followScroll() {
    const box = conversation.current;
    if (!box) return;
    const near = box.scrollHeight - box.scrollTop - box.clientHeight < 80;
    if (near) atBottom.current = true;
    else if (box.scrollTop < lastTop.current - 2) atBottom.current = false;
    lastTop.current = box.scrollTop;
    setFollowing(atBottom.current);
  }

  function toBottom() {
    atBottom.current = true;
    setFollowing(true);
    bottom.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }

  // Back and forward: every chat or view the user opens is a step
  useEffect(() => {
    const record = history.current;
    const here = record.stack[record.index];
    // Nothing new, or a step back or forward that already moved the index
    if (here.chatId === chats.currentId && here.view === view) return;
    record.stack = [...record.stack.slice(0, record.index + 1), { chatId: chats.currentId, view }].slice(-50);
    record.index = record.stack.length - 1;
    setCanGo({ back: record.index > 0, forward: false });
  }, [chats.currentId, view]);

  // Incognito has its own chats, so it starts its own history
  useEffect(() => {
    history.current = { stack: [{ chatId: null, view: "chat" }], index: 0 };
    setCanGo({ back: false, forward: false });
  }, [incognito]);

  function go(step) {
    const record = history.current;
    const exists = (place) => !place.chatId || chats.chats.some((chat) => chat.id === place.chatId);
    let target = record.index + step;
    while (target >= 0 && target < record.stack.length && !exists(record.stack[target])) target += step;
    if (target < 0 || target >= record.stack.length) return;

    const place = record.stack[target];
    record.index = target;
    chats.open(place.chatId);
    setView(place.view);
    setSelectedStep(null);
    setCanGo({ back: target > 0, forward: target < record.stack.length - 1 });
  }

  // Keyboard shortcuts
  useEffect(() => {
    function onKey(event) {
      const mod = event.ctrlKey || event.metaKey;
      const key = event.key.toLowerCase();
      const back = platform === "mac" ? event.metaKey && key === "[" : event.altKey && key === "arrowleft";
      const forward = platform === "mac" ? event.metaKey && key === "]" : event.altKey && key === "arrowright";
      if (back || forward) {
        event.preventDefault();
        go(back ? -1 : 1);
      } else if (mod && event.shiftKey && key === "n") {
        event.preventDefault();
        toggleIncognito();
      } else if (mod && key === "n") {
        event.preventDefault();
        newChat();
      } else if (mod && key === "b") {
        event.preventDefault();
        setSidebarOpen((open) => !open);
      } else if (mod && key === "k") {
        event.preventDefault();
        setSidebarOpen(true);
        setTimeout(() => search.current?.focus(), 0);
      } else if (mod && key === "g" && lastPlanMessage) {
        event.preventDefault();
        setView((current) => (current === "graph" ? "chat" : "graph"));
      } else if (mod && key === "o") {
        event.preventDefault();
        addFiles();
      } else if (mod && key === "tab") {
        event.preventDefault();
        goChat(event.shiftKey ? -1 : 1);
      } else if (mod && (key === "=" || key === "+")) {
        event.preventDefault();
        zoomBy(1);
      } else if (mod && key === "-") {
        event.preventDefault();
        zoomBy(-1);
      } else if (mod && key === "0") {
        event.preventDefault();
        setZoom(1);
      } else if (key === "f11" || (platform === "mac" && event.metaKey && event.ctrlKey && key === "f")) {
        event.preventDefault();
        toggleFullscreen().catch(() => {});
      } else if (mod && key === "q" && platform !== "windows") {
        event.preventDefault();
        closeWindow();
      } else if (key === "escape" && running.current) {
        stop();
      } else if (key === "escape" && view !== "chat") {
        setView("chat");
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  function zoomBy(direction) {
    setZoom((current) => {
      const index = ZOOMS.indexOf(current);
      return ZOOMS[Math.min(ZOOMS.length - 1, Math.max(0, (index < 0 ? 2 : index) + direction))];
    });
  }

  async function addFiles() {
    addAttachments(await pickFiles());
    setFocusToken((token) => token + 1);
  }

  // Previous and next chat, in the order of the sidebar
  function goChat(direction) {
    const order = [...chats.chats].sort((a, b) => Number(Boolean(b.pinned)) - Number(Boolean(a.pinned)) || b.updatedAt - a.updatedAt);
    if (order.length === 0) return;
    const index = order.findIndex((chat) => chat.id === chats.currentId);
    const next = order[(index + direction + order.length) % order.length];
    chats.open(next.id);
    setView("chat");
  }

  async function findUpdates() {
    setUpdate({ state: "checking" });
    try {
      setUpdate(await checkForUpdates());
    } catch (error) {
      setUpdate({ state: "error", message: String(error.message ?? error) });
    }
  }

  function addAttachments(files) {
    setAttachments((current) => [...current, ...files.filter((file) => !current.some((item) => item.path === file.path))]);
  }

  function newChat() {
    chats.open(null);
    setView("chat");
    setSelectedStep(null);
    setGraphMessageId(null);
    setFocusToken((token) => token + 1);
  }

  function toggleIncognito() {
    setIncognito((value) => !value);
    setView("chat");
    setSelectedStep(null);
    setGraphMessageId(null);
  }

  // Sidebar: hovering its button or the left edge shows it above the chat, a click pins it
  function peekSidebar(open) {
    if (sidebarOpen) return;
    clearTimeout(peekTimer.current);
    peekTimer.current = setTimeout(() => setPeek(open), open ? 90 : 280);
  }

  // Stop: the answer is dropped; a run also stops the engine, which starts again on the next request
  function stop() {
    const current = running.current;
    if (!current) return;
    stopped.current.add(current.messageId);
    running.current = null;
    const note = current.kind === "run" ? "Stopped. Steps that finished before the stop are in the audit log." : "Stopped.";
    chats.updateMessage(current.chatId, current.messageId, (message) => ({ busy: null, note, reading: message.busy?.types ?? message.reading }));
    if (current.kind === "run") stopEngine().catch(() => {});
  }

  // The status under a message follows what the engine is doing
  function setProgress(chatId, messageId, word, percent, types = null) {
    chats.updateMessage(chatId, messageId, (message) =>
      message.busy ? { busy: { ...message.busy, word, percent, types: types ? { ...message.busy.types, ...types } : message.busy.types } } : {},
    );
  }
  latestSetProgress.current = setProgress;

  // One engine call, shown as a working status on the message, then logged
  async function work(chatId, messageId, word, call, onResult, kind = "read") {
    const startedAt = performance.now();
    running.current = { chatId, messageId, word, kind };
    chats.updateMessage(chatId, messageId, { busy: { word, percent: null, startedAt }, error: null, note: null });
    try {
      const result = await call();
      if (stopped.current.delete(messageId)) return null;
      running.current = null;
      const ms = performance.now() - startedAt;
      chats.updateMessage(chatId, messageId, (message) => {
        const patch = onResult(result, message, ms);
        return { busy: null, ...patch, events: [...(message.events ?? []), ...(patch.events ?? [])] };
      });
      return result;
    } catch (error) {
      if (stopped.current.delete(messageId)) return null;
      running.current = null;
      chats.updateMessage(chatId, messageId, (message) => ({ busy: null, error: String(error), reading: message.busy?.types ?? message.reading }));
      return null;
    }
  }

  // A ready plan goes on by itself: read-only work runs, changes wait for a yes or a code in the chat
  async function proceed(chatId, messageId, plan) {
    if (plan.status !== "Ready" || plan.steps.every((step) => step.output === "code")) return;
    const onlyTools = plan.steps.every((step) => step.output === "mcp");
    const simulation = await work(chatId, messageId, onlyTools ? "Preparing the call" : "Checking what will change", () => lambek("simulate", { id: plan.id }), (simulation, message, ms) => ({
      simulation,
      execution: null,
      events: [{ stage: "Simulate", label: "Simulated", detail: simulationDetail(simulation), ms }],
    }));
    if (simulation?.status === "Ready" && simulation.risk === "low") run(chatId, messageId, plan, simulation);
  }

  function run(chatId, messageId, plan, simulation, typedCode) {
    const servers = [...new Set(plan.steps.filter((step) => step.output === "mcp").map((step) => step.action.split(".")[0].replace(/^mcp-/, "")))];
    const doing = servers.length > 0 && plan.steps.every((step) => step.output === "mcp") ? `Calling ${servers.join(", ")}` : "Running";
    const needsApproval = simulation.risk !== "low";
    return work(
      chatId,
      messageId,
      needsApproval ? "Approving" : doing,
      async () => {
        if (needsApproval) {
          await lambek("approve", { id: plan.id, confirmation: typedCode ?? "" });
          setProgress(chatId, messageId, doing, null);
        }
        return lambek("run", { id: plan.id });
      },
      (execution, _message, ms) => ({
        plan,
        simulation,
        execution: keepRows(execution),
        events: [
          ...(needsApproval ? [{ stage: "Approve", detail: "approval bound to the plan hash and the files" }] : []),
          { stage: "Run", label: execution.status === "Completed" ? "Ran" : "Stopped", detail: execution.reason ?? execution.status.toLowerCase(), ms },
        ],
      }),
      "run",
    );
  }

  // A long chat is compacted, with the only progress bar of the app
  const compacting = useRef(false);
  useEffect(() => {
    const chat = chats.current;
    if (!chat || busy || compacting.current) return;
    const older = chat.messages.slice(0, -RECENT_MESSAGES).filter((message) => message.role === "lambek" && !message.compacted && !message.busy);
    if (older.length === 0) return;
    const long = JSON.stringify(chat).length > LONG_CHAT_BYTES || chat.messages.length - (chat.compactedUpTo ?? 0) > LONG_CHAT_MESSAGES;
    if (long) compact(chat.id, chat.messages.length, older.map((message) => message.id));
  }, [messages]);

  async function compact(chatId, count, ids) {
    compacting.current = true;
    const word = "Compacting our conversation so we can keep going";
    const { messageId } = chats.addMessage({ role: "lambek", request: "" }, chatId);
    chats.updateMessage(chatId, messageId, { busy: { word, percent: 0, progress: true } });
    for (let index = 0; index < ids.length; index += 4) {
      for (const id of ids.slice(index, index + 4)) chats.updateMessage(chatId, id, shrink);
      chats.updateMessage(chatId, messageId, { busy: { word, percent: (Math.min(ids.length, index + 4) / ids.length) * 100, progress: true } });
      await new Promise((resolve) => setTimeout(resolve, 45));
    }
    chats.updateMessage(chatId, messageId, { busy: null, note: "Earlier results were shortened to keep this chat fast." });
    chats.updateChat(chatId, { compactedUpTo: count });
    compacting.current = false;
  }

  // The last plan that waits for a yes or a code
  const waiting = useMemo(() => {
    const message = [...messages].reverse().find((item) => item.role === "lambek" && !item.busy && (item.plan || item.answer));
    if (!message?.simulation || message.execution || message.simulation.status !== "Ready" || message.simulation.risk === "low") return null;
    // Nothing would change: there is nothing to confirm
    const changes = message.simulation.steps.some((step) => step.count > 0) || message.plan.steps.some((step) => step.output === "mcp");
    if (!changes) return null;
    return message;
  }, [messages]);

  // From the composer, or an edited request that takes the place of the old one:
  // then only the messages before it count
  async function ask(text, sentFiles = null, before = null) {
    const files = sentFiles ?? attachments;
    const typed = text.trim();
    const request = withAttachments(typed, files);
    const target = before ? [...before].reverse().find((message) => message.plan?.steps.some((item) => item.action)) : lastPlanMessage;
    const context = target?.plan.id;
    const step = focus?.step;
    const pending = before ? null : waiting;
    const language = chats.current?.language;
    const hasSummary = Boolean(chats.current?.summary) && (!before || before.some(namesChat));
    if (!typed && files.length === 0) return;
    if (!sentFiles) {
      setDraft("");
      setAttachments([]);
    }
    atBottom.current = true;

    const { chatId } = chats.addMessage({ role: "user", text: typed, attachments: files });

    // The confirmation code of a plan that changes things: run it
    const code = pending?.simulation.confirmationCode;
    if (code && typed.toUpperCase() === code) {
      const { messageId } = chats.addMessage({ role: "lambek", request: typed }, chatId);
      run(chatId, messageId, pending.plan, pending.simulation, code);
      return;
    }

    const { messageId } = chats.addMessage({ role: "lambek", request }, chatId);

    // Files without a message: what Lambek can read from them
    if (!typed && files.length > 0) {
      const result = await work(chatId, messageId, "Reading the files", () => lambek("inspect", { paths: files.map((file) => file.path), language, incognito }), (result, _message, ms) => ({
        kind: "files",
        answer: result.answer,
        elapsed: ms,
      }));
      if (result?.language) chats.updateChat(chatId, { language: result.language });
      return;
    }

    const word = context ? "Reading your reply" : "Reading your request";
    const result = await work(chatId, messageId, word, () => lambek("ask", { text: request, context, step, language, incognito }), (result, _message, ms) => {
      // The plan keeps the words of the request that created it
      const title = result.kind === "new" ? request : (target?.title ?? target?.request);
      if (result.kind === "explain") return { kind: "explain", answer: result.answer, elapsed: ms };
      if (result.kind === "run") return { kind: "run", answer: null, elapsed: ms };
      if (result.kind === "edit") setGraphMessageId(messageId);
      return { kind: result.kind, plan: result, title, elapsed: ms };
    });
    if (!result) return;
    if (result.language) chats.updateChat(chatId, { language: result.language });

    // A yes to a plan: run it, or ask for its code when it cannot be undone
    if (result.kind === "run" && target) {
      const ready = pending?.id === target.id ? pending : null;
      if (ready?.simulation.risk === "high") {
        const answer = result.language === "fr" ? `Tapez ${ready.simulation.confirmationCode} pour confirmer.` : `Type ${ready.simulation.confirmationCode} to confirm.`;
        chats.updateMessage(chatId, messageId, { answer });
      } else if (ready) {
        run(chatId, messageId, ready.plan, ready.simulation);
      } else {
        chats.updateMessage(chatId, messageId, { plan: target.plan, title: target.title });
        proceed(chatId, messageId, target.plan);
      }
      return;
    }

    // The first task of a chat gives it a short title
    if (!hasSummary && result.status === "Ready" && result.steps?.some((item) => item.action)) {
      chats.updateChat(chatId, { summary: summarize(result) });
    }

    if (result.status === "Ready") proceed(chatId, messageId, result);
  }

  // An edited request: the old one and what followed go, Lambek works on the new words in their place
  function editRequest(messageId, text, files) {
    const index = messages.findIndex((message) => message.id === messageId);
    if (index < 0 || busy) return;
    const before = messages.slice(0, index);
    const chatId = chats.currentId;
    chats.truncateFrom(chatId, messageId);
    // The chat was named after a plan that goes away: it takes the name of the next one
    if (!before.some(namesChat)) chats.updateChat(chatId, { summary: null, ...(before.length === 0 ? { title: text } : {}) });
    ask(text, files, before);
  }

  // Retry an answer: its request is asked again in the same place, what followed goes
  function retryFor(answerId) {
    const index = messages.findIndex((message) => message.id === answerId);
    const request = [...messages.slice(0, index)].reverse().find((message) => message.role === "user");
    if (!request) return null;
    return () => editRequest(request.id, request.text ?? "", request.attachments ?? []);
  }

  async function edit(step, name, value) {
    const message = graphMessage;
    const startedAt = performance.now();
    const plan = await lambek("edit", { id: message.plan.id, step, name, value });
    const ms = performance.now() - startedAt;
    chats.updateMessage(chats.currentId, message.id, (current) => ({
      plan,
      simulation: null,
      execution: null,
      kind: "edit",
      events: [...(current.events ?? []), { stage: "Edit", label: "Updated", detail: `step ${step}: ${name} = ${value || "none"}`, ms }],
    }));
  }

  function pickExample(text) {
    setDraft(text);
    setFocusToken((token) => token + 1);
  }

  const composerFor = (compact) => (
    <Composer
      compact={compact}
      text={draft}
      onText={setDraft}
      busy={busy}
      onStop={stop}
      attachments={attachments}
      onAttach={addAttachments}
      onDetach={(path) => setAttachments((current) => current.filter((file) => file.path !== path))}
      onSend={ask}
      onInsert={(text) => {
        setDraft(text);
        setFocusToken((token) => token + 1);
      }}
      onTools={() => setView("tools")}
      focus={focus}
      focusToken={focusToken}
      onClearFocus={() => setSelectedStep(null)}
      placeholder={
        focus ? `Ask about step ${focus.step}, or change it…` : lastPlanMessage ? "Reply, change a value, or ask why…" : "Describe a task…"
      }
    />
  );

  const isHome = view === "chat" && messages.length === 0;
  const pinned = !incognito && sidebarOpen;
  const peeking = !incognito && !sidebarOpen && peek;

  const menu = [
    {
      label: "File",
      items: [
        { label: "New chat", keys: "Ctrl+N", onSelect: newChat },
        { label: incognito ? "Leave incognito" : "New incognito chat", keys: "Ctrl+Shift+N", onSelect: toggleIncognito },
        { separator: "exit" },
        { label: { windows: "Exit", mac: "Quit Lambek", linux: "Quit" }[platform], keys: platform === "windows" ? "Alt+F4" : "Ctrl+Q", onSelect: () => closeWindow() },
      ],
    },
    {
      label: "Edit",
      items: [
        { label: "Undo", keys: "Ctrl+Z", onSelect: () => editCommand("undo") },
        { label: "Redo", keys: platform === "mac" ? "Ctrl+Shift+Z" : "Ctrl+Y", onSelect: () => editCommand("redo") },
        { separator: "clipboard" },
        { label: "Cut", keys: "Ctrl+X", onSelect: () => editCommand("cut") },
        { label: "Copy", keys: "Ctrl+C", onSelect: () => editCommand("copy") },
        { label: "Paste", keys: "Ctrl+V", onSelect: () => editCommand("paste") },
        { label: "Select all", keys: "Ctrl+A", onSelect: () => editCommand("selectAll") },
      ],
    },
    {
      label: "View",
      items: [
        { label: sidebarOpen ? "Hide sidebar" : "Show sidebar", keys: "Ctrl+B", onSelect: () => setSidebarOpen(!sidebarOpen) },
        { label: "Nodes", keys: "Ctrl+G", disabled: !lastPlanMessage, onSelect: () => setView("graph") },
        { separator: "zoom" },
        { label: "Zoom in", keys: "Ctrl+=", onSelect: () => zoomBy(1) },
        { label: "Zoom out", keys: "Ctrl+-", onSelect: () => zoomBy(-1) },
        { label: "Actual size", keys: "Ctrl+0", onSelect: () => setZoom(1) },
        { separator: "screen" },
        { label: platform === "mac" ? "Enter full screen" : "Full screen", keys: platform === "mac" ? "Control+Ctrl+F" : "F11", onSelect: () => toggleFullscreen().catch(() => {}) },
      ],
    },
    {
      label: "Go",
      items: [
        { label: "Back", keys: platform === "mac" ? "Ctrl+[" : "Alt+Left", disabled: !canGo.back, onSelect: () => go(-1) },
        { label: "Forward", keys: platform === "mac" ? "Ctrl+]" : "Alt+Right", disabled: !canGo.forward, onSelect: () => go(1) },
        { separator: "history" },
        { label: "Previous chat", keys: "Ctrl+Shift+Tab", disabled: chats.chats.length < 2, onSelect: () => goChat(-1) },
        { label: "Next chat", keys: "Ctrl+Tab", disabled: chats.chats.length < 2, onSelect: () => goChat(1) },
        { separator: "search" },
        {
          label: "Search chats",
          keys: "Ctrl+K",
          onSelect: () => {
            setSidebarOpen(true);
            setTimeout(() => search.current?.focus(), 0);
          },
        },
      ],
    },
    {
      label: "Help",
      items: [
        { label: "Keyboard shortcuts", onSelect: () => setDialog("keys") },
        { label: "Check for updates…", onSelect: findUpdates },
        { label: "About Lambek", onSelect: () => setDialog("about") },
      ],
    },
  ];

  return (
    <div className={`app ${pinned ? "with-sidebar" : ""} ${peeking ? "peeking" : ""} ${incognito ? "incognito" : ""}`}>
      <header className="titlebar" data-tauri-drag-region>
        {incognito ? (
          <span className="incognito-title">
            <GhostNodes size={18} /> Incognito
          </span>
        ) : (
          <div className="titlebar-start" data-tauri-drag-region>
            <AppMenu sections={menu} />
            <button
              className="icon-button"
              onClick={() => {
                setSidebarOpen(!sidebarOpen);
                setPeek(false);
              }}
              onMouseEnter={() => peekSidebar(true)}
              onMouseLeave={() => peekSidebar(false)}
              data-tip={sidebarOpen ? "Hide sidebar" : "Show sidebar"}
              data-keys={keyLabel("Ctrl+B")}
              aria-label={sidebarOpen ? "Close sidebar" : "Open sidebar"}
            >
              <PanelLeft size={18} />
            </button>
            <button className="icon-button" onClick={() => go(-1)} disabled={!canGo.back} data-tip="Back" data-keys={BACK_KEYS} aria-label="Back">
              <ArrowLeft size={18} />
            </button>
            <button className="icon-button" onClick={() => go(1)} disabled={!canGo.forward} data-tip="Forward" data-keys={FORWARD_KEYS} aria-label="Forward">
              <ArrowRight size={18} />
            </button>
          </div>
        )}
        <span className="titlebar-title" data-tauri-drag-region />
        {incognito ? (
          <button className="icon-button" onClick={toggleIncognito} data-tip="Leave incognito" data-keys={keyLabel("Ctrl+Shift+N")} aria-label="Leave incognito">
            <X size={18} />
          </button>
        ) : (
          isHome && (
            <button className="icon-button" onClick={toggleIncognito} data-tip="Incognito" data-keys={keyLabel("Ctrl+Shift+N")} aria-label="Incognito">
              <GhostNodes size={19} />
            </button>
          )
        )}
        <WindowControls />
      </header>

      {!incognito && !sidebarOpen && <div className="edge" onMouseEnter={() => peekSidebar(true)} onMouseLeave={() => peekSidebar(false)} />}

      {!incognito && (
        <Sidebar
          onEnter={() => peekSidebar(true)}
          onLeave={() => peekSidebar(false)}
          onNew={newChat}
          onTools={() => setView(view === "tools" ? "chat" : "tools")}
          toolsActive={view === "tools"}
          chats={chats.chats}
          currentId={chats.currentId}
          searchRef={search}
          onOpen={(id) => {
            chats.open(id);
            setView("chat");
            setSelectedStep(null);
            setGraphMessageId(null);
            setPeek(false);
          }}
          onRemove={chats.removeChat}
          onUpdate={chats.updateChat}
          account={{
            name: engine?.user,
            theme: theme.preference,
            onTheme: theme.choose,
            onShortcuts: () => setDialog("keys"),
            onUpdates: findUpdates,
            onAbout: () => setDialog("about"),
          }}
        />
      )}

      <main className="main">
        {view === "chat" && !isHome && !incognito && chats.current && (
          <ChatHeading chat={chats.current} onUpdate={chats.updateChat} onRemove={chats.removeChat} />
        )}
        {view === "tools" && <Tools onChanged={loadCategories} />}

        {view === "graph" && graphMessage && (
          <Suspense fallback={<section className="graph" />}>
            <Graph3D
              plan={graphMessage.plan}
              title={graphMessage.title ?? graphMessage.request}
              theme={theme.theme}
              selected={selectedStep}
              onSelect={setSelectedStep}
              onEdit={edit}
              caption={lastAnswer?.execution?.answer ?? lastAnswer?.simulation?.answer ?? lastAnswer?.plan?.answer ?? lastAnswer?.answer}
              onClose={() => setView("chat")}
            />
          </Suspense>
        )}

        {view === "chat" &&
          (isHome ? (
            <Home
              name={engine?.user}
              incognito={incognito}
              categories={categories}
              engineError={engine && !engine.ok ? engine.error : null}
              onExample={pickExample}
              onTools={() => setView("tools")}
            >
              {composerFor(false)}
            </Home>
          ) : (
            <section className="conversation" ref={conversation} onScroll={followScroll}>
              <div className="turns">
                {messages.map((message) => {
                  if (message.role === "user") {
                    return <Request key={message.id} message={message} busy={busy} onEdit={(text, files) => editRequest(message.id, text, files)} />;
                  }
                  return (
                    <Answer
                      key={message.id}
                      message={message}
                      canRetry={!busy}
                      onRetry={retryFor(message.id)}
                      onOpenStep={(step) => {
                        setGraphMessageId(message.id);
                        setView("graph");
                        setSelectedStep(step);
                      }}
                    />
                  );
                })}
                <div ref={bottom} className="turns-end" />
              </div>
            </section>
          ))}

        {!isHome && view !== "tools" ? (
          <footer className="dock">
            {view === "chat" && busy && !following && (
              <button className="working-pill" onClick={toBottom} aria-label={`${busyMessage?.busy.word ?? "Working"}. Show the latest message`}>
                <ReductionMark />
              </button>
            )}
            {composerFor(true)}
          </footer>
        ) : (
          <span />
        )}
      </main>

      {dialog === "about" && (
        <Dialog title="About Lambek" onClose={() => setDialog(null)}>
          <div className="about">
            <h2 className="about-name">
              Lambek <i>for</i> {PLATFORM_NAMES[platform]}
            </h2>
            <p className="about-version">
              Version {appVersion} (engine {engine?.version ?? "not started"})
            </p>
            <button className="button about-button" onClick={() => setDialog("keys")}>
              Help
            </button>
            <button className="button about-button" onClick={() => openUrl(`https://github.com/${REPOSITORY}/issues`)}>
              Get support
            </button>
          </div>
        </Dialog>
      )}

      {update && (
        <Dialog title="Updates" onClose={() => setUpdate(null)}>
          <div className="update">
            {update.state === "checking" && <p>Checking GitHub for a newer version…</p>}
            {update.state === "current" && <p>Lambek {appVersion} is up to date.</p>}
            {update.state === "none" && <p>No release is published yet. You have Lambek {appVersion}.</p>}
            {update.state === "error" && <p>Could not reach GitHub: {update.message}</p>}
            {update.state === "newer" && (
              <>
                <p>
                  Lambek {update.latest} is available. You have {appVersion}.
                </p>
                <button className="button primary" onClick={() => openUrl(update.url)}>
                  Open the download page
                </button>
              </>
            )}
            <p className="update-source">Source: github.com/{REPOSITORY}</p>
          </div>
        </Dialog>
      )}

      {dialog === "keys" && (
        <Dialog title="Keyboard shortcuts" onClose={() => setDialog(null)}>
          <dl className="facts keys">
            {SHORTCUTS.map(([keys, action]) => (
              <Fragment key={keys}>
                <dt>
                  <kbd>{keyLabel(keys)}</kbd>
                </dt>
                <dd>{action}</dd>
              </Fragment>
            ))}
          </dl>
        </Dialog>
      )}

      {dragging && (
        <div className="drop">
          <Upload size={21} />
          <span>Drop files to add them</span>
        </div>
      )}
    </div>
  );
}
