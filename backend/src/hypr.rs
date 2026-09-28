use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::{process::Command, thread, time::Duration};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Workspace {
    #[serde(default)]
    pub id: i64,
    #[serde(default)]
    pub name: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Client {
    #[serde(default)]
    pub address: String,
    #[serde(default)]
    pub at: Vec<i64>,
    #[serde(default)]
    pub size: Vec<i64>,
    #[serde(default)]
    pub workspace: Workspace,
    #[serde(default)]
    pub floating: bool,
    #[serde(default)]
    pub pseudo: bool,
    #[serde(default, rename = "class")]
    pub class_name: String,
    #[serde(default)]
    pub title: String,
    #[serde(default, rename = "initialClass")]
    pub initial_class: String,
    #[serde(default, rename = "initialTitle")]
    pub initial_title: String,
    #[serde(default)]
    pub pid: i64,
    #[serde(default = "unknown_monitor")]
    pub monitor: i64,
    #[serde(default)]
    pub pinned: bool,
    #[serde(default)]
    pub fullscreen: i64,
    #[serde(default, rename = "fullscreenClient")]
    pub fullscreen_client: i64,
    #[serde(default)]
    pub grouped: Vec<String>,
    #[serde(default)]
    pub tags: Vec<String>,
}

pub fn unknown_monitor() -> i64 {
    -1
}

pub fn normalize_address(value: &str) -> Result<String> {
    let mut address = value.trim().to_ascii_lowercase();
    if let Some(rest) = address.strip_prefix("0x") {
        address = rest.to_string();
    }

    if address.is_empty()
        || !address
            .chars()
            .all(|character| character.is_ascii_hexdigit())
    {
        bail!("invalid Hyprland window address");
    }

    Ok(format!("0x{address}"))
}

fn output(args: &[&str]) -> Result<String> {
    let result = Command::new("hyprctl")
        .args(args)
        .output()
        .context("failed to execute hyprctl")?;

    if !result.status.success() {
        return Err(anyhow!(
            "hyprctl failed: {}",
            String::from_utf8_lossy(&result.stderr).trim()
        ));
    }

    String::from_utf8(result.stdout).context("hyprctl returned non-UTF8 output")
}

pub fn version() -> Result<String> {
    Ok(output(&["version"])?
        .lines()
        .next()
        .unwrap_or_default()
        .trim()
        .to_string())
}

pub fn ensure_compatible() -> Result<()> {
    let installed = version()?;
    if !installed.starts_with("Hyprland 0.56.") {
        bail!("unsupported Hyprland version: {installed}; reviewed dispatcher API is 0.56.x");
    }
    Ok(())
}

pub fn clients() -> Result<Vec<Client>> {
    Ok(serde_json::from_str(&output(&["-j", "clients"])?)?)
}

pub fn active_window() -> Result<Option<Client>> {
    let value: serde_json::Value = serde_json::from_str(&output(&["-j", "activewindow"])?)?;
    if value
        .as_object()
        .map(|object| object.is_empty())
        .unwrap_or(true)
    {
        return Ok(None);
    }
    Ok(Some(serde_json::from_value(value)?))
}

pub fn active_workspace() -> Result<Workspace> {
    Ok(serde_json::from_str(&output(&["-j", "activeworkspace"])?)?)
}

pub fn dispatch(expression: &str) -> Result<()> {
    let result = Command::new("hyprctl")
        .arg("dispatch")
        .arg(expression)
        .output()
        .context("failed to execute hyprctl dispatch")?;

    if !result.status.success() {
        bail!(
            "Hyprland dispatcher failed: {}",
            String::from_utf8_lossy(&result.stderr).trim()
        );
    }

    let stdout = String::from_utf8_lossy(&result.stdout);
    if stdout.to_ascii_lowercase().contains("error") {
        bail!("Hyprland dispatcher rejected request: {}", stdout.trim());
    }

    Ok(())
}

pub fn lua_string(value: &str) -> String {
    let mut output = String::with_capacity(value.len() + 2);
    output.push('"');
    for character in value.chars() {
        match character {
            '\\' => output.push_str("\\\\"),
            '"' => output.push_str("\\\""),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            other => output.push(other),
        }
    }
    output.push('"');
    output
}

pub fn selector(address: &str) -> Result<String> {
    Ok(format!("address:{}", normalize_address(address)?))
}

pub fn focus(address: &str) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.focus({{ window = {} }})",
        lua_string(&selector(address)?)
    ))
}

