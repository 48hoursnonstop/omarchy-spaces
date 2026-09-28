use crate::hypr::Client;
use crate::protocol::{PLUGIN_ID, STATE_SCHEMA_VERSION};
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::{env, fs, io::Write, path::PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RestoreRecord {
    pub address: String,
    pub workspace_id: i64,
    pub workspace_name: String,
    #[serde(default = "crate::hypr::unknown_monitor")]
    pub monitor_id: i64,
    pub floating: bool,
    pub at: Vec<i64>,
    pub size: Vec<i64>,
    pub pinned: bool,
    pub pseudo: bool,
    pub fullscreen: i64,
    pub fullscreen_client: i64,
    pub group_key: String,
    pub sequence: u64,
    pub batch_id: Option<String>,
    pub original_active: Option<String>,
    pub class_name: String,
    #[serde(default)]
    pub initial_class: String,
    pub title: String,
    #[serde(default)]
    pub initial_title: String,
    #[serde(default)]
    pub pid: i64,
    // A compositor transaction may have applied only some of its dispatches.
    // Keep its record even when the window is no longer on the hidden workspace.
    #[serde(default)]
    pub pending: bool,
}

impl RestoreRecord {
    pub fn from_client(
        client: &Client,
        sequence: u64,
        batch_id: Option<String>,
        original_active: Option<String>,
    ) -> Self {
        let mut group = client.grouped.clone();
        group.push(client.address.clone());
        group.sort();
        group.dedup();

        Self {
            address: client.address.clone(),
            workspace_id: client.workspace.id,
            workspace_name: client.workspace.name.clone(),
            monitor_id: client.monitor,
            floating: client.floating,
            at: client.at.clone(),
            size: client.size.clone(),
            pinned: client.pinned,
            pseudo: client.pseudo,
            fullscreen: client.fullscreen,
            fullscreen_client: client.fullscreen_client,
            group_key: group.join("|"),
            sequence,
            batch_id,
            original_active,
            class_name: client.class_name.clone(),
            initial_class: client.initial_class.clone(),
            title: client.title.clone(),
            initial_title: client.initial_title.clone(),
            pid: client.pid,
            pending: true,
        }
    }

    pub fn workspace_selector(&self) -> String {
        if self.workspace_name.is_empty() {
            self.workspace_id.to_string()
        } else {
            self.workspace_name.clone()
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct State {
    pub schema_version: u32,
    pub next_sequence: u64,
    pub records: Vec<RestoreRecord>,
}

impl Default for State {
    fn default() -> Self {
        Self {
            schema_version: STATE_SCHEMA_VERSION,
            next_sequence: 1,
            records: Vec::new(),
        }
    }
}

pub fn path() -> PathBuf {
    let base = env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(".local/state")
        });
    base.join(PLUGIN_ID).join("restore-v1.json")
}

pub fn load() -> Result<State> {
    let path = path();
    if !path.exists() {
        return Ok(State::default());
    }

    let data = fs::read_to_string(&path).with_context(|| format!("reading {}", path.display()))?;
    let state: State = serde_json::from_str(&data).context("parsing restore state")?;

    if state.schema_version != STATE_SCHEMA_VERSION {
        anyhow::bail!("unsupported state schema {}", state.schema_version);
    }

    Ok(state)
}

pub fn save(state: &State) -> Result<()> {
    let path = path();
    let parent = path.parent().context("restore state path has no parent")?;
    fs::create_dir_all(parent)?;

    let temporary = path.with_extension(format!("json.tmp.{}", std::process::id()));
    let data = serde_json::to_vec_pretty(state)?;

    {
        let mut file = fs::File::create(&temporary)?;
        file.write_all(&data)?;
        file.sync_all()?;
    }

    fs::rename(&temporary, &path)?;
    fs::File::open(parent)?.sync_all()?;
    Ok(())
}

pub struct StateLock {
    _file: fs::File,
}

#[derive(Debug)]
pub struct Busy;

impl std::fmt::Display for Busy {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "another tornikegomareli.spaces backend action is already running"
        )
    }
}

impl std::error::Error for Busy {}

impl StateLock {
    pub fn acquire() -> Result<Self> {
        let base = env::var_os("XDG_RUNTIME_DIR")
            .map(PathBuf::from)
            .context("XDG_RUNTIME_DIR is unavailable")?;
        let directory = base.join(PLUGIN_ID);
        let path = directory.join("transaction.lock");
        fs::create_dir_all(&directory)?;
        let file = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(path)?;
        match file.try_lock() {
            Ok(()) => {}
            Err(fs::TryLockError::WouldBlock) => return Err(Busy.into()),
            Err(error) => return Err(error.into()),
        }
        // Never unlink the lock inode: the kernel releases it on close/crash.
        Ok(Self { _file: file })
    }
}
