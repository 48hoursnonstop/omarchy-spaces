use crate::{
    hypr,
    protocol::HIDDEN_WORKSPACE,
    state::{self, RestoreRecord, State},
};
use anyhow::{anyhow, bail, Result};
use std::cmp::Reverse;
use std::collections::{HashMap, HashSet};
use std::time::{SystemTime, UNIX_EPOCH};

fn by_address() -> Result<HashMap<String, hypr::Client>> {
    Ok(hypr::clients()?
        .into_iter()
        .map(|client| (client.address.to_ascii_lowercase(), client))
        .collect())
}

fn is_hidden(client: &hypr::Client) -> bool {
    let plain = HIDDEN_WORKSPACE.trim_start_matches("special:");
    client.workspace.name == HIDDEN_WORKSPACE || client.workspace.name == plain
}

pub fn reconcile(state: &mut State) -> Result<()> {
    let live = by_address()?;
    let before = state.records.len();

    state.records.retain(|record| {
        live.get(&record.address.to_ascii_lowercase())
            .map(|client| {
                (is_hidden(client) || record.pending)
                    && (record.pid == 0 || record.pid == client.pid)
            })
            .unwrap_or(false)
    });

    if state.records.len() != before {
        state::save(state)?;
    }

    Ok(())
}

fn group_targets(client: &hypr::Client, live: &HashMap<String, hypr::Client>) -> Vec<hypr::Client> {
    let mut addresses: HashSet<String> = client
        .grouped
        .iter()
        .map(|address| address.to_ascii_lowercase())
        .collect();
    addresses.insert(client.address.to_ascii_lowercase());

    let mut targets: Vec<_> = addresses
        .into_iter()
        .filter_map(|address| live.get(&address).cloned())
        .collect();

    if targets.is_empty() {
        targets.push(client.clone());
    }

    targets.sort_by(|left, right| left.address.cmp(&right.address));
    targets
}

fn persist_records(
    state: &mut State,
    clients: &[hypr::Client],
    batch_id: Option<String>,
    original_active: Option<String>,
) -> Result<()> {
    let mut changed = false;

    for client in clients {
        if state
            .records
            .iter()
            .any(|record| record.address.eq_ignore_ascii_case(&client.address))
        {
            continue;
        }

        let sequence = state.next_sequence;
        state.next_sequence += 1;
        state.records.push(RestoreRecord::from_client(
            client,
            sequence,
            batch_id.clone(),
            original_active.clone(),
        ));
        changed = true;
    }

    if changed {
        state::save(state)?;
    }

    Ok(())
}

fn hide_clients(clients: &[hypr::Client]) -> Result<()> {
    for client in clients {
        if client.pinned {
            hypr::set_pin(&client.address, false)?;
        }

        if client.fullscreen != 0 || client.fullscreen_client != 0 {
            hypr::set_fullscreen_state(&client.address, 0, 0)?;
        }

        hypr::move_to_workspace(&client.address, HIDDEN_WORKSPACE)?;
        hypr::wait_for_workspace(&client.address, HIDDEN_WORKSPACE)?;
    }

    Ok(())
}

fn finish_hide(state: &mut State, clients: &[hypr::Client]) -> Result<()> {
    for record in &mut state.records {
        if clients
            .iter()
            .any(|client| client.address.eq_ignore_ascii_case(&record.address))
        {
            record.pending = false;
        }
    }
    state::save(state)
}

pub fn minimize(state: &mut State, address: &str) -> Result<Vec<String>> {
    reconcile(state)?;
    let live = by_address()?;
    let address = hypr::normalize_address(address)?;
    let client = live
        .get(&address.to_ascii_lowercase())
        .ok_or_else(|| anyhow!("window not found: {address}"))?;

    if is_hidden(client) {
        return Ok(vec![address]);
    }

    let targets = group_targets(client, &live);
    persist_records(state, &targets, None, None)?;
    hide_clients(&targets)?;
    finish_hide(state, &targets)?;

    Ok(targets
        .iter()
        .map(|target| target.address.clone())
        .collect())
}