pub fn move_to_workspace(address: &str, workspace: &str) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.move({{ window = {}, workspace = {}, follow = false }})",
        lua_string(&selector(address)?),
        lua_string(workspace)
    ))
}

pub fn set_floating(address: &str, value: bool) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.float({{ window = {}, action = {} }})",
        lua_string(&selector(address)?),
        lua_string(if value { "set" } else { "unset" })
    ))
}

pub fn set_pseudo(address: &str, value: bool) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.pseudo({{ window = {}, action = {} }})",
        lua_string(&selector(address)?),
        lua_string(if value { "set" } else { "unset" })
    ))
}

pub fn set_pin(address: &str, value: bool) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.pin({{ window = {}, action = {} }})",
        lua_string(&selector(address)?),
        lua_string(if value { "set" } else { "unset" })
    ))
}

pub fn alter_zorder_top(address: &str) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.alter_zorder({{ window = {}, mode = \"top\" }})",
        lua_string(&selector(address)?)
    ))
}

pub fn client_by_address(address: &str) -> Result<Client> {
    let normalized = normalize_address(address)?;
    clients()?
        .into_iter()
        .find(|client| client.address.eq_ignore_ascii_case(&normalized))
        .ok_or_else(|| anyhow!("window not found: {normalized}"))
}

fn workspace_matches(client: &Client, workspace: &str) -> bool {
    client.workspace.name == workspace || client.workspace.id.to_string() == workspace
}

pub fn wait_for_workspace(address: &str, workspace: &str) -> Result<()> {
    for _ in 0..25 {
        if let Ok(client) = client_by_address(address) {
            if workspace_matches(&client, workspace) {
                return Ok(());
            }
        }
        thread::sleep(Duration::from_millis(8));
    }

    let client = client_by_address(address)?;
    bail!(
        "window {} did not settle on workspace {} (currently {})",
        normalize_address(address)?,
        workspace,
        client.workspace.name
    )
}

pub fn wait_for_floating(address: &str, expected: bool) -> Result<()> {
    for _ in 0..25 {
        if let Ok(client) = client_by_address(address) {
            if client.floating == expected {
                return Ok(());
            }
        }
        thread::sleep(Duration::from_millis(8));
    }

    let client = client_by_address(address)?;
    bail!(
        "window {} floating state did not settle at {} (currently {})",
        normalize_address(address)?,
        expected,
        client.floating
    )
}

pub fn reattach_tiled(address: &str) -> Result<()> {
    // Moving a tiled client out of a hidden special workspace can leave the
    // compositor with a tiled flag but no freshly attached layout target.
    // Force one real floating -> tiled transition after the workspace move so
    // Hyprland rebuilds the target in the destination layout immediately.
    set_floating(address, true)?;
    wait_for_floating(address, true)?;
    set_floating(address, false)?;
    wait_for_floating(address, false)?;
    Ok(())
}

pub fn set_fullscreen_state(address: &str, internal: i64, client: i64) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.fullscreen_state({{ window = {}, action = \"set\", internal = {}, client = {}, layout_aware = true }})",
        lua_string(&selector(address)?),
        internal,
        client
    ))
}

pub fn move_resize(address: &str, at: &[i64], size: &[i64]) -> Result<()> {
    if at.len() >= 2 {
        dispatch(&format!(
            "hl.dsp.window.move({{ window = {}, x = {}, y = {}, relative = false }})",
            lua_string(&selector(address)?),
            at[0],
            at[1]
        ))?;
    }

    if size.len() >= 2 {
        dispatch(&format!(
            "hl.dsp.window.resize({{ window = {}, x = {}, y = {}, relative = false }})",
            lua_string(&selector(address)?),
            size[0],
            size[1]
        ))?;
    }

    Ok(())
}

pub fn resize(address: &str, width: i64, height: i64) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.resize({{ window = {}, x = {}, y = {}, relative = false }})",
        lua_string(&selector(address)?),
        width,
        height
    ))
}

pub fn center(address: &str) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.center({{ window = {} }})",
        lua_string(&selector(address)?)
    ))
}

pub fn tag(address: &str, tag: &str) -> Result<()> {
    dispatch(&format!(
        "hl.dsp.window.tag({{ window = {}, tag = {} }})",
        lua_string(&selector(address)?),
        lua_string(tag)
    ))
}

