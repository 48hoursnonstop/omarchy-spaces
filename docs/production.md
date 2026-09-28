# Spaces 1.1.1: installation, updates and clean removal

Supported baseline: Omarchy 4.0.4, Quickshell 0.3.1 and Hyprland 0.56.x with Lua configuration. Hyprbars is part of the standard installation. It is built/loaded through the official `hyprpm` repository so its ABI matches the running compositor; the release does not ship a generic precompiled Hyprbars library.

## Install

Required commands: `omarchy`, `omarchy-shell`, `hyprctl`, `hyprpm`, `jq`, Python 3, Cargo and Rust 1.89+. A first Hyprbars build also requires Git, cpio, CMake, Meson, GCC and Make. Install dependencies through your normal Omarchy package workflow before running the installer.

For a fresh installation:

```sh
git clone --branch feature/window-controls https://github.com/48hoursnonstop/omarchy-spaces.git \
  ~/.config/omarchy/plugins/tornikegomareli.spaces
~/.config/omarchy/plugins/tornikegomareli.spaces/scripts/install.sh
```

If Spaces is already installed, switch that checkout to this fork/branch first. Do not clone over it. If workspace-taskbar is installed, restore its hidden windows and remove its titlebar integration before replacing it. The two plugins have independent journals; Spaces does not guess another plugin's restoration metadata.

The installer checks compatibility, compiles outside the watched source directory, installs the helper atomically, configures official Hyprbars and records the workspace switcher's original placement. Spaces replaces that widget in place and adds a narrow show-desktop strip as the last right-hand bar entry. Existing Spaces settings are retained on repeat installation. Success requires a healthy service, compatible helper, clean compositor configuration and loaded titlebars.

If first-time activation fails, the installer rolls back the managed titlebar changes and previous bar entries. It retains the checkout, helper and installation/recovery state for retry or a clean uninstall. An interrupted installation does not discard its ownership journal.

## Check and update

```sh
~/.config/omarchy/plugins/tornikegomareli.spaces/scripts/doctor.sh
~/.config/omarchy/plugins/tornikegomareli.spaces/scripts/update.sh
```

The updater follows the checkout's configured remote branch. It rejects local modifications and non-fast-forward history, builds the candidate in staging, then updates source, helper and managed titlebar configuration together. Failed activation restores the previous source/helper and retains the restore journal. A compositor update that changes the Hyprbars ABI should be followed by `install.sh` to refresh the official plugin and rerun health checks.

## Clean uninstall

```sh
~/.config/omarchy/plugins/tornikegomareli.spaces/scripts/uninstall.sh --yes
```

This removes:

- The installed source directory, or just its link when using a development checkout.
- Spaces entries/settings and the separate desktop strip in `shell.json`, restoring the prior built-in workspace widget placement/settings without reverting other bar changes.
- The managed `spaces-hyprbars.lua` file and its marked import in `hyprland.lua`.
- Helper binaries, build cache, installation metadata, recovery journal and Spaces preferences.
- Exact Spaces command hooks from Claude's `settings.json`, preserving other hooks and settings.

Hyprbars is disabled and its official repository removed only when Spaces installed/enabled them and no other configuration/plugins use them. Existing shared installations are retained. No backup copy of the source is created. Dotfile symlinks are preserved.

Uninstall first stops UI/titlebar requests, restores hidden windows and verifies that no restore records or hidden clients remain. Any failed recovery, reload, query or managed-file ownership check stops removal with data available for retry. The empty runtime lock inode intentionally remains until logout, preventing old processes from acquiring a different lock after removal; it contains no preferences or restore records.

Use `uninstall.sh --yes --keep-settings` to preserve application pins and overrides explicitly. The installer creates no keybindings; remove any custom bindings you added manually. Standard package dependencies are not uninstalled because they may be used by other applications.

## Emergency recovery

```sh
~/.local/share/tornikegomareli.spaces/bin/spaces-backend --protocol 6 recover
```

If recovery reports an error, keep the restore journal and correct the reported condition before retrying. Select a normal workspace before recovering windows whose journal entry is missing; they are rescued there because their original location cannot be reconstructed.

The [verification report](verification.md) records automated coverage, real compositor acceptance and remaining hardware-specific checks.
