# Window controls integration: verification

Reviewed on 2026-09-27. Release candidate: **1.1.0-rc.1**, helper **0.9.0**, protocol **6**, state schema **1**.

The integration starts from Spaces `f8306d763c7b3c89d24172edb0e68fb6dacb68a9` (1.0.0) and adapts the window-control implementation from workspace-taskbar `c9e6165beab567a73b300dd485768c3ce8cb73cc` (0.14.0-rc.2). Both MIT notices are preserved.

## Design and ownership

Spaces keeps its existing plugin ID, workspace pills, live spatial preview, settings and agent IPC. A shared service owns AppLibrary identity, pins and the serialized helper queue. Each bar projects that service onto its own workspace model and owns its preview anchor. Native menus receive the service directly and anchor to the bar that opened them.

The journal restores a minimized window's workspace and monitor identity into the model even if Hyprland has removed its now-empty workspace. The private hidden workspace never becomes a user-facing pill. Manually minimized windows and Show desktop batches remain distinct. Workspaces moved to another monitor use current compositor metadata before saved monitor metadata.

Window operations use the ported one-shot helper and its transactional journal, exclusive process lock, compatibility guard and recovery logic. Helper/data/state/config paths use the `tornikegomareli.spaces` namespace, and hidden windows use `special:omarchy-spaces-minimized`. There is no automatic migration from workspace-taskbar. Optional Hyprbars setup refuses a simultaneous workspace-taskbar titlebar integration.

## Checks performed

Environment: Omarchy 4.0.4-1, Hyprland 0.56.2-2, Quickshell 0.3.1-1. The reviewed public host files match the hashes in `compat/upstream.json`.

| Check | Result and scope |
| --- | --- |
| Rust format, Clippy with warnings denied, release build | Passed |
| Rust unit tests | 3 passed: exact addresses, Lua escaping, Pop tags |
| Transaction tests | 18 passed against a mocked compositor: journal ordering, failures/retry, groups, desktop batches, workspace-scoped restore, saved monitor metadata, foreign-state isolation and recovery |
| Lifecycle tests | 8 passed using isolated command fixtures for install, update and recovery-aware uninstall |
| Model tests | 25 passed: original settings/layout/agent behavior plus minimized workspace projection, monitor reassignment, special workspace visibility, grouped minimized state and desktop batches |
| App matcher and optional Hyprbars smoke checks | Passed, including idempotent setup/removal and action wrapper behavior |
| Bash syntax and ShellCheck | Passed for scripts, smoke tests and the agent hook |
| Manifest and QML lint | Passed; dynamic host members are informational because their public facades lack full static type metadata |
| Real service QML runtime | Passed with an isolated helper fixture: AppLibrary matching, pin persistence, no duplicate launchers, batch/group busy state, actual Process completion, failed operations and error retention |
| Graphical QML runtime | Passed in a separate headless labwc compositor: top/bottom/left/right bar layouts, window/workspace/group menus, minimized preview state, keyboard selection/dismissal, a 45-window scrolling chooser, disabled actions when the helper is unavailable |

`tests/qml/ui.test.py` uses the real Spaces components and installed native Omarchy UI components, with fixture window data. `wtype` sends actual Wayland key events. The fixture holds the native panel's exclusive focus prime while testing because headless labwc has no physical keyboard seat; this does **not** certify Hyprland's exclusive-to-on-demand focus handoff. No fake window controls dispatch into the user's compositor.

The graphical fixture deliberately has no Hyprland IPC connection or captured application surfaces. Expected logs mention unavailable Hyprland IPC and software-rendering buffer fallback. It does not exercise real preview video, active-workspace styling driven by a live compositor, or real application window movement. It fails on QML TypeError, ReferenceError, binding loops, invalid assignments, failed assertions or incomplete screenshots.

## Reproduce

See the test commands in the README. `scripts/check-qml.sh` and the QML runtime tests require Omarchy/Quickshell; the transaction, model, matcher and lifecycle tests also run in CI without a live desktop.

For retained graphical artifacts outside the watched plugin source:

```sh
SPACES_UI_ARTIFACTS="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-spaces-dev/ui" \
  python3 tests/qml/ui.test.py
```

The runner finds `labwc` on PATH, or accepts a binary path through `SPACES_TEST_LABWC`. It creates its own runtime directory, socket and XDG directories and terminates its compositor afterward. Test screenshots are synthetic fixtures, not evidence of a production deployment.

## Remaining live-session release checks

- Install the fork and helper in a disposable Omarchy session; verify reload and restart while windows are minimized and while an operation is pending.
- Exercise real Wayland and XWayland windows: minimize/restore, grouped windows, Show desktop, floating geometry, fullscreen, Pop out, scratchpad, close and recovery after interruption. Exact tiled-tree reconstruction is outside the implementation's guarantee.
- Check real preview capture and native keyboard focus on open, immediate reopen and outside-click dismissal.
- Check physical multiple monitors, mixed scaling, per-monitor filtering, workspace migration and monitor removal with minimized windows.
- Exercise the optional official Hyprbars integration against the running compositor ABI.

The user's installed bar and compositor configuration were not changed during this development pass. The implementation and automated checks are ready for that live-session validation; this document does not claim the remaining release matrix has passed.