fn has_tag(client: &Client, wanted: &str) -> bool {
    client
        .tags
        .iter()
        .any(|tag| tag.trim_end_matches('*') == wanted)
}

pub fn action(action: &str, address: &str, argument: Option<&str>) -> Result<()> {
    let window = lua_string(&selector(address)?);
    let expression = match action {
        "focus" => format!("hl.dsp.focus({{ window = {window} }})"),
        "close" => format!("hl.dsp.window.close({{ window = {window} }})"),
        "float-toggle" => format!(
            "hl.dsp.window.float({{ window = {window}, action = \"toggle\" }})"
        ),
        "fullscreen-toggle" => format!(
            "hl.dsp.window.fullscreen({{ window = {window}, action = \"toggle\", mode = \"fullscreen\" }})"
        ),
        "maximized-toggle" => format!(
            "hl.dsp.window.fullscreen({{ window = {window}, action = \"toggle\", mode = \"maximized\" }})"
        ),
        "pseudo-toggle" => format!(
            "hl.dsp.window.pseudo({{ window = {window}, action = \"toggle\" }})"
        ),
        "group-toggle" => {
            // Omarchy 4.0.4 binds hl.dsp.group.toggle() without a window selector.
            // Focus the exact address first so the active-window dispatcher cannot
            // operate on a sibling or whichever client happened to be active.
            focus(address)?;
            dispatch("hl.dsp.group.toggle()")?;
            return Ok(());
        }
        "move-workspace" => {
            let workspace = argument.ok_or_else(|| anyhow!("move-workspace requires workspace"))?;
            format!(
                "hl.dsp.window.move({{ window = {window}, workspace = {}, follow = false }})",
                lua_string(workspace)
            )
        }
        "move-monitor" => {
            let monitor = argument.ok_or_else(|| anyhow!("move-monitor requires monitor"))?;
            format!(
                "hl.dsp.window.move({{ window = {window}, monitor = {}, follow = false }})",
                lua_string(monitor)
            )
        }
        "pop-toggle" => {
            // Mirror Omarchy 4.0.4's omarchy-hyprland-window-pop semantics, but
            // keep every operation address-scoped so invoking it from a taskbar
            // menu can never act on whichever window happened to become active.
            let client = client_by_address(address)?;
            if has_tag(&client, "pop") {
                if client.pinned {
                    set_pin(address, false)?;
                }
                if client.floating {
                    set_floating(address, false)?;
                    wait_for_floating(address, false)?;
                }
                tag(address, "-pop")?;
            } else {
                if client.floating || client.pinned || client.fullscreen != 0 || client.fullscreen_client != 0 {
                    bail!("pop-out requires a tiled, unpinned, non-fullscreen window");
                }
                set_floating(address, true)?;
                wait_for_floating(address, true)?;
                resize(address, 1300, 900)?;
                center(address)?;
                set_pin(address, true)?;
                alter_zorder_top(address)?;
                tag(address, "+pop")?;
            }
            return Ok(());
        }
        "float-pin" | "float-pin-toggle" => {
            let client = client_by_address(address)?;
            if client.pinned {
                set_pin(address, false)?;
                set_floating(address, false)?;
            } else {
                set_floating(address, true)?;
                set_pin(address, true)?;
                alter_zorder_top(address)?;
            }
            return Ok(());
        }
        _ => bail!("unsupported window action: {action}"),
    };

    dispatch(&expression)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_exact_addresses() {
        assert_eq!(normalize_address("0xAbC123").unwrap(), "0xabc123");
        assert_eq!(normalize_address("abc123").unwrap(), "0xabc123");
        assert!(normalize_address("address:0xabc").is_err());
        assert!(normalize_address("window title").is_err());
    }

    #[test]
    fn escapes_lua_strings() {
        assert_eq!(lua_string("a\"b\\c"), "\"a\\\"b\\\\c\"");
    }

    #[test]
    fn recognizes_static_or_dynamic_pop_tag() {
        let mut client = Client::default();
        assert!(!has_tag(&client, "pop"));
        client.tags = vec!["other".into(), "pop".into()];
        assert!(has_tag(&client, "pop"));
        client.tags = vec!["pop*".into()];
        assert!(has_tag(&client, "pop"));
    }
}
