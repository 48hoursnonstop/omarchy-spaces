.pragma library

// Pure helpers for the Spaces widget. Nothing here touches QML
// objects beyond plain property reads, so the logic can be exercised with
// node (see tests/model.test.js).

var DEFAULTS = {
  showIcons: true,            // master switch: app icons visible or hidden
  showApps: "hover",          // "all" | "active" | "hover" (active + hovered) | "hoverOnly"
  persistentWorkspaces: 5,    // workspaces 1..N are always shown
  hideEmpty: false,           // hide empty workspaces, even persistent ones
  perMonitor: false,          // only list workspaces on this bar's monitor
  iconSize: 16,
  maxIcons: 8,                // overflow collapses into a "+N" chip
  groupApps: false,           // one icon per app, with a window count
  dimUnfocused: true,         // dim other windows on the active workspace
  focusedTitle: false,        // show the focused window's title next to its icon
  titleLength: 24,
  activeStyle: "subtle",      // "subtle" | "solid" | "accent"
  labelStyle: "number",       // "number" | "glyph" | "none"
  animations: true,
  animationSpeed: "normal",   // "slow" | "normal" | "fast"
  scrollSwitch: true,
  iconStyle: "color",         // "color" | "mono"
  urgentHighlight: true,      // pulse workspaces whose windows ask for attention
  middleClickClose: false,    // middle-click an icon closes that window
  tooltips: true,
  density: "normal",          // "compact" | "normal" | "roomy"
  activeClick: "none",        // clicking the active pill: "none" | "previous"
  settingsButton: "hover",    // gear button: "hover" | "always" | "never"
  previews: true,             // live preview of a workspace on hover
  previewSize: "medium",      // "small" | "medium" | "large"
  previewLive: true,          // keep previews streaming; false = one frame
  agentStatus: true,          // badges for coding agents running in terminals
  minimizeOnClick: true,
  desktopButton: false
}

var SHOW_APPS = ["all", "active", "hover", "hoverOnly"]
var ICON_STYLES = ["color", "mono"]
var DENSITIES = ["compact", "normal", "roomy"]
var ACTIVE_CLICKS = ["none", "previous"]
var SETTINGS_BUTTONS = ["hover", "always", "never"]
var PREVIEW_SIZES = ["small", "medium", "large"]
var ACTIVE_STYLES = ["subtle", "solid", "accent"]
var LABEL_STYLES = ["number", "glyph", "none"]
var SPEEDS = ["slow", "normal", "fast"]

function clampInt(value, min, max, fallback) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

function oneOf(value, allowed, fallback) {
  return allowed.indexOf(String(value)) !== -1 ? String(value) : fallback
}

function bool(value, fallback) {
  return typeof value === "boolean" ? value : fallback
}

// Normalizes a raw shell.json entry into a complete, valid settings object.
function resolveSettings(raw) {
  var s = raw || {}
  var d = DEFAULTS
  return {
    showIcons: bool(s.showIcons, d.showIcons),
    showApps: oneOf(s.showApps, SHOW_APPS, d.showApps),
    persistentWorkspaces: clampInt(s.persistentWorkspaces, 0, 10, d.persistentWorkspaces),
    hideEmpty: bool(s.hideEmpty, d.hideEmpty),
    perMonitor: bool(s.perMonitor, d.perMonitor),
    iconSize: clampInt(s.iconSize, 12, 24, d.iconSize),
    maxIcons: clampInt(s.maxIcons, 1, 20, d.maxIcons),
    groupApps: bool(s.groupApps, d.groupApps),
    dimUnfocused: bool(s.dimUnfocused, d.dimUnfocused),
    focusedTitle: bool(s.focusedTitle, d.focusedTitle),
    titleLength: clampInt(s.titleLength, 8, 60, d.titleLength),
    activeStyle: oneOf(s.activeStyle, ACTIVE_STYLES, d.activeStyle),
    labelStyle: oneOf(s.labelStyle, LABEL_STYLES, d.labelStyle),
    animations: bool(s.animations, d.animations),
    animationSpeed: oneOf(s.animationSpeed, SPEEDS, d.animationSpeed),
    scrollSwitch: bool(s.scrollSwitch, d.scrollSwitch),
    iconStyle: oneOf(s.iconStyle, ICON_STYLES, d.iconStyle),
    urgentHighlight: bool(s.urgentHighlight, d.urgentHighlight),
    middleClickClose: bool(s.middleClickClose, d.middleClickClose),
    tooltips: bool(s.tooltips, d.tooltips),
    density: oneOf(s.density, DENSITIES, d.density),
    activeClick: oneOf(s.activeClick, ACTIVE_CLICKS, d.activeClick),
    settingsButton: oneOf(s.settingsButton, SETTINGS_BUTTONS, d.settingsButton),
    previews: bool(s.previews, d.previews),
    previewSize: oneOf(s.previewSize, PREVIEW_SIZES, d.previewSize),
    previewLive: bool(s.previewLive, d.previewLive),
    agentStatus: bool(s.agentStatus, d.agentStatus),
    minimizeOnClick: bool(s.minimizeOnClick, d.minimizeOnClick),
    desktopButton: bool(s.desktopButton, d.desktopButton)
  }
}

