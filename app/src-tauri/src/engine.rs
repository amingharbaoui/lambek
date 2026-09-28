use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Write};
use std::path::Path;
use std::process::{Child, ChildStderr, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// The PowerShell engine, running `Start-LambekHost` in a child process.
/// Requests and responses are one JSON object per line.
pub struct Engine {
    child: Arc<Mutex<Child>>,
    errors: Arc<Mutex<String>>,
    input: Option<ChildStdin>,
    output: BufReader<ChildStdout>,
    next_id: u64,
    pub ready: Value,
}

impl Engine {
    /// Starts pwsh, imports the module, loads the packs, and waits for the ready message.
    pub fn start(
        pwsh: &str,
        module: &Path,
        packs: &[&Path],
        audit: Option<&Path>,
    ) -> Result<Engine, String> {
        let pack_list = packs
            .iter()
            .map(|p| quote(&plain_path(p)))
            .collect::<Vec<_>>()
            .join(",");

        let mut script = format!(
            "Import-Module {}; Start-LambekHost -PackPath {}",
            quote(&plain_path(module)),
            pack_list
        );
        if let Some(path) = audit {
            script.push_str(&format!(" -AuditPath {}", quote(&plain_path(path))));
        }

        let mut command = Command::new(pwsh);
        command
            .args([
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                &script,
            ])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        // No console window on Windows
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x0800_0000);
        }

        let mut child = command
            .spawn()
            .map_err(|e| format!("Could not start PowerShell ({pwsh}): {e}"))?;

        let input = child.stdin.take().ok_or("No standard input")?;
        let mut output = BufReader::new(child.stdout.take().ok_or("No standard output")?);
        let errors = collect_errors(child.stderr.take().ok_or("No standard error")?);

        // First line: {"event":"ready", ...}
        let ready = read_json(&mut output).map_err(|e| with_errors(e, &errors))?;
        if ready["event"] != "ready" {
            return Err(format!("Unexpected first message: {ready}"));
        }

        Ok(Engine {
            child: Arc::new(Mutex::new(child)),
            errors,
            input: Some(input),
            output,
            next_id: 1,
            ready,
        })
    }

    /// Sends one request and returns its result, or the error message of the engine.
    #[cfg(test)]
    pub fn request(&mut self, method: &str, params: Value) -> Result<Value, String> {
        self.request_with(method, params, |_| {})
    }

    /// Same as `request`, and calls `on_progress` for each stage the engine reports while it works.
    pub fn request_with(
        &mut self,
        method: &str,
        params: Value,
        mut on_progress: impl FnMut(&Value),
    ) -> Result<Value, String> {
        let id = self.next_id;
        self.next_id += 1;

        let line = json!({ "id": id, "method": method, "params": params }).to_string();
        let input = self.input.as_mut().ok_or("Engine is not reachable.")?;
        writeln!(input, "{line}").map_err(|e| format!("Engine is not reachable: {e}"))?;
        input.flush().map_err(|e| e.to_string())?;

        // Progress lines come first, then the response
        let errors = Arc::clone(&self.errors);
        let mut response = read_json(&mut self.output).map_err(|e| with_errors(e, &errors))?;
        while response["event"] == "progress" {
            on_progress(&response);
            response = read_json(&mut self.output).map_err(|e| with_errors(e, &errors))?;
        }
        if response["id"] != json!(id) {
            return Err(format!("Response for another request: {response}"));
        }
        if let Some(message) = response["error"]["message"].as_str() {
            return Err(message.to_string());
        }
        Ok(response["result"].clone())
    }
}