fn restore_records(
    state: &mut State,
    records: Vec<RestoreRecord>,
    focus_address: Option<&str>,
) -> Result<Vec<String>> {
    if records.is_empty() {
        return Ok(Vec::new());
    }

    let live = by_address()?;
    let mut restored = Vec::new();

    for record in &mut state.records {
        if records
            .iter()
            .any(|target| target.address.eq_ignore_ascii_case(&record.address))
        {
            record.pending = true;
        }
    }
    state::save(state)?;

    // Phase 1: return every live client to its destination workspace first.
    // Hyprland 0.56.x can otherwise process the follow-up layout state while
    // the client still belongs to the hidden special workspace.
    for record in &records {
        if !live.contains_key(&record.address.to_ascii_lowercase()) {
            continue;
        }

        let workspace = record.workspace_selector();
        hypr::move_to_workspace(&record.address, &workspace)?;
        hypr::wait_for_workspace(&record.address, &workspace)?;
        restored.push(record.address.clone());
    }

    // Phase 2: restore window state only after the workspace transfer settled.
    // For tiled clients we deliberately force a floating -> tiled transition.
    // A plain `unset` is a no-op when Hyprland already reports floating=false,
    // which is exactly the stale-target case that produced overlapping 1:1
    // windows on the first restore.
    for record in &records {
        if !restored
            .iter()
            .any(|address| address.eq_ignore_ascii_case(&record.address))
        {
            continue;
        }

        if record.floating {
            hypr::set_floating(&record.address, true)?;
            hypr::wait_for_floating(&record.address, true)?;
            hypr::move_resize(&record.address, &record.at, &record.size)?;
        } else {
            hypr::reattach_tiled(&record.address)?;
        }

        if record.pseudo {
            hypr::set_pseudo(&record.address, true)?;
        }

        if record.pinned {
            hypr::set_pin(&record.address, true)?;
        }

        if record.fullscreen != 0 || record.fullscreen_client != 0 {
            hypr::set_fullscreen_state(
                &record.address,
                record.fullscreen,
                record.fullscreen_client,
            )?;
        }
    }

    let removed: HashSet<_> = records
        .iter()
        .map(|record| record.address.to_ascii_lowercase())
        .collect();
    state
        .records
        .retain(|record| !removed.contains(&record.address.to_ascii_lowercase()));
    state::save(state)?;

    if let Some(address) = focus_address {
        if restored
            .iter()
            .any(|restored_address| restored_address.eq_ignore_ascii_case(address))
        {
            hypr::focus(address)?;
        }
    }

    Ok(restored)
}

pub fn restore(state: &mut State, address: &str, focus: bool) -> Result<Vec<String>> {
    reconcile(state)?;
    let address = hypr::normalize_address(address)?;
    let seed = state
        .records
        .iter()
        .find(|record| record.address.eq_ignore_ascii_case(&address))
        .cloned()
        .ok_or_else(|| anyhow!("window is not minimized by this plugin"))?;

    let records: Vec<_> = state
        .records
        .iter()
        .filter(|record| record.group_key == seed.group_key)
        .cloned()
        .collect();

    restore_records(
        state,
        records,
        if focus { Some(address.as_str()) } else { None },
    )
}

pub fn restore_last(state: &mut State) -> Result<Vec<String>> {
    reconcile(state)?;
    let seed = state
        .records
        .iter()
        .max_by_key(|record| record.sequence)
        .cloned();

    match seed {
        Some(record) => restore(state, &record.address, true),
        None => Ok(Vec::new()),
    }
}

pub fn move_minimized(state: &mut State, address: &str, workspace: &str) -> Result<bool> {
    reconcile(state)?;
    let address = hypr::normalize_address(address)?;
    let group = state
        .records
        .iter()
        .find(|r| r.address.eq_ignore_ascii_case(&address))
        .map(|r| r.group_key.clone());
    let Some(group) = group else { return Ok(false) };
    if workspace == HIDDEN_WORKSPACE || workspace == HIDDEN_WORKSPACE.trim_start_matches("special:")
    {
        bail!("the private minimized workspace is not a restore destination");
    }
    for record in &mut state.records {
        if record.group_key == group {
            record.workspace_name = workspace.to_string();
            record.workspace_id = workspace.parse().unwrap_or(0);
        }
    }
    state::save(state)?;
    restore(state, &address, false)?;
    Ok(true)
}