function durationFor(settings, base) {
  if (!settings.animations) return 0
  var factor = settings.animationSpeed === "slow" ? 1.6 : (settings.animationSpeed === "fast" ? 0.55 : 1)
  return Math.round(base * factor)
}

// Whether a workspace pill should reveal its app icons.
function showsApps(settings, occupied, active, hovered) {
  if (!settings.showIcons || !occupied) return false
  switch (settings.showApps) {
  case "all": return true
  case "active": return active
  case "hoverOnly": return hovered
  default: return active || hovered
  }
}

// Spacing between pills and inside them, in unscaled px.
function densityMetrics(density) {
  if (density === "compact") return { gap: 2, pad: 5, iconGap: 1 }
  if (density === "roomy") return { gap: 7, pad: 10, iconGap: 5 }
  return { gap: 4, pad: 7, iconGap: 3 }
}

// Hyprland reports addresses with or without the 0x prefix depending on source.
function normalizeAddress(address) {
  return String(address || "").toLowerCase().replace(/^0x/, "")
}

// Workspace ids to render. `occupied` maps id -> window count for every
// normal (positive id) workspace Hyprland knows about. `activeIds` are
// workspaces that must stay visible even when empty (focused / on-screen).
function workspaceIds(occupied, activeIds, persistent, hideEmpty) {
  var ids = []
  function add(id) {
    if (id !== 0 && isFinite(id) && ids.indexOf(id) === -1) ids.push(id)
  }

  if (!hideEmpty) for (var p = 1; p <= persistent; p++) add(p)
  for (var key in occupied) {
    var id = Number(key)
    if (occupied[key] > 0 || !hideEmpty) add(id)
  }
  for (var a = 0; a < activeIds.length; a++) add(activeIds[a])

  ids.sort(function(l, r) { return (l > 0 && r < 0) ? -1 : (l < 0 && r > 0) ? 1 : l - r })
  return ids
}

// Label text for a workspace pill.
function workspaceLabel(id, focused, style, name) {
  if (style === "none") return ""
  if (id < 0) return String(name || "special").replace(/^special:/, "").slice(0, 1).toUpperCase()
  if (style === "glyph" && focused) return "󱓻"
  return id === 10 ? "0" : String(id)
}

// Stable key identifying "the same app" across windows.
function appKey(appId) {
  return String(appId || "").toLowerCase()
}

// Orders windows the way they sit on screen: left to right, then top to
// bottom. Windows without a known position keep their relative order.
function sortWindows(windows) {
  var indexed = windows.map(function(w, i) { return { w: w, i: i } })
  indexed.sort(function(l, r) {
    var la = l.w.at, ra = r.w.at
    if (la && ra) {
      if (la[0] !== ra[0]) return la[0] - ra[0]
      if (la[1] !== ra[1]) return la[1] - ra[1]
    } else if (la && !ra) {
      return -1
    } else if (!la && ra) {
      return 1
    }
    return l.i - r.i
  })
  return indexed.map(function(x) { return x.w })
}

