use std::{env, fs, path::PathBuf};

fn main() {
    // Fresh copy of the engine and the packs: a file removed from them must not stay next to the app
    if let Ok(out) = env::var("OUT_DIR") {
        if let Some(profile) = PathBuf::from(out).ancestors().nth(3) {
            for name in ["engine", "dsl"] {
                let _ = fs::remove_dir_all(profile.join(name));
            }
        }
    }
    tauri_build::build()
}