pub fn restore_all(state: &mut State) -> Result<Vec<String>> {
    reconcile(state)?;
    let records = state.records.clone();
    restore_records(state, records, None)
}

pub fn restore_workspace(state: &mut State, workspace: &str) -> Result<Vec<String>> {
    reconcile(state)?;
    let records = state
        .records
        .iter()
        .filter(|record| {
            record.workspace_name == workspace || record.workspace_id.to_string() == workspace
        })
        .cloned()
        .collect();
    restore_records(state, records, None)
}

pub fn show_desktop_toggle(state: &mut State, workspace_arg: Option<&str>) -> Result<Vec<String>> {
    reconcile(state)?;
    let workspace = workspace_arg
        .map(str::to_string)
        .unwrap_or(hypr::active_workspace()?.name);
    let batch_prefix = format!("desktop:{workspace}:");

    if let Some(seed) = state
        .records
        .iter()
        .find(|record| {
            record
                .batch_id
                .as_deref()
                .map(|batch| batch.starts_with(&batch_prefix))
                .unwrap_or(false)
        })
        .cloned()
    {
        let batch_id = seed.batch_id.clone();
        let focus_address = seed.original_active.clone();
        let mut records: Vec<_> = state
            .records
            .iter()
            .filter(|record| record.batch_id == batch_id)
            .cloned()
            .collect();
        // Restore the Show Desktop batch in reverse minimize order. This does
        // not attempt to reconstruct an exact tiled tree; it only makes the
        // compositor reinsert the most recently hidden clients first.
        records.sort_by_key(|record| Reverse(record.sequence));
        let restored = restore_records(state, records, None)?;

        if let Some(address) = focus_address {
            let _ = hypr::focus(&address);
        }

        return Ok(restored);
    }

    let live = hypr::clients()?;
    let active = hypr::active_window()?.map(|client| client.address);
    let targets: Vec<_> = live
        .into_iter()
        .filter(|client| {
            !is_hidden(client)
                && (client.workspace.name == workspace
                    || client.workspace.id.to_string() == workspace)
        })
        .collect();

    if targets.is_empty() {
        return Ok(Vec::new());
    }

    // A workspace control can be used without focusing that workspace first.
    // Restore focus only when it belonged to the windows hidden by this batch.
    let active = active.filter(|address| targets.iter().any(|client| &client.address == address));

    let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis();
    let batch_id = format!("desktop:{workspace}:{stamp}");
    persist_records(state, &targets, Some(batch_id), active)?;
    hide_clients(&targets)?;
    finish_hide(state, &targets)?;

    Ok(targets.into_iter().map(|client| client.address).collect())
}

pub fn recover(state: &mut State) -> Result<Vec<String>> {
    let mut restored = restore_all(state)?;
    let orphans: Vec<_> = hypr::clients()?.into_iter().filter(is_hidden).collect();
    if !orphans.is_empty() {
        let workspace = hypr::active_workspace()?;
        if workspace.id <= 0 || workspace.name.starts_with("special:") {
            bail!("select a normal workspace before recovering untracked windows");
        }
        // Original geometry/workspace cannot be reconstructed without a record.
        // Persist an explicit fallback destination before rescuing any orphan.
        let targets: Vec<_> = orphans
            .into_iter()
            .map(|mut client| {
                client.workspace = workspace.clone();
                client
            })
            .collect();
        persist_records(state, &targets, None, None)?;
        let records = state.records.clone();
        restored.extend(restore_records(state, records, None)?);
    }
    ensure_not_hidden_without_record(state)?;
    Ok(restored)
}

pub fn ensure_not_hidden_without_record(state: &State) -> Result<()> {
    let tracked: HashSet<_> = state
        .records
        .iter()
        .map(|record| record.address.to_ascii_lowercase())
        .collect();
    let stranded: Vec<_> = hypr::clients()?
        .into_iter()
        .filter(|client| {
            is_hidden(client) && !tracked.contains(&client.address.to_ascii_lowercase())
        })
        .collect();

    if !stranded.is_empty() {
        bail!(
            "{} untracked window(s) are on the plugin special workspace",
            stranded.len()
        );
    }

    Ok(())
}
