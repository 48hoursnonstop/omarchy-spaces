# Changelog

## 1.1.2 (fork)

- Release the 1.1.0 interface with Show Desktop as a narrow strip touching the far right screen edge (bottom edge for vertical bars).
- Disable the in-workspace desktop button by default and remove empty layout columns when controls or overflow are hidden.
- Install and uninstall the separate strip together with Spaces. Keep Hyprbars, transactional window controls, previews, pins and recovery from 1.1.0.
- This release follows the `fix/v1-desktop-corner` branch, not the separate appearance changes on `feature/window-controls`.

## 1.1.0 (fork)

- Hyprbars is included in normal installation and required by the final health check; titlebar double-click uses the same exact-address action helper as its buttons.
- Installation records and replaces the original workspace widget's placement. Failure rolls back the bar and managed titlebar integration.
- Clean uninstall restores hidden windows and the previous workspace widget, removes Spaces source/runtime/preferences/settings/hooks, preserves unrelated settings and shared Hyprbars resources, and retains recovery data on failures. `--keep-settings` is available explicitly.
- Updates build a candidate before activation, follow the installed tracking branch and roll back source/helper on activation failure.
- Added lifecycle/rollback regressions and real nested Hyprland acceptance with official Hyprbars, real windows, native menu keyboard focus, preview capture, QML restart, two scaled monitors and recovery after monitor removal.

## 1.1.0-rc.1 (fork)

- Integrated transactional minimize/restore and Show desktop into workspace pills; minimized windows retain their original workspace and monitor.
- Added per-window, grouped-window, pinned-launcher and workspace menus using Omarchy's native controls, keyboard focus and scrolling.
- Added Pop out, window movement, scratchpad, maximize/fullscreen, floating, pinning, pseudo and group actions.
- Added closed-app launchers, AppLibrary identity and overrides, recovery controls and visible operation errors.
- Preserved live workspace previews and agent status; minimized windows get restore chips below previews and all overflow windows remain reachable.
- Added a protocol-checked Rust helper, namespaced restore state, install/update/recovery-aware uninstall scripts, optional Hyprbars controls and automated checks.
- Kept the original plugin ID, settings and agent-hook IPC. This is a release candidate; see `docs/verification.md` for coverage and remaining live-session checks.

## 1.0.0

First stable release, ready for the Omarchy plugin marketplace.

- The plugin ID is now `tornikegomareli.spaces`, matching the repository owner.
  If you installed an earlier version, remove `insanearts.spaces`, add the plugin
  again, and update the hook paths in `~/.claude/settings.json`.
- README: screenshots from the product film, requirements, and update and
  removal instructions
- Marketplace preview image
- Verified with the bar on the top, bottom, left and right edges

## 0.3.0

- Agent status: terminals running Claude Code show a spinner while the agent
  works, a pulsing `!` when it needs input, and a check mark when it is done.
  Workspaces with a waiting agent pulse
- `hooks/claude-hook` reports agent state; see the README for setup
- Setting to turn agent status off

## 0.2.0

- Live workspace previews: hover another workspace to see a miniature of it,
  with each window where it really is. Click a window to jump to it
- The preview slides between workspaces as you move along the bar
- Hovering an app icon highlights its window in the preview
- `peek` command to open a preview from a keybinding:
  `omarchy-shell insanearts.spaces peek 3`
- Settings: turn previews on or off, preview size, live video or still frame
- Icons for apps with reverse-DNS ids, such as `dev.example.tool`
- Fix: workspaces could stay half faded after appearing

## 0.1.0

First release.

- Workspace pills that show the icons of the apps open on each workspace
- The active workspace slides open; the focused window is highlighted
- Click a workspace or an icon to focus it; scroll to switch workspaces
- Settings panel: when icons show, icon style and size, grouping by app,
  active style, labels, density, urgent highlights, tooltips, animations
- Icons for Chromium web apps and apps missing from the icon theme
