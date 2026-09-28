# Window controls integration: verification

Reviewed on 2026-09-27. Release: **1.1.0**, helper **0.9.0**, protocol **6**, state schema **1**.

The integration starts from Spaces `f8306d763c7b3c89d24172edb0e68fb6dacb68a9` (1.0.0) and adapts the window-control implementation from workspace-taskbar `c9e6165beab567a73b300dd485768c3ce8cb73cc` (0.14.0-rc.2). Both MIT notices are preserved.

## Design and ownership

Spaces keeps its existing plugin ID, workspace pills, live spatial preview, settings and agent IPC. A shared service owns AppLibrary identity for actions/pins and the serialized helper queue. Workspace icon presentation uses the original Spaces desktop-entry/icon resolver. Each bar projects that service onto its own workspace model and owns its preview anchor. Native menus receive the service directly and anchor to the bar that opened them.

The journal restores a minimized window's workspace and monitor identity into the model even if Hyprland has removed its now-empty workspace. The private hidden workspace never becomes a user-facing pill. Manually minimized windows and Show desktop batches remain distinct. Workspaces moved to another monitor use current compositor metadata before saved monitor metadata.

Window operations use the ported one-shot helper and its transactional journal, exclusive process lock, compatibility guard and recovery logic. Helper/data/state/config paths use the `tornikegomareli.spaces` namespace, and hidden windows use `special:omarchy-spaces-minimized`. There is no automatic migration from workspace-taskbar. Hyprbars is included in installation; setup refuses a competing titlebar configuration.

## Checks performed

Environment: Omarchy 4.0.4-1, Hyprland 0.56.2-2, Quickshell 0.3.1-1. The reviewed public host files match the hashes in `compat/upstream.json`.

| Check | Result and scope |
| --- | --- |
| Rust format, Clippy with warnings denied, release build | Passed |
| Rust unit tests | 3 passed: exact addresses, Lua escaping, Pop tags |
| Transaction tests | 18 passed against a mocked compositor: journal ordering, failures/retry, groups, desktop batches, workspace-scoped restore, saved monitor metadata, foreign-state isolation and recovery |
| Lifecycle tests | 16 passed using isolated command fixtures: required Hyprbars installation, activation rollback, repeated install, complete removal, explicit preference retention, recovery failures, unrelated settings/hooks and dotfile/development symlinks |
| Update tests | 4 passed against real temporary Git repositories: tracking branch selection, staging failures, source/helper rollback and preservation of local edits |
| Model tests | 25 passed: original settings/layout/agent behavior plus minimized workspace projection, monitor reassignment, special workspace visibility, grouped minimized state and desktop batches |
| App matcher and Hyprbars smoke checks | Passed: idempotent setup/removal, action wrapper behavior, pre-existing ownership, failed removal/retry, foreign config detection and failed compositor queries |
| Bash syntax and ShellCheck | Passed for scripts, smoke tests and the agent hook |
| Manifest and QML lint | Passed; dynamic host members are informational because their public facades lack full static type metadata |
| Real service QML runtime | Passed with an isolated helper fixture: AppLibrary matching, pin persistence, no duplicate launchers, batch/group busy state, actual Process completion, failed operations and error retention |
| Graphical QML runtime | Passed in a separate headless labwc compositor: top/bottom/left/right bar layouts, window/workspace/group menus, minimized preview state, keyboard selection/dismissal, a 45-window scrolling chooser, disabled actions when the helper is unavailable |
| Real Hyprland + Hyprbars acceptance | Passed with three real Foot windows: official plugin load/reload/unload and clean Lua config, QML minimize/restore and restart with a minimized window, workspace projection, native keyboard focus/reopen/Escape, live preview capture, titlebar action helper, maximization, desktop batches, Pop, scratchpad, two virtual monitors with mixed scale, restore on the second monitor and recovery after its removal |

`tests/qml/ui.test.py` uses the real Spaces components and installed native Omarchy UI components, with fixture window data. `wtype` sends actual Wayland key events. The fixture holds the native panel's exclusive focus prime while testing because headless labwc has no physical keyboard seat; this does **not** certify Hyprland's exclusive-to-on-demand focus handoff. No fake window controls dispatch into the user's compositor.