/// Closing standard input lets the engine stop its MCP servers and exit.
/// If it does not exit in time, it is killed.
impl Engine {
    /// A handle that can stop the process while a request is waiting for its answer.
    pub fn stopper(&self) -> Arc<Mutex<Child>> {
        Arc::clone(&self.child)
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        drop(self.input.take());
        let deadline = Instant::now() + Duration::from_millis(1500);
        while Instant::now() < deadline {
            if let Ok(mut child) = self.child.lock()
                && let Ok(Some(_)) = child.try_wait()
            {
                return;
            }
            std::thread::sleep(Duration::from_millis(21));
        }
        if let Ok(mut child) = self.child.lock() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

fn read_json(output: &mut BufReader<ChildStdout>) -> Result<Value, String> {
    let mut bytes = Vec::new();
    let count = output
        .read_until(b'\n', &mut bytes)
        .map_err(|e| e.to_string())?;
    if count == 0 {
        return Err("The engine stopped.".to_string());
    }
    // The engine writes UTF-8; a stray byte must not lose the whole answer
    let line = String::from_utf8_lossy(&bytes);
    serde_json::from_str(&line).map_err(|e| format!("Invalid JSON from the engine: {e}"))
}

/// Reads what PowerShell writes on standard error, so a failed start can say why.
/// Only the last few thousand characters are kept.
fn collect_errors(stderr: ChildStderr) -> Arc<Mutex<String>> {
    let errors = Arc::new(Mutex::new(String::new()));
    let sink = Arc::clone(&errors);
    std::thread::spawn(move || {
        for line in BufReader::new(stderr).lines().map_while(Result::ok) {
            if let Ok(mut text) = sink.lock() {
                text.push_str(line.trim_end());
                text.push('\n');
                if text.len() > 4000 {
                    let cut = text.len() - 4000;
                    let cut = (cut..text.len())
                        .find(|&i| text.is_char_boundary(i))
                        .unwrap_or(0);
                    text.drain(..cut);
                }
            }
        }
    });
    errors
}

/// Adds the last error lines of PowerShell to a message.
fn with_errors(message: String, errors: &Arc<Mutex<String>>) -> String {
    // The reader thread needs a moment to receive the last lines
    std::thread::sleep(Duration::from_millis(150));
    let text = errors
        .lock()
        .map(|text| text.trim().to_string())
        .unwrap_or_default();
    if text.is_empty() {
        message
    } else {
        format!("{message} {text}")
    }
}

/// Windows paths from Tauri can start with \\?\, which PowerShell does not accept everywhere.
fn plain_path(path: &Path) -> String {
    let text = path.to_string_lossy();
    if let Some(rest) = text.strip_prefix(r"\\?\UNC\") {
        format!(r"\\{rest}")
    } else if let Some(rest) = text.strip_prefix(r"\\?\") {
        rest.to_string()
    } else {
        text.to_string()
    }
}

/// Single-quoted PowerShell string.
fn quote(text: &str) -> String {
    format!("'{}'", text.replace('\'', "''"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn repo() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
    }

    fn pwsh() -> String {
        std::env::var("LAMBEK_PWSH").unwrap_or_else(|_| "pwsh".to_string())
    }

    fn start() -> Engine {
        let root = repo();
        let module = root.join("engine/Lambek/Lambek.psd1");
        let files = root.join("dsl/files");
        let code = root.join("dsl/code");
        let audit = std::env::temp_dir().join("lambek-rust-test-audit.jsonl");
        Engine::start(&pwsh(), &module, &[&files, &code], Some(&audit)).expect("engine starts")
    }

    #[test]
    fn quotes_single_quotes() {
        assert_eq!(quote("C:\\it's"), "'C:\\it''s'");
    }

    #[test]
    fn starts_and_answers_ping() {
        let mut engine = start();
        let packs = engine.ready["packs"].as_array().unwrap();
        assert_eq!(packs[..2], [json!("files"), json!("code")]);
        let result = engine.request("ping", json!({})).unwrap();
        assert_eq!(result["name"], "Lambek");
    }

    #[test]
    fn asks_and_gets_a_plan() {
        let mut engine = start();
        let result = engine
            .request("ask", json!({ "text": "list the files in C:\\Temp" }))
            .unwrap();
        assert_eq!(result["status"], "Ready");
        assert_eq!(result["sentences"][0], "list the files in C:\\Temp");
    }

    #[test]
    fn keeps_accents_in_both_directions() {
        let mut engine = start();
        let result = engine
            .request(
                "ask",
                json!({ "text": "crée un dossier nommé \"Été\" dans C:\\Temp" }),
            )
            .unwrap();
        let sentence = result["sentences"][0].as_str().unwrap();
        assert!(
            sentence.starts_with("créer un dossier nommé Été"),
            "{sentence}"
        );
    }

    #[test]
    fn answers_small_talk() {
        let mut engine = start();
        let result = engine.request("ask", json!({ "text": "salut" })).unwrap();
        assert_eq!(result["answer"], "Bonjour ! Que voulez-vous faire ?");
    }

    #[test]
    fn stops_when_dropped() {
        let engine = start();
        drop(engine);
    }

    #[test]
    fn stops_from_another_thread() {
        let mut engine = start();
        let stopper = engine.stopper();
        std::thread::spawn(move || stopper.lock().unwrap().kill().unwrap())
            .join()
            .unwrap();
        std::thread::sleep(Duration::from_millis(300));
        let error = engine.request("ping", json!({})).unwrap_err();
        assert!(error.contains("stopped") || error.contains("not reachable"));
    }

    #[test]
    fn reports_progress_before_the_answer() {
        let mut engine = start();
        let mut stages = Vec::new();
        let result = engine
            .request_with(
                "ask",
                json!({ "text": "list the files in C:\\Temp" }),
                |event| stages.push(event["stage"].as_str().unwrap_or("").to_string()),
            )
            .unwrap();
        assert_eq!(result["status"], "Ready");
        assert_eq!(stages, ["Split", "Read", "Match", "Check", "Order"]);
    }

    #[test]
    fn removes_the_extended_path_prefix() {
        assert_eq!(
            plain_path(Path::new(r"\\?\C:\App\engine")),
            r"C:\App\engine"
        );
        assert_eq!(
            plain_path(Path::new(r"\\?\UNC\server\share")),
            r"\\server\share"
        );
        assert_eq!(plain_path(Path::new("/opt/lambek")), "/opt/lambek");
    }

    #[test]
    fn says_why_the_engine_did_not_start() {
        let root = repo();
        let missing = root.join("engine/Missing/Missing.psd1");
        let error = Engine::start(&pwsh(), &missing, &[], None)
            .err()
            .expect("the start fails");
        assert!(error.contains("stopped"), "{error}");
        assert!(error.contains("Missing"), "{error}");
    }

    #[test]
    fn returns_engine_errors() {
        let mut engine = start();
        let error = engine.request("nope", json!({})).unwrap_err();
        assert!(error.contains("Unknown method"));
    }
}
