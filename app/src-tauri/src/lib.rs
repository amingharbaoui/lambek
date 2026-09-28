mod engine;

use engine::Engine;
use serde_json::Value;
use std::process::Child;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tauri::path::BaseDirectory;
use tauri::{AppHandle, Emitter, Manager, RunEvent};

/// The engine starts with the app, in the background, and lives for the whole session.
#[derive(Default)]
struct EngineState(Mutex<Option<Engine>>);

/// Kept apart from the engine lock, so a running request can be stopped.
#[derive(Default)]
struct Stopper(Mutex<Option<Arc<Mutex<Child>>>>);

fn start_engine(app: &AppHandle) -> Result<Engine, String> {
    let resource = |path: &str| {
        app.path()
            .resolve(path, BaseDirectory::Resource)
            .map_err(|e| e.to_string())
    };

    let module = resource("engine/Lambek/Lambek.psd1")?;
    let files = resource("dsl/files")?;
    let code = resource("dsl/code")?;
    let pwsh = std::env::var("LAMBEK_PWSH").unwrap_or_else(|_| "pwsh".to_string());

    Engine::start(&pwsh, &module, &[&files, &code], None)
}

/// Runs a closure with the engine, starting it first if needed.
/// The engine answers on a blocking pipe, so this runs off the async threads.
fn run_with_engine<T>(
    app: &AppHandle,
    work: impl FnOnce(&mut Engine) -> Result<T, String>,
) -> Result<T, String> {
    let state = app.state::<EngineState>();
    let mut guard = state.0.lock().map_err(|_| "Engine lock is broken.")?;

    if guard.is_none() {
        let engine = start_engine(app)?;
        if let Ok(mut stopper) = app.state::<Stopper>().0.lock() {
            *stopper = Some(engine.stopper());
        }
        *guard = Some(engine);
    }

    let engine = guard.as_mut().expect("engine was just started");
    let result = work(engine);

    // Restart on the next request if the engine stopped
    if let Err(message) = &result
        && (message.contains("stopped") || message.contains("not reachable"))
    {
        *guard = None;
    }
    result
}

async fn with_engine<T, F>(app: AppHandle, work: F) -> Result<T, String>
where
    T: Send + 'static,
    F: FnOnce(&mut Engine) -> Result<T, String> + Send + 'static,
{
    tauri::async_runtime::spawn_blocking(move || run_with_engine(&app, work))
        .await
        .map_err(|e| e.to_string())?
}

/// Version, packs, and MCP state of the engine.
#[tauri::command]
async fn status(app: AppHandle) -> Result<Value, String> {
    with_engine(app, |engine| Ok(engine.ready.clone())).await
}

/// Sends one request to the engine: ask, edit, simulate, approve, run, categories, mcp, or audit.
#[tauri::command]
async fn lambek(app: AppHandle, method: String, params: Value) -> Result<Value, String> {
    let emitter = app.clone();
    with_engine(app, move |engine| {
        engine.request_with(&method, params, |event| {
            let _ = emitter.emit("lambek-progress", event.clone());
        })
    })
    .await
}

/// Stops the engine and whatever it is running. It starts again on the next request.
#[tauri::command]
fn stop(app: AppHandle) -> Result<(), String> {
    let stopper = app.state::<Stopper>();
    let handle = stopper.0.lock().map_err(|_| "Stop lock is broken.")?.take();
    if let Some(child) = handle {
        child
            .lock()
            .map_err(|_| "Engine lock is broken.")?
            .kill()
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .manage(EngineState::default())
        .manage(Stopper::default())
        .setup(|app| {
            // Warm start: PowerShell loads while the window paints
            let handle = app.handle().clone();
            std::thread::spawn(move || run_with_engine(&handle, |_| Ok(())));

            // The page shows the window after its first frame; this is only a fallback
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                std::thread::sleep(Duration::from_secs(2));
                if let Some(window) = handle.get_webview_window("main") {
                    let _ = window.show();
                }
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![status, lambek, stop])
        .build(tauri::generate_context!())
        .expect("error while building Lambek")
        .run(|app, event| {
            // Stop the engine, and with it the MCP servers, when the app exits
            if let RunEvent::Exit = event
                && let Ok(mut guard) = app.state::<EngineState>().0.lock()
            {
                guard.take();
            }
        });
}
