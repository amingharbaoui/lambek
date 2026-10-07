import { useEffect, useState } from "react";
import { FileCog, RefreshCw } from "lucide-react";
import { lambek, openPath } from "../lambek.js";

const RISK_TONES = { low: "", medium: "warn", high: "danger" };
const STATUS_TEXT = { Connected: "running", Ready: "ready, starts on first use", Failed: "failed", Disabled: "disabled" };
const EXAMPLE = `{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "C:\\\\Users\\\\you\\\\Desktop"]
    }
  }
}`;

// MCP servers: their tools become actions Lambek can plan, simulate, and run
export default function Tools({ onChanged }) {
  const [data, setData] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  async function load(params = {}) {
    setBusy(true);
    setError(null);
    try {
      setData(await lambek("mcp", params));
      if (params.refresh) onChanged();
    } catch (problem) {
      setError(String(problem));
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    load();
  }, []);

  async function openConfig() {
    const result = await lambek("mcp", { create: true });
    setData(result);
    await openPath(result.config);
  }

  return (
    <section className="tools">
      <div className="tools-inner">
        <h1>Connectors</h1>
        <p className="lede">Local MCP servers. Each tool becomes an action: planned, simulated, and approved like any other.</p>

        <div className="tools-bar">
          <span className="path" title={data?.config}>
            {data?.config ?? "…"}
          </span>
          <button className="button ghost" onClick={openConfig}>
            <FileCog size={14} /> Open config
          </button>
          <button className="button" onClick={() => load({ refresh: true })} disabled={busy}>
            <RefreshCw size={14} className={busy ? "spin" : ""} /> Reload
          </button>
        </div>

        {error && <p className="error">{error}</p>}

        {data && data.servers.length === 0 && (
          <div className="empty-state">
            No servers yet. Add them to the config in the format below, then reload:
            <pre className="code">{EXAMPLE}</pre>
          </div>
        )}

        {data?.servers.map((server) => (
          <article key={server.name} className="server">
            <div className="server-head">
              <h2>{server.name}</h2>
              <span className={`tag ${server.status === "Failed" ? "danger" : ""}`}>{STATUS_TEXT[server.status] ?? server.status}</span>
              {server.version && <span className="status-time">MCP {server.version}</span>}
            </div>
            {server.error && <p className="error">{server.error}</p>}
            {server.tools.map((tool) => (
              <div key={tool.action} className="tool">
                <code>{tool.name}</code>
                <span title={tool.description}>{tool.description || tool.title}</span>
                <span className={`tag ${RISK_TONES[tool.risk]}`}>{tool.risk}</span>
              </div>
            ))}
            {server.skipped.length > 0 && (
              <p className="skipped">
                Not available: {server.skipped.map((item) => `${item.tool} (${item.reason})`).join(", ")}
              </p>
            )}
          </article>
        ))}
      </div>
    </section>
  );
}