The graphical fixture deliberately has no Hyprland IPC connection or captured application surfaces. Expected logs mention unavailable Hyprland IPC and software-rendering buffer fallback. It does not exercise real preview video, active-workspace styling driven by a live compositor, or real application window movement. It fails on QML TypeError, ReferenceError, binding loops, invalid assignments, failed assertions or incomplete screenshots.

The separate `tests/qml/hyprland.test.py` suite closes those gaps with real Hyprland 0.56.2 nested inside a headless labwc. It loads the official Hyprbars build from commit `7644cecdb947060682891a0db2a0cdc5c0b9e704`, pinned by upstream for this compositor ABI. It runs the real service, widget, menu, helper and native Omarchy UI components. Only the host's application catalog is a small fixture. Native focus priming is unmodified; a persistent virtual keyboard provides a seat before panels open. Both initial and restarted Quickshell runs had no QML runtime warnings/errors.

## Reproduce

See the test commands in the README. `scripts/check-qml.sh` and the QML runtime tests require Omarchy/Quickshell; the transaction, model, matcher and lifecycle tests also run in CI without a live desktop.

For retained graphical artifacts outside the watched plugin source:

```sh
SPACES_UI_ARTIFACTS="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-spaces-dev/ui" \
  python3 tests/qml/ui.test.py
```

The runner finds `labwc` on PATH, or accepts a binary path through `SPACES_TEST_LABWC`. It creates its own runtime directory, socket and XDG directories and terminates its compositor afterward. Test screenshots are synthetic fixtures, not evidence of a production deployment.

For the real compositor suite, build official Hyprbars against the running Hyprland headers, then run:

```sh
SPACES_TEST_BINARY="$CARGO_TARGET_DIR/release/spaces-backend" \
SPACES_TEST_HYPRBARS=/path/to/official/hyprbars.so \
SPACES_UI_ARTIFACTS="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-spaces-dev/acceptance" \
  python3 tests/qml/hyprland.test.py
```

This requires labwc, Hyprland, Foot, grim, wtype and GPU rendering. The runner isolates XDG/IPC, denies access to a physical input seat, prevents systemd environment propagation, stubs `hyprpm` only in the fixture (the official library is loaded directly), and terminates all child processes. It never starts another Omarchy shell on the user's compositor.

## Coverage limits

- Real acceptance used Wayland Foot windows. XWayland applications, application-specific fullscreen behavior, grouped-window interruption and physical monitor hotplug still need broader hardware/application coverage. Transaction failures/groups are covered by mocked-compositor tests.
- Installer/`hyprpm` ownership and rollback use isolated command fixtures; the real compositor suite directly loads the official ABI-matched library. A fresh download/build through `hyprpm` and complete Omarchy host registration were not run on the user's installed session.
- Real monitor movement/removal used virtual outputs, including 1.25 scaling. This is not certification for every physical multi-GPU or mixed-DPI configuration.
- Exact tiled-tree reconstruction is outside the implementation's guarantee. Custom user-written keybindings and shared system packages are not removed by uninstall.

The user's installed bar and compositor configuration were not changed during this preparation. The release is packaged for the supported baseline with the above coverage; no production deployment or universal hardware certification is claimed.

## 1.1.1 appearance correction

The normal workspace pills are compared against upstream commit `f8306d7` in the same isolated Hyprland session with the same real windows. Pixel comparisons pass for default, expanded and grouped/focused-title configurations. The original icon appearance animation and icon lookup are restored; added desktop buttons, preview toolbars and state rails are removed. Minimized windows use the existing spatial preview placeholders as restore targets.

`ShowDesktop.qml` is a custom QML bar entry appended after the final right-hand widget. Its narrow strip extends through Omarchy 4's eight-pixel trailing margin. On vertical bars it sits at the bottom. It calls Spaces' public IPC with the active workspace of its own monitor, sharing the existing batch journal. The live acceptance test exercises hide/restore through this component. Installation, update rollback and uninstall own only this entry and the existing Spaces placement; other bar entries are retained.

The real compositor test additionally requires ImageMagick (`magick compare`) for upstream pixel comparison. It runs in an isolated compositor, without re-enabling the plugin in the user's session.
