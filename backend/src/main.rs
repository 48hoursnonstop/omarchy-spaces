mod actions;
mod hypr;
mod protocol;
mod state;

use anyhow::{bail, Result};
use serde_json::json;
use std::process::ExitCode;

fn snapshot_json(state: &state::State) -> serde_json::Value {
    json!({
        "ok": true,
        "backendVersion": protocol::BACKEND_VERSION,
        "protocolVersion": protocol::PROTOCOL_VERSION,
        "stateSchemaVersion": protocol::STATE_SCHEMA_VERSION,
        "minimized": state.records
    })
}

fn run() -> Result<serde_json::Value> {
    let mut args = std::env::args().skip(1);
    let mut command = args.next().unwrap_or_else(|| "help".to_string());
    if command == "--protocol" {
        let expected = args.next().unwrap_or_default();
        if expected != protocol::PROTOCOL_VERSION.to_string() {
            bail!(
                "Backend update required: expected protocol {expected}, backend protocol {}",
                protocol::PROTOCOL_VERSION
            );
        }
        command = args.next().unwrap_or_else(|| "help".to_string());
    }

    if command == "version-json" {
        return Ok(json!({
            "ok": true,
            "backendVersion": protocol::BACKEND_VERSION,
            "protocolVersion": protocol::PROTOCOL_VERSION,
            "stateSchemaVersion": protocol::STATE_SCHEMA_VERSION,
            "hyprlandIpc": true
        }));
    }

    if command == "capabilities" {
        return Ok(json!({
            "ok": true,
            "protocolVersion": protocol::PROTOCOL_VERSION,
            "commands": [
                "snapshot",
                "minimize",
                "restore",
                "restore-last",
                "restore-all",
                "restore-workspace",
                "show-desktop-toggle",
                "reconcile",
                "recover",
                "window-action",
                "doctor-json"
            ]
        }));
    }

    if !matches!(command.as_str(), "snapshot" | "reconcile" | "doctor-json") {
        hypr::ensure_compatible()?;
    }
    // Doctor observes the atomically replaced state; it must not interrupt UI
    // transactions by taking their exclusive lock.
    let _state_lock = if command == "doctor-json" {
        None
    } else {
        Some(state::StateLock::acquire()?)
    };
    let mut state = state::load()?;
    match command.as_str() {
        "snapshot" | "reconcile" => {
            actions::reconcile(&mut state)?;
            Ok(snapshot_json(&state))
        }
        "minimize" => {
            let address = args
                .next()
                .ok_or_else(|| anyhow::anyhow!("missing address"))?;
            let changed = actions::minimize(&mut state, &address)?;
            Ok(json!({"ok": true, "changed": changed, "minimized": state.records}))
        }
        "restore" => {
            let address = args
                .next()
                .ok_or_else(|| anyhow::anyhow!("missing address"))?;
            let focus = args.any(|value| value == "--focus");
            let changed = actions::restore(&mut state, &address, focus)?;
            Ok(json!({"ok": true, "changed": changed, "minimized": state.records}))
        }
        "restore-last" => {
            let changed = actions::restore_last(&mut state)?;
            Ok(json!({"ok": true, "changed": changed, "minimized": state.records}))
        }
        "restore-all" => {
            let changed = actions::restore_all(&mut state)?;
            Ok(json!({"ok": true, "changed": changed, "minimized": state.records}))
        }
        "restore-workspace" => {
            let workspace = args
                .next()
                .ok_or_else(|| anyhow::anyhow!("missing workspace"))?;
            let changed = actions::restore_workspace(&mut state, &workspace)?;
            Ok(json!({"ok": true, "changed": changed, "minimized": state.records}))
        }
        "show-desktop-toggle" => {
            let workspace = args.next();
            let changed = actions::show_desktop_toggle(&mut state, workspace.as_deref())?;
            Ok(json!({"ok": true, "changed": changed, "minimized": state.records}))
        }
        "recover" => {
            let changed = actions::recover(&mut state)?;
            Ok(json!({"ok": true, "changed": changed, "minimized": state.records}))
        }
        "window-action" => {
            let action = args
                .next()
                .ok_or_else(|| anyhow::anyhow!("missing action"))?;
            let address = args
                .next()
                .ok_or_else(|| anyhow::anyhow!("missing address"))?;
            let argument = args.next();
            let moved_hidden = action == "move-workspace"
                && actions::move_minimized(
                    &mut state,
                    &address,
                    argument
                        .as_deref()
                        .ok_or_else(|| anyhow::anyhow!("move-workspace requires workspace"))?,
                )?;
            if !moved_hidden {
                hypr::action(&action, &address, argument.as_deref())?;
            }
            Ok(json!({
                "ok": true,
                "action": action,
                "address": address,
                "minimized": state.records
            }))
        }
        "doctor-json" => {
            let stranded_error = actions::ensure_not_hidden_without_record(&state)
                .err()
                .map(|error| error.to_string());
            Ok(json!({
                "ok": stranded_error.is_none() && !state.records.iter().any(|r| r.pending),
                "pendingTransactions": state.records.iter().filter(|r| r.pending).count(),
                "backendVersion": protocol::BACKEND_VERSION,
                "protocolVersion": protocol::PROTOCOL_VERSION,
                "stateSchemaVersion": protocol::STATE_SCHEMA_VERSION,
                "statePath": state::path().display().to_string(),
                "records": state.records.len(),
                "hyprland": hypr::version().unwrap_or_else(|error| format!("unavailable: {error}")),
                "strandedError": stranded_error
            }))
        }
        _ => bail!("unknown command: {command}"),
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(value) => {
            println!("{}", serde_json::to_string(&value).unwrap());
            if value.get("ok").and_then(|v| v.as_bool()) == Some(false) {
                ExitCode::from(1)
            } else {
                ExitCode::SUCCESS
            }
        }
        Err(error) => {
            let busy = error.downcast_ref::<state::Busy>().is_some();
            println!(
                "{}",
                json!({"ok": false, "busy": busy, "error": format!("{error:#}")})
            );
            ExitCode::from(if busy { 75 } else { 1 })
        }
    }
}
