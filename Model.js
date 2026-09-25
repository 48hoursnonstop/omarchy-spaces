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
  settingsButton: "hover"     // gear button: "hover" | "always" | "never"
}

var SHOW_APPS = ["all", "active", "hover", "hoverOnly"]
var ICON_STYLES = ["color", "mono"]
var DENSITIES = ["compact", "normal", "roomy"]
var ACTIVE_CLICKS = ["none", "previous"]
var SETTINGS_BUTTONS = ["hover", "always", "never"]
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
    settingsButton: oneOf(s.settingsButton, SETTINGS_BUTTONS, d.settingsButton)
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
    if (id > 0 && ids.indexOf(id) === -1) ids.push(id)
  }

  if (!hideEmpty) for (var p = 1; p <= persistent; p++) add(p)
  for (var key in occupied) {
    var id = Number(key)
    if (occupied[key] > 0 || !hideEmpty) add(id)
  }
  for (var a = 0; a < activeIds.length; a++) add(activeIds[a])

  ids.sort(function(l, r) { return l - r })
  return ids
}

// Label text for a workspace pill.
function workspaceLabel(id, focused, style) {
  if (style === "none") return ""
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
        existing = { key: k, address: w.address, appId: w.appId, title: w.title, focused: w.focused, count: 1, addresses: [w.address] }
        byApp[k] = existing
        items.push(existing)
      } else {
        existing.count++
        existing.addresses.push(w.address)
        if (w.focused) {
          existing.focused = true
          existing.address = w.address
          existing.title = w.title
        }
      }
    }
  } else {
    for (var j = 0; j < windows.length; j++) {
      var x = windows[j]
      items.push({ key: x.address, address: x.address, appId: x.appId, title: x.title, focused: x.focused, count: 1, addresses: [x.address] })
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

// Chromium-family --app windows use classes like
// "chrome-web.whatsapp.com__-Default" or "brave-app.hey.com__-Profile_1".
// Returns the host ("web.whatsapp.com") or "" when the class is not one.
function webAppHost(appId) {
  var m = /^(?:chrome|chromium|brave|msedge|vivaldi|helium|opera)-([^_]+?)(?:__|_).*-(?:Default|Profile_\d+)$/i.exec(String(appId || ""))
  return m ? m[1] : ""
}

// Icon candidates scanned from disk: prefer scalable, then the largest raster.
function iconPathScore(path) {
  var p = String(path || "")
  if (/\.svg$/i.test(p)) return 100000
  var m = /\/(\d+)x\d+\//.exec(p)
  if (m) return Number(m[1])
  return /\/pixmaps\//.test(p) ? 48 : 1
}

function iconNameFromPath(path) {
  var value = String(path || "")
  var slash = value.lastIndexOf("/")
  var file = slash >= 0 ? value.slice(slash + 1) : value
  var dot = file.lastIndexOf(".")
  return dot > 0 ? file.slice(0, dot) : file
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
    densityMetrics: densityMetrics, normalizeAddress: normalizeAddress, durationFor: durationFor,
    workspaceIds: workspaceIds, workspaceLabel: workspaceLabel, appKey: appKey,
    sortWindows: sortWindows, iconItems: iconItems, truncate: truncate,
    focusedLabel: focusedLabel, webAppHost: webAppHost, iconPathScore: iconPathScore,
    iconNameFromPath: iconNameFromPath, stepWorkspace: stepWorkspace, mergedEntry: mergedEntry
  }
}