// Turns a sorted window list into render items.
//   windows: [{ address, appId, title, focused }]
// Returns { items: [{ key, address, appId, title, focused, count }], overflow }
function iconItems(windows, groupApps, maxIcons) {
  var items = []
  if (groupApps) {
    var byApp = {}
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      var k = appKey(w.appId) || w.address
      var existing = byApp[k]
      if (!existing) {
        existing = windowItem(w, k)
        byApp[k] = existing
        items.push(existing)
      } else {
        existing.count++
        existing.addresses.push(w.address)
        existing.minimizedCount += w.minimized ? 1 : 0
        existing.busy = existing.busy || !!w.busy
        existing.popped = existing.popped || !!w.popped
        if (w.focused || (existing.minimized && !w.minimized)) {
          existing.address = w.address
          existing.title = w.title
          existing.focused = !!w.focused
        }
        existing.minimized = existing.minimizedCount === existing.count
      }
    }
  } else {
    for (var j = 0; j < windows.length; j++) {
      var x = windows[j]
      items.push(windowItem(x, x.address))
    }
  }

  var overflow = Math.max(0, items.length - maxIcons)
  if (overflow > 0) {
    // Never hide the focused window behind the overflow chip.
    var visible = items.slice(0, maxIcons)
    var focusedIdx = -1
    for (var f = maxIcons; f < items.length; f++) if (items[f].focused) focusedIdx = f
    if (focusedIdx !== -1) visible[visible.length - 1] = items[focusedIdx]
    items = visible
  }
  return { items: items, overflow: overflow }
}

function windowItem(w, key) {
  return {
    key: key, address: w.address, appId: w.appId, desktopId: w.desktopId || "",
    title: w.title, focused: !!w.focused, count: 1, addresses: [w.address],
    minimized: !!w.minimized, minimizedCount: w.minimized ? 1 : 0,
    busy: !!w.busy, popped: !!w.popped
  }
}

// Project service rows onto workspace pills, including workspaces Hyprland
// removed after their last window was minimized. Hidden clients keep their
// original workspace and monitor through the restore journal.
function projectWorkspaces(workspaces, windows, monitorId, perMonitor) {
  var map = {}, metadata = {}
  for (var i = 0; i < workspaces.length; i++) {
    var ws = workspaces[i]
    metadata[ws.id] = ws
    if (ws.id > 0 && (!perMonitor || ws.monitorId === monitorId))
      map[ws.id] = { id: ws.id, name: ws.name, windows: [], area: ws.area }
  }
  for (var j = 0; j < windows.length; j++) {
    var w = windows[j]
    if (!w.workspace || w.workspaceName === "special:omarchy-spaces-minimized") continue
    var meta = metadata[w.workspace]
    var owner = meta ? meta.monitorId : w.monitorId
    if (perMonitor && owner >= 0 && owner !== monitorId) continue
    if (!map[w.workspace]) map[w.workspace] = {
      id: w.workspace, name: w.workspaceName, windows: [], area: meta ? meta.area : null
    }
    map[w.workspace].windows.push(w)
  }
  for (var id in map) map[id].windows = sortWindows(map[id].windows)
  return map
}

function desktopHidden(windows) {
  return windows.some(function(w) { return !!w.desktopBatch })
}

function truncate(text, max) {
  var t = String(text || "")
  return t.length > max ? t.slice(0, Math.max(1, max - 1)) + "…" : t
}

// Title shown next to the focused icon. The app name when
// the app has a single window in the workspace, else the window title.
function focusedLabel(item, appName, maxLength) {
  if (!item || !item.focused) return ""
  var text = item.count > 1 || !appName ? item.title : appName
  return truncate(text, maxLength)
}

// Width of the workspace miniature, in unscaled px.
function previewWidth(size) {
  if (size === "small") return 260
  if (size === "large") return 520
  return 380
}

// Usable area of a monitor in logical layout coordinates, i.e. without the
// space reserved by bars. `monitor`: { x, y, width, height, scale, reserved }
// where width/height are physical pixels and reserved is [l, t, r, b].
function monitorArea(monitor) {
  if (!monitor || !monitor.width || !monitor.height) return null
  var scale = monitor.scale > 0 ? monitor.scale : 1
  var r = monitor.reserved && monitor.reserved.length === 4 ? monitor.reserved : [0, 0, 0, 0]
  var w = monitor.width / scale
  var h = monitor.height / scale
  return {
    x: (monitor.x || 0) + r[0],
    y: (monitor.y || 0) + r[1],
    width: Math.max(1, w - r[0] - r[2]),
    height: Math.max(1, h - r[1] - r[3])
  }
}

