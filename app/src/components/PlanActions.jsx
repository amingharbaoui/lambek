import CodeBlock from "./CodeBlock.jsx";

const SHOWN_ROWS = 89;

// Column names and values as people read them, not as PowerShell names them
const HEADERS = { FullName: "Path", Name: "Name", Length: "Size", LastWriteTime: "Modified", CreationTime: "Created" };
const ISO_DATE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/;

function readable(key, value) {
  if (value === null || value === undefined) return "";
  if (key === "Length" && typeof value === "number") {
    const units = ["bytes", "KB", "MB", "GB", "TB"];
    let size = value;
    let unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return unit === 0 ? `${size} bytes` : `${size.toFixed(1)} ${units[unit]}`;
  }
  if (typeof value === "string" && ISO_DATE.test(value)) {
    return new Date(value).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
  }
  return String(value);
}

function ResultTable({ rows, total }) {
  const columns = Object.keys(rows[0]);
  const count = Math.max(total ?? 0, rows.length);
  return (
    <>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              {columns.map((key) => (
                <th key={key} className={typeof rows[0][key] === "number" ? "number" : ""}>
                  {HEADERS[key] ?? key}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.slice(0, SHOWN_ROWS).map((row, index) => (
              <tr key={index}>
                {columns.map((key) => (
                  <td key={key} className={typeof row[key] === "number" ? "number" : ""}>
                    {readable(key, row[key])}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {count > SHOWN_ROWS && (
        <p className="table-note">
          Showing {SHOWN_ROWS} of {count} rows.
        </p>
      )}
    </>
  );
}

// What a plan produced: code to copy, rows it read, or the items it will change
export default function PlanActions({ message }) {
  const { plan, execution } = message;
  if (!plan || plan.status !== "Ready") return null;

  // Generated code is shown, never run
  if (plan.steps.every((step) => step.output === "code")) {
    return plan.steps.map((step) => <CodeBlock key={step.step} code={step.script} />);
  }

  if (execution) {
    return execution.steps.map((step) =>
      step.output.length > 0 && typeof step.output[0] === "object" ? <ResultTable key={step.step} rows={step.output} total={step.total} /> : null,
    );
  }

  // The files a change would touch are listed with the stages, under the arrow
  return null;
}
