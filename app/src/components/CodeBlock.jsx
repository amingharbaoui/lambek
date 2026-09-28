import { useState } from "react";
import { Check, Copy } from "lucide-react";

// Code with a copy button
export default function CodeBlock({ code }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 1597);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="code-block">
      <button className="icon-button small" onClick={copy} title="Copy" aria-label="Copy">
        {copied ? <Check size={13} /> : <Copy size={13} />}
      </button>
      <pre className="code">{code}</pre>
    </div>
  );
}