// Places windows inside a width x height miniature of `area`, where they
// really are on screen. Floating windows come last so they draw on top.
// Windows without a known position are laid out in an even grid instead.
//   windows: [{ address, at: [x, y] | null, size: [w, h] | null, floating }]
function previewLayout(windows, area, width, height) {
  var placed = []
  var known = area && windows.length > 0 && windows.every(function(w) { return w.at && w.size })

  if (known) {
    var sx = width / area.width
    var sy = height / area.height
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      var x = (w.at[0] - area.x) * sx
      var y = (w.at[1] - area.y) * sy
      var ww = w.size[0] * sx
      var hh = w.size[1] * sy
      // Clamp into the miniature; windows can hang off the edge.
      var cx = Math.max(0, Math.min(width - 4, x))
      var cy = Math.max(0, Math.min(height - 4, y))
      placed.push({
        address: w.address,
        x: cx, y: cy,
        width: Math.max(4, Math.min(width - cx, ww - (cx - x))),
        height: Math.max(4, Math.min(height - cy, hh - (cy - y))),
        floating: !!w.floating
      })
    }
  } else {
    var n = windows.length
    var cols = Math.max(1, Math.ceil(Math.sqrt(n)))
    var rows = Math.max(1, Math.ceil(n / cols))
    var gap = 4
    var cw = (width - gap * (cols - 1)) / cols
    var ch = (height - gap * (rows - 1)) / rows
    for (var j = 0; j < n; j++) {
      placed.push({
        address: windows[j].address,
        x: (j % cols) * (cw + gap), y: Math.floor(j / cols) * (ch + gap),
        width: cw, height: ch,
        floating: false
      })
    }
  }

  placed.sort(function(l, r) { return (l.floating ? 1 : 0) - (r.floating ? 1 : 0) })
  return placed
}

// Maps window PIDs to agent states. `agents`: { session: { state, pids } }
// where pids run from the agent up to init. The nearest ancestor that is a
// window owns the agent, since terminals can be nested in other terminals.
// When several agents share a window, "waiting" beats "working" beats "done".
var AGENT_RANK = { waiting: 3, working: 2, done: 1 }

function agentStates(agents, windowPids) {
  var out = {}
  for (var session in agents) {
    var agent = agents[session]
    var rank = AGENT_RANK[agent.state] || 0
    if (!rank) continue
    for (var i = 0; i < agent.pids.length; i++) {
      var pid = agent.pids[i]
      if (!windowPids[pid]) continue
      if (!out[pid] || AGENT_RANK[out[pid]] < rank) out[pid] = agent.state
      break
    }
  }
  return out
}

function parsePids(csv) {
  return String(csv || "").split(",").map(function(v) { return Number(v) }).filter(function(n) { return n > 1 })
}

// Next workspace id when scrolling; wraps around.
function stepWorkspace(ids, current, delta) {
  if (!ids.length) return current
  var idx = ids.indexOf(current)
  if (idx === -1) return ids[0]
  var next = (idx + (delta > 0 ? 1 : -1) + ids.length) % ids.length
  return ids[next]
}

// Merges a settings delta into an entry for shell.json.
function mergedEntry(moduleName, current, delta) {
  var entry = { id: moduleName }
  for (var k in current) if (k !== "id") entry[k] = current[k]
  for (var d in delta) entry[d] = delta[d]
  return entry
}

// node / CommonJS export for tests; ignored by QML.
if (typeof module !== "undefined") {
  module.exports = {
    DEFAULTS: DEFAULTS, resolveSettings: resolveSettings, showsApps: showsApps,
    densityMetrics: densityMetrics, normalizeAddress: normalizeAddress,
    agentStates: agentStates, parsePids: parsePids,
    previewWidth: previewWidth, monitorArea: monitorArea, previewLayout: previewLayout, durationFor: durationFor,
    workspaceIds: workspaceIds, workspaceLabel: workspaceLabel, appKey: appKey,
    sortWindows: sortWindows, iconItems: iconItems, truncate: truncate,
    focusedLabel: focusedLabel,
    stepWorkspace: stepWorkspace, mergedEntry: mergedEntry,
    projectWorkspaces: projectWorkspaces, desktopHidden: desktopHidden
  }
}
