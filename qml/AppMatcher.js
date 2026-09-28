function text(value) { return String(value || "").trim() }
function lower(value) { return text(value).toLowerCase() }

function safe(entry, name, fallback) {
  try {
    var value = entry ? entry[name] : undefined
    return value === undefined || value === null ? fallback : value
  } catch (e) {
    return fallback
  }
}

function stem(value) {
  var v = lower(value)
  if (v.slice(-8) === ".desktop") v = v.slice(0, -8)
  return v
}

function compact(value) {
  return stem(value).replace(/[^a-z0-9]+/g, "")
}

function basename(value) {
  var v = text(value)
  var slash = v.lastIndexOf("/")
  return slash >= 0 ? v.slice(slash + 1) : v
}

function commandName(entry) {
  try {
    var command = safe(entry, "command", [])
    if (command && command.length > 0) return basename(command[0])
  } catch (e) {}
  return ""
}

function startupClass(entry) {
  return text(safe(entry, "startupClass", safe(entry, "startupWmClass", "")))
}

function windowCandidates(win) {
  var values = [win.className, win.initialClass, win.appId]
  var out = []
  for (var i = 0; i < values.length; i++) {
    var candidate = compact(values[i])
    if (candidate && out.indexOf(candidate) < 0) out.push(candidate)
  }
  return out
}

function overrideKeys(win) {
  var values = [win.className, win.initialClass, win.appId]
  var out = []
  for (var i = 0; i < values.length; i++) {
    var raw = lower(values[i])
    var normalized = compact(values[i])
    if (raw && out.indexOf(raw) < 0) out.push(raw)
    if (normalized && out.indexOf(normalized) < 0) out.push(normalized)
  }
  return out
}

function overrideDesktopId(win, overrides) {
  if (!overrides) return ""
  var keys = overrideKeys(win)
  for (var i = 0; i < keys.length; i++) {
    var value = overrides[keys[i]]
    if (value !== undefined && value !== null && text(value)) return stem(value)
  }
  return ""
}

function entryById(rows, id) {
  var wanted = stem(id)
  if (!wanted) return null
  for (var i = 0; i < rows.length; i++) {
    var entry = rows[i] && rows[i].entry ? rows[i].entry : rows[i]
    if (stem(safe(entry, "id", "")) === wanted) return entry
  }
  return null
}

function steamAppId(win) {
  var fields = [lower(win.className), lower(win.initialClass), lower(win.appId)]
  for (var i = 0; i < fields.length; i++) {
    var match = fields[i].match(/steam[_-]app[_-](\d+)/)
    if (match) return match[1]
  }
  return ""
}

function execMentionsSteamId(exec, id) {
  if (!id) return false
  var value = lower(exec)
  if (value.indexOf("steam://rungameid/" + id) >= 0) return true
  if (new RegExp("(?:^|\\s)-applaunch\\s+" + id + "(?:\\s|$)").test(value)) return true
  return value.indexOf(id) >= 0 && value.indexOf("steam") >= 0
}

function execUrls(exec) {
  var value = text(exec)
  var matches = value.match(/https?:\/\/[^\s"']+/ig)
  return matches || []
}

function hostFromUrl(value) {
  var match = text(value).match(/^https?:\/\/([^\/:?#]+)/i)
  return match ? lower(match[1]).replace(/^www\./, "") : ""
}

function titleMentionsHost(title, host) {
  if (!title || !host) return false
  var haystack = lower(title).replace(/[^a-z0-9]+/g, " ")
  var labels = host.split(".")
  var ignored = { www: true, web: true, app: true, com: true, net: true, org: true, io: true, google: true }
  for (var i = 0; i < labels.length; i++) {
    var label = labels[i].replace(/[^a-z0-9]/g, "")
    if (label.length >= 3 && !ignored[label] && haystack.indexOf(label) >= 0) return true
  }
  return false
}

function isWebAppEntry(entry) {
  var exec = lower(safe(entry, "execString", ""))
  return exec.indexOf("omarchy-launch-webapp") >= 0 || /--app(?:=|\s+)https?:\/\//.test(exec)
}

function webAppScore(win, entry) {
  if (!isWebAppEntry(entry)) return -1

  var title = compact(win.title || win.initialTitle)
  var name = compact(safe(entry, "name", ""))
  if (title && name && (title === name || (name.length >= 3 && title.indexOf(name) >= 0))) return 1300

  var urls = execUrls(safe(entry, "execString", ""))
  for (var i = 0; i < urls.length; i++) {
    if (titleMentionsHost(win.title || win.initialTitle, hostFromUrl(urls[i]))) return 1250
  }

  return -1
}

function score(win, entry) {
  if (!entry) return -1

  var candidates = windowCandidates(win)
  var startup = compact(startupClass(entry))
  var id = compact(safe(entry, "id", ""))
  var command = compact(commandName(entry))
  var name = compact(safe(entry, "name", ""))
  var best = webAppScore(win, entry)

  for (var i = 0; i < candidates.length; i++) {
    var candidate = candidates[i]
    if (startup && candidate === startup) best = Math.max(best, 1000)
    if (id && candidate === id) best = Math.max(best, 940)
    if (command && candidate === command) best = Math.max(best, 840)
    if (id && candidate.length >= 4 && (id.indexOf(candidate) >= 0 || candidate.indexOf(id) >= 0)) best = Math.max(best, 700)
    if (startup && candidate.length >= 4 && (startup.indexOf(candidate) >= 0 || candidate.indexOf(startup) >= 0)) best = Math.max(best, 680)
    if (name && candidate === name) best = Math.max(best, 630)
  }

  var exec = lower(safe(entry, "execString", ""))
  var steamId = steamAppId(win)
  if (steamId && execMentionsSteamId(exec, steamId)) best = Math.max(best, 880)

  var urls = execUrls(exec)
  for (var u = 0; u < urls.length; u++) {
    var host = hostFromUrl(urls[u])
    if (titleMentionsHost(win.title, host)) best = Math.max(best, 650)
  }

  return best
}

function bestMatch(win, rows, overrides) {
  var forcedId = overrideDesktopId(win, overrides)
  if (forcedId) {
    var forced = entryById(rows, forcedId)
    if (forced) return { entry: forced, score: 10000, reason: "override" }
  }

  var chosen = null
  var chosenScore = -1
  for (var i = 0; i < rows.length; i++) {
    var entry = rows[i] && rows[i].entry ? rows[i].entry : rows[i]
    var current = score(win, entry)
    if (current > chosenScore) {
      chosen = entry
      chosenScore = current
    }
  }

  return chosenScore >= 600 ? { entry: chosen, score: chosenScore, reason: "heuristic" } : null
}

if (typeof module !== "undefined") {
  module.exports = {
    bestMatch: bestMatch,
    score: score,
    compact: compact,
    overrideDesktopId: overrideDesktopId,
    steamAppId: steamAppId,
    hostFromUrl: hostFromUrl
  }
}
