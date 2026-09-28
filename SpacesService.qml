import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "qml/AppMatcher.js" as AppMatcher

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: "tornikegomareli.spaces"
  readonly property int expectedProtocol: 6
  readonly property string home: Quickshell.env("HOME")
  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string backendPath: dataHome + "/" + pluginId + "/bin/spaces-backend"
  readonly property string overridePath: configHome + "/" + pluginId + "/overrides.json"
  readonly property string pinsPath: configHome + "/" + pluginId + "/pins.json"

  property alias windows: windowModel
  property var windowRows: []
  property alias pinnedLaunchers: pinnedLauncherModel
  property bool backendHealthy: false
  property string backendVersion: ""
  property bool protocolCompatible: false
  property bool appLibraryHealthy: false
  property string appLibraryDiagnostic: "Not probed"
  property string lastError: ""
  property var menuHost: null
  property bool menuOpened: false
  property bool batchBusy: false
  property int orphanHiddenCount: 0

  function windowForAddress(address) {
    const normalized = normalizedAddress(address)
    for (let i = 0; i < windowModel.count; i++) {
      const row = windowModel.get(i)
      if (row.address === normalized) return JSON.parse(JSON.stringify(row))
    }
    return null
  }

  function activeWindowAddress() {
    for (let i = 0; i < windowModel.count; i++)
      if (windowModel.get(i).active) return windowModel.get(i).address
    return ""
  }

  property var appRows: []
  property var appPresentationById: ({})
  property var appOverrides: ({})
  property var pinnedDesktopIds: []
  property var minimizedByAddress: ({})
  property var minimizedRecordsByAddress: ({})
  property var busyByAddress: ({})
  property var unmatchedProbeByAddress: ({})
  property var orderByAddress: ({})
  property int nextWindowOrder: 1
  property var backendQueue: []
  property var activeJob: null

  ListModel { id: windowModel }
  ListModel { id: pinnedLauncherModel }

  function normalizedAddress(value) {
    var v = String(value || "").trim().toLowerCase()
    if (!v) return ""
    return v.indexOf("0x") === 0 ? v : "0x" + v
  }

  function windowOrder(address) {
    var normalized = normalizedAddress(address)
    if (!normalized) return 0
    if (orderByAddress[normalized] !== undefined) return Number(orderByAddress[normalized])

    var next = ({})
    for (var key in orderByAddress) next[key] = orderByAddress[key]
    next[normalized] = nextWindowOrder
    orderByAddress = next
    nextWindowOrder += 1
    return Number(next[normalized])
  }

  function pruneWindowOrder(rows) {
    var keep = ({})
    for (var i = 0; i < rows.length; i++) keep[rows[i].address] = true

    var changed = false
    var next = ({})
    for (var address in orderByAddress) {
      if (keep[address]) next[address] = orderByAddress[address]
      else changed = true
    }
    if (changed) orderByAddress = next
  }

  function parseOverrides(rawText) {
    var next = ({})
    var raw = String(rawText || "").trim()
    if (!raw) {
      appOverrides = next
      rebuildWindows()
      return
    }

    try {
      var parsed = JSON.parse(raw)
      var source = parsed && parsed.matches ? parsed.matches : parsed
      if (!source || typeof source !== "object" || source instanceof Array)
        throw new Error("expected an object or { matches: { ... } }")

      for (var key in source) {
        var value = String(source[key] || "").trim()
        if (!value) continue
        next[String(key || "").trim().toLowerCase()] = value
      }
      appOverrides = next
      if (lastError.indexOf("Invalid AppLibrary override file:") === 0) lastError = ""
      rebuildWindows()
    } catch (e) {
      lastError = "Invalid AppLibrary override file: " + String(e)
    }
  }


  function parsePins(rawText) {
    const raw = String(rawText || "").trim()
    if (!raw) {
      root.pinnedDesktopIds = []
      root.rebuildWindows()
      root.rebuildPinnedLaunchers()
      return
    }

    try {
      const parsed = JSON.parse(raw)
      const source = parsed instanceof Array ? parsed : (parsed && parsed.desktopIds)
      if (!(source instanceof Array)) throw new Error("expected an array or { desktopIds: [...] }")

      const next = []
      const seen = ({})
      for (let i = 0; i < source.length; i++) {
        const id = String(source[i] || "").trim()
        if (!id || seen[id]) continue
        seen[id] = true
        next.push(id)
      }

      root.pinnedDesktopIds = next
      if (root.lastError.indexOf("Invalid Spaces pins file:") === 0) root.lastError = ""
      root.rebuildWindows()
      root.rebuildPinnedLaunchers()
    } catch (e) {
      root.lastError = "Invalid Spaces pins file: " + String(e)
    }
  }

  function savePins() {
    const body = JSON.stringify({ desktopIds: root.pinnedDesktopIds }, null, 2) + "\n"
    pinsFile.setText(body)
  }

  function pinIndex(desktopId) {
    return root.pinnedDesktopIds.indexOf(String(desktopId || ""))
  }

  function isApplicationPinned(desktopId) {
    return root.pinIndex(desktopId) >= 0
  }

  function pinApplication(desktopId) {
    const id = String(desktopId || "").trim()
    if (!id || !root.appPresentationById[id]) return false
    if (root.isApplicationPinned(id)) return true

    const next = root.pinnedDesktopIds.slice()
    next.push(id)
    root.pinnedDesktopIds = next
    root.rebuildWindows()
    root.rebuildPinnedLaunchers()
    root.savePins()
    return true
  }

  function unpinApplication(desktopId) {
    const id = String(desktopId || "").trim()
    const index = root.pinIndex(id)
    if (index < 0) return true

    const next = root.pinnedDesktopIds.slice()
    next.splice(index, 1)
    root.pinnedDesktopIds = next
    root.rebuildWindows()
    root.rebuildPinnedLaunchers()
    root.savePins()
    return true
  }

  function movePinnedApplication(desktopId, delta) {
    const id = String(desktopId || "").trim()
    const index = root.pinIndex(id)
    const target = index + Number(delta || 0)
    if (index < 0 || target < 0 || target >= root.pinnedDesktopIds.length || target === index) return false

    const next = root.pinnedDesktopIds.slice()
    const moved = next.splice(index, 1)[0]
    next.splice(target, 0, moved)
    root.pinnedDesktopIds = next
    root.rebuildPinnedLaunchers()
    root.savePins()
    return true
  }

  function syncPinnedLauncherModel(rows) {
    const wanted = ({})
    for (let i = 0; i < rows.length; i++) wanted[rows[i].desktopId] = true

    for (let i = pinnedLauncherModel.count - 1; i >= 0; i--) {
      if (!wanted[String(pinnedLauncherModel.get(i).desktopId)]) pinnedLauncherModel.remove(i)
    }

    for (let targetIndex = 0; targetIndex < rows.length; targetIndex++) {
      const row = rows[targetIndex]
      let currentIndex = -1
      for (let i = 0; i < pinnedLauncherModel.count; i++) {
        if (String(pinnedLauncherModel.get(i).desktopId) === row.desktopId) {
          currentIndex = i
          break
        }
      }

      if (currentIndex < 0) {
        pinnedLauncherModel.insert(targetIndex, row)
        continue
      }

      if (currentIndex !== targetIndex) pinnedLauncherModel.move(currentIndex, targetIndex, 1)
      pinnedLauncherModel.setProperty(targetIndex, "appName", row.appName)
      pinnedLauncherModel.setProperty(targetIndex, "iconSource", row.iconSource)
      pinnedLauncherModel.setProperty(targetIndex, "pinIndex", row.pinIndex)
    }
  }

  function rebuildPinnedLaunchers() {
    const running = ({})
    for (let i = 0; i < windowModel.count; i++) {
      const id = String(windowModel.get(i).desktopId || "")
      if (id) running[id] = true
    }

    const rows = []
    for (let i = 0; i < root.pinnedDesktopIds.length; i++) {
      const id = String(root.pinnedDesktopIds[i] || "")
      if (!id || running[id]) continue
      const presentation = root.appPresentationById[id]
      if (!presentation || !presentation.name || !presentation.icon) continue
      rows.push({
        desktopId: id,
        appName: String(presentation.name),
        iconSource: String(presentation.icon),
        pinIndex: i
      })
    }

    root.syncPinnedLauncherModel(rows)
  }

  function probeAppLibrary() {
    if (!shell) {
      appLibraryHealthy = false
      appLibraryDiagnostic = "Plugin shell facade unavailable"
      rebuildWindows()
      return
    }

    var lib = shell.appLibrary
    if (!lib) {
      appLibraryHealthy = false
      appLibraryDiagnostic = "UPSTREAM_APP_LIBRARY_CAPABILITY_BROKEN: shell.appLibrary is null"
      rebuildWindows()
      return
    }

    try {
      lib.refreshIcons()
      var rows = lib.sortedEntries("") || []
      if (rows.length === 0) throw new Error("AppLibrary returned no visible entries")

      var presentations = ({})
      var verified = false
      for (var i = 0; i < rows.length; i++) {
        var entry = rows[i] && rows[i].entry ? rows[i].entry : rows[i]
        if (!entry) continue
        var id = String(entry.id || "")
        var name = String(lib.entryName(entry) || "")
        var icon = String(lib.iconSource(entry.icon) || "")
        if (id && name && icon) presentations[id] = { name: name, icon: icon }
        if (name && icon) verified = true
      }

      if (!verified) throw new Error("entryName/iconSource probe failed for visible DesktopEntries")

      appRows = rows
      appPresentationById = presentations
      appLibraryHealthy = true
      appLibraryDiagnostic = "ok"
      rebuildWindows()
      rebuildPinnedLaunchers()
    } catch (e) {
      appLibraryHealthy = false
      appLibraryDiagnostic = "UPSTREAM_APP_LIBRARY_CAPABILITY_BROKEN: " + String(e)
      rebuildWindows()
    }
  }

  function workspaceNameFrom(rawWorkspace, fallbackWorkspace) {
    if (rawWorkspace && rawWorkspace.name !== undefined) return String(rawWorkspace.name || "")
    if (fallbackWorkspace && fallbackWorkspace.name !== undefined) return String(fallbackWorkspace.name || "")
    return ""
  }

  function infoForToplevel(toplevel) {
    if (!toplevel) return null
    var raw = toplevel.lastIpcObject || ({})
    var address = normalizedAddress(toplevel.address || raw.address)
    if (!address) return null
    var wayland = toplevel.wayland
    var workspaceName = workspaceNameFrom(raw.workspace, toplevel.workspace)

    return {
      address: address,
      title: String(toplevel.title || raw.title || raw.initialTitle || ""),
      initialTitle: String(raw.initialTitle || ""),
      className: String(raw.class || ""),
      initialClass: String(raw.initialClass || ""),
      appId: String(wayland ? wayland.appId : ""),
      pid: Number(raw.pid || 0),
      workspace: raw.workspace && raw.workspace.id !== undefined
        ? Number(raw.workspace.id)
        : (toplevel.workspace ? Number(toplevel.workspace.id) : 0),
      workspaceName: workspaceName,
      specialWorkspace: workspaceName.indexOf("special:") === 0,
      monitorId: raw.monitor !== undefined ? Number(raw.monitor) : -1,
      active: !!toplevel.activated,
      urgent: !!toplevel.urgent,
      floating: !!raw.floating,
      pinned: !!raw.pinned,
      pseudo: !!raw.pseudo,
      fullscreen: Number(raw.fullscreen || 0),
      fullscreenClient: Number(raw.fullscreenClient || 0),
      groupedCount: raw.grouped && raw.grouped.length !== undefined ? Number(raw.grouped.length) : 0,
      popped: raw.tags && raw.tags.length !== undefined
        ? Array.prototype.some.call(raw.tags, function(tag) { return String(tag || "").replace(/\*$/, "") === "pop" })
        : false
    }
  }

  function infoForRecord(record) {
    if (!record) return null
    var address = normalizedAddress(record.address)
    if (!address) return null
    var workspaceName = String(record.workspace_name || "")
    return {
      address: address,
      title: String(record.title || record.initial_title || ""),
      initialTitle: String(record.initial_title || ""),
      className: String(record.class_name || ""),
      initialClass: String(record.initial_class || ""),
      appId: "",
      pid: Number(record.pid || 0),
      workspace: Number(record.workspace_id || 0),
      workspaceName: workspaceName,
      specialWorkspace: workspaceName.indexOf("special:") === 0,
      monitorId: record.monitor_id === undefined ? -1 : Number(record.monitor_id),
      active: false,
      urgent: false,
      floating: !!record.floating,
      pinned: !!record.pinned,
      pseudo: !!record.pseudo,
      fullscreen: Number(record.fullscreen || 0),
      fullscreenClient: Number(record.fullscreen_client || 0),
      groupedCount: 0,
      popped: false
    }
  }

  function rowForInfo(info) {
    if (!info) return null

    var match = appLibraryHealthy ? AppMatcher.bestMatch(info, appRows, appOverrides) : null
    var entry = match ? match.entry : null
    var desktopId = entry ? String(entry.id || "") : ""
    var presentation = desktopId ? appPresentationById[desktopId] : null
    var matched = !!(entry && presentation && presentation.name && presentation.icon)
    var appName = matched ? String(presentation.name) : "Unmatched application"
    var icon = matched ? String(presentation.icon) : ""
    var minimized = minimizedByAddress[info.address] === true
    var restoreRecord = minimized ? minimizedRecordsByAddress[info.address] : null
    if (!restoreRecord && info.workspaceName === "special:omarchy-spaces-minimized") {
      // IPC may report the move before the one-shot helper returns its journal.
      // Keep the existing slot while that transaction is still in flight.
      var previous = windowRows.find(function(row) { return row.address === info.address })
      return previous && busyByAddress[info.address]
        ? Object.assign({}, previous, { active: false, busy: true }) : null
    }

    // A live Hyprland client that is currently hidden reports the plugin's
    // private special workspace. Present the original restore metadata instead
    // so Spaces never mistakes the implementation detail for user state.
    var workspace = restoreRecord ? Number(restoreRecord.workspace_id || 0) : Number(info.workspace || 0)
    var workspaceName = restoreRecord ? String(restoreRecord.workspace_name || "") : String(info.workspaceName || "")
    var floating = restoreRecord ? !!restoreRecord.floating : !!info.floating
    var pinned = restoreRecord ? !!restoreRecord.pinned : !!info.pinned
    var pseudo = restoreRecord ? !!restoreRecord.pseudo : !!info.pseudo
    var fullscreen = restoreRecord ? Number(restoreRecord.fullscreen || 0) : Number(info.fullscreen || 0)
    var fullscreenClient = restoreRecord ? Number(restoreRecord.fullscreen_client || 0) : Number(info.fullscreenClient || 0)

    return {
      address: info.address,
      appId: info.appId || info.className || "",
      pid: Number(info.pid || 0),
      title: info.title || info.initialTitle || appName,
      desktopId: matched ? desktopId : "",
      appName: appName,
      iconSource: icon,
      active: minimized ? false : !!info.active,
      urgent: !!info.urgent,
      minimized: minimized,
      desktopBatch: restoreRecord ? String(restoreRecord.batch_id || "") : "",
      busy: busyByAddress[info.address] === true,
      workspace: workspace,
      workspaceName: workspaceName,
      specialWorkspace: workspaceName.indexOf("special:") === 0,
      monitorId: restoreRecord && restoreRecord.monitor_id !== undefined
        ? Number(restoreRecord.monitor_id) : Number(info.monitorId),
      floating: floating,
      pinned: pinned,
      pseudo: pseudo,
      fullscreen: fullscreen,
      fullscreenClient: fullscreenClient,
      groupedCount: Number(info.groupedCount || 0),
      popped: !!info.popped,
      matched: matched,
      taskbarPinned: matched && root.isApplicationPinned(desktopId),
      modelOrder: windowOrder(info.address)
    }
  }

  function markUnmatchedForProbe(address) {
    var normalized = normalizedAddress(address)
    if (!normalized || unmatchedProbeByAddress[normalized]) return

    var next = ({})
    for (var key in unmatchedProbeByAddress) next[key] = unmatchedProbeByAddress[key]
    next[normalized] = true
    unmatchedProbeByAddress = next
    appRefreshDebounce.restart()
  }

  function modelIndexForAddress(address) {
    for (var i = 0; i < windowModel.count; i++)
      if (String(windowModel.get(i).address) === String(address)) return i
    return -1
  }

  function syncWindowModel(rows) {
    var wanted = ({})
    for (var i = 0; i < rows.length; i++) wanted[rows[i].address] = true

    for (var removeIndex = windowModel.count - 1; removeIndex >= 0; removeIndex--) {
      if (!wanted[String(windowModel.get(removeIndex).address)]) windowModel.remove(removeIndex)
    }

    var roles = [
      "title", "desktopId", "appName", "iconSource", "active", "urgent", "minimized", "busy",
      "workspace", "workspaceName", "specialWorkspace", "monitorId", "floating", "pinned", "pseudo",
      "fullscreen", "fullscreenClient", "groupedCount", "popped", "matched", "taskbarPinned", "modelOrder",
      "appId", "pid", "desktopBatch"
    ]

    for (var targetIndex = 0; targetIndex < rows.length; targetIndex++) {
      var row = rows[targetIndex]
      var currentIndex = modelIndexForAddress(row.address)
      if (currentIndex < 0) {
        windowModel.insert(targetIndex, row)
        continue
      }

      if (currentIndex !== targetIndex) windowModel.move(currentIndex, targetIndex, 1)
      for (var roleIndex = 0; roleIndex < roles.length; roleIndex++) {
        var role = roles[roleIndex]
        windowModel.setProperty(targetIndex, role, row[role])
      }
    }
  }

  function rebuildWindows() {
    var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var rows = []
    var seen = ({})
    var orphans = 0

    for (var i = 0; i < values.length; i++) {
      var info = infoForToplevel(values[i])
      if (info && info.workspaceName === "special:omarchy-spaces-minimized"
          && !minimizedRecordsByAddress[info.address] && !busyByAddress[info.address]) orphans++
      var row = rowForInfo(info)
      if (!row) continue
      seen[row.address] = true
      rows.push(row)
      if (!row.matched && appLibraryHealthy) markUnmatchedForProbe(row.address)
    }

    for (var address in minimizedRecordsByAddress) {
      if (seen[address]) continue
      var fallback = rowForInfo(infoForRecord(minimizedRecordsByAddress[address]))
      if (fallback) {
        rows.push(fallback)
        if (!fallback.matched && appLibraryHealthy) markUnmatchedForProbe(fallback.address)
      }
    }

    rows.sort(function(a, b) {
      if (a.modelOrder !== b.modelOrder) return a.modelOrder - b.modelOrder
      return a.address.localeCompare(b.address)
    })

    syncWindowModel(rows)
    root.orphanHiddenCount = orphans
    root.windowRows = rows
    pruneWindowOrder(rows)
    rebuildPinnedLaunchers()
  }

  function setBusy(address, value) {
    var normalized = normalizedAddress(address)
    if (!normalized) return

    var next = ({})
    for (var key in busyByAddress) next[key] = busyByAddress[key]
    if (value) next[normalized] = true
    else delete next[normalized]
    busyByAddress = next
    rebuildWindows()
  }

  function enqueueBackend(args, tag, address, addresses, batch) {
    backendQueue.push({ args: args, tag: tag || "", address: normalizedAddress(address), addresses: addresses || [], batch: !!batch })
    startNextBackendJob()
  }

  function requestSnapshot() {
    if (!protocolCompatible || !backendHealthy) return
    for (var i = 0; i < backendQueue.length; i++)
      if (backendQueue[i].tag === "snapshot") return
    if (activeJob && activeJob.tag === "snapshot") return
    enqueueBackend(["snapshot"], "snapshot", "")
  }

  function startNextBackendJob() {
    if (backendProc.running || activeJob || backendQueue.length === 0) return
    activeJob = backendQueue.shift()
    backendOutput.text = ""
    // The invoked binary checks its own protocol before doing any work. This
    // also covers replacement between a version probe and the action itself.
    backendProc.command = activeJob.tag === "version"
      ? [backendPath, "version-json"]
      : [backendPath, "--protocol", String(expectedProtocol)].concat(activeJob.args)
    backendProc.running = true
  }

  function applyMinimizedRecords(records) {
    var flags = ({})
    var details = ({})
    var values = records instanceof Array ? records : []

    for (var i = 0; i < values.length; i++) {
      var address = normalizedAddress(values[i].address)
      if (!address) continue
      flags[address] = true
      details[address] = values[i]
    }

    minimizedByAddress = flags
    minimizedRecordsByAddress = details
  }

  function handleBackendObject(job, obj) {
    if (!obj) return

    if (obj.backendVersion !== undefined) backendVersion = String(obj.backendVersion)
    if (obj.protocolVersion !== undefined) {
      protocolCompatible = Number(obj.protocolVersion) === expectedProtocol
      if (job && (job.tag === "version" || job.tag === "snapshot"))
        backendHealthy = protocolCompatible && obj.ok !== false
    }

    if (obj.minimized !== undefined) applyMinimizedRecords(obj.minimized)
    if (obj.error) lastError = String(obj.error)
    else if (obj.ok === true && job && job.tag === "action") {
      const persistentConfigError = lastError.indexOf("Invalid AppLibrary override file:") === 0
        || lastError.indexOf("Invalid Spaces pins file:") === 0
        || lastError.indexOf("Could not save Spaces pins:") === 0
      if (!persistentConfigError) lastError = ""
    }

    finishJob(job)

    Hyprland.refreshToplevels()
    Qt.callLater(function() { root.rebuildWindows() })

    if (job && job.tag === "action") snapshotDebounce.restart()
  }

  function backendAction(args, address) {
    if (!backendHealthy || !protocolCompatible) {
      lastError = "Backend update required. Run " + configHome + "/omarchy/plugins/" + pluginId + "/scripts/build-backend.sh"
      return false
    }

    var normalized = normalizedAddress(address)
    var addresses = normalized ? [normalized] : []
    var tl = normalized ? toplevelFor(normalized) : null
    var grouped = tl && tl.lastIpcObject ? tl.lastIpcObject.grouped || [] : []
    var record = minimizedRecordsByAddress[normalized]
    if (record && record.group_key) grouped = record.group_key.split("|")
    for (var i = 0; i < grouped.length; i++) {
      var member = normalizedAddress(grouped[i])
      if (member && addresses.indexOf(member) === -1) addresses.push(member)
    }
    if (addresses.some(function(id) { return busyByAddress[id] })) return false
    var flags = Object.assign({}, busyByAddress)
    addresses.forEach(function(id) { flags[id] = true })
    busyByAddress = flags
    rebuildWindows()
    enqueueBackend(args, "action", normalized, addresses)
    return true
  }

  function finishJob(job) {
    if (!job) return
    var flags = Object.assign({}, busyByAddress)
    if (job.address) delete flags[job.address]
    for (var i = 0; i < job.addresses.length; i++) delete flags[job.addresses[i]]
    busyByAddress = flags
    if (job.batch) batchBusy = false
  }

  function batchAction(args, workspace) {
    if (!backendHealthy || !protocolCompatible || batchBusy) return false
    var targets = windowRows.filter(function(row) {
      return workspace === undefined || String(row.workspace) === String(workspace)
        || row.workspaceName === String(workspace)
    })
    if (targets.some(function(row) { return row.busy })) return false
    var flags = Object.assign({}, busyByAddress)
    var addresses = targets.map(function(row) { flags[row.address] = true; return row.address })
    busyByAddress = flags
    batchBusy = true
    rebuildWindows()
    enqueueBackend(args, "action", "", addresses, true)
    return true
  }

  function toplevelFor(address) {
    var normalized = normalizedAddress(address)
    var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < values.length; i++)
      if (normalizedAddress(values[i].address) === normalized) return values[i]
    return null
  }

  function isMinimized(address) {
    return minimizedByAddress[normalizedAddress(address)] === true
  }

  function activateWindow(address, minimizeActive) {
    var normalized = normalizedAddress(address)
    if (busyByAddress[normalized]) return false
    if (isMinimized(normalized)) return backendAction(["restore", normalized, "--focus"], normalized)

    var toplevel = toplevelFor(normalized)
    if (!toplevel) return false
    if (minimizeActive !== false && toplevel.activated) return backendAction(["minimize", normalized], normalized)

    if (toplevel.wayland) {
      toplevel.wayland.activate()
      snapshotDebounce.restart()
      return true
    }

    return backendAction(["window-action", "focus", normalized], normalized)
  }

  function closeWindow(address) {
    var normalized = normalizedAddress(address)
    if (busyByAddress[normalized]) return false
    var toplevel = toplevelFor(normalized)
    if (toplevel && toplevel.wayland) {
      toplevel.wayland.close()
      snapshotDebounce.restart()
      return true
    }
    return backendAction(["window-action", "close", normalized], normalized)
  }

  function launchApplication(desktopId, appName) {
    const id = String(desktopId || "").trim()
    if (!id) return false
    if (!shell || !shell.appLibrary || !appLibraryHealthy) {
      lastError = "AppLibrary unavailable; cannot launch " + id
      return false
    }

    try {
      shell.appLibrary.launch(id, String(appName || id))
      return true
    } catch (e) {
      lastError = "AppLibrary launch failed: " + String(e)
      return false
    }
  }

  function menuAction(action, address, argument) {
    var normalized = normalizedAddress(address)
    if (action === "minimize") return backendAction(["minimize", normalized], normalized)
    if (action === "restore") return backendAction(["restore", normalized, "--focus"], normalized)
    if (action === "close") return closeWindow(normalized)

    var args = ["window-action", String(action), normalized]
    if (argument !== undefined && argument !== null && String(argument).length > 0)
      args.push(String(argument))
    return backendAction(args, normalized)
  }

  function showDesktop(workspace) {
    if (workspace === undefined || workspace === null || String(workspace) === "") return false
    return batchAction(["show-desktop-toggle", String(workspace)], workspace)
  }
  function restoreWorkspace(workspace) { return batchAction(["restore-workspace", String(workspace)], workspace) }
  function restoreLast() { return batchAction(["restore-last"]) }
  function restoreAll() { return batchAction(["restore-all"]) }
  function recover() { return batchAction(["recover"]) }

  QtObject {
    id: backendOutput
    property string text: ""
  }

  Process {
    id: backendProc
    stdout: SplitParser { onRead: function(line) { backendOutput.text += line } }
    stderr: SplitParser { onRead: function(line) { root.lastError = line } }

    // Quickshell 0.3.1 emits runningChanged, but not exited, on FailedToStart.
    onRunningChanged: {
      if (running) return
      const stoppedJob = root.activeJob
      Qt.callLater(function() {
        if (!backendProc.running && stoppedJob && root.activeJob === stoppedJob) {
          if (stoppedJob.address) root.setBusy(stoppedJob.address, false)
          root.activeJob = null
          root.backendQueue = []
          root.busyByAddress = ({})
          root.batchBusy = false
          root.rebuildWindows()
          root.backendHealthy = false
          root.lastError = "Backend could not start. Run " + root.configHome + "/omarchy/plugins/" + root.pluginId + "/scripts/build-backend.sh"
        }
      })
    }

    onExited: function(code) {
      var job = root.activeJob
      root.activeJob = null
      var obj = null

      try {
        obj = JSON.parse(backendOutput.text || "{}")
      } catch (e) {
        root.lastError = "Backend returned invalid JSON: " + String(e)
        if (job && (job.tag === "version" || job.tag === "snapshot")) root.backendHealthy = false
      }

      if (obj && obj.busy === true) {
        root.finishJob(job)
        root.rebuildWindows()
        if (job && job.tag === "action") root.lastError = "Window operation busy; try again"
        snapshotDebounce.restart()
        root.startNextBackendJob()
        return
      }

      if (code !== 0 && job && (job.tag === "version" || job.tag === "snapshot"))
        root.backendHealthy = false

      if (!obj) { root.finishJob(job); root.rebuildWindows() }
      root.handleBackendObject(job, obj)
      root.startNextBackendJob()
    }
  }

  FileView {
    id: pinsFile
    path: root.pinsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.parsePins(text())
    onFileChanged: pinsFile.reload()
    onLoadFailed: function() { root.parsePins("") }
    onSaved: {
      if (root.lastError.indexOf("Could not save Spaces pins:") === 0) root.lastError = ""
    }
    onSaveFailed: function(error) {
      root.lastError = "Could not save Spaces pins: " + FileViewError.toString(error)
    }
  }

  FileView {
    id: overridesFile
    path: root.overridePath
    watchChanges: true
    printErrors: false
    onLoaded: root.parseOverrides(text())
    onFileChanged: overridesFile.reload()
    onLoadFailed: root.parseOverrides("")
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { root.rebuildWindows() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      rebuildDebounce.restart()
      snapshotDebounce.restart()
    }
  }

  Connections {
    target: root.shell && root.shell.appLibrary ? root.shell.appLibrary : null
    function onAppsChanged() { root.probeAppLibrary() }
  }

  Timer {
    id: rebuildDebounce
    interval: 40
    repeat: false
    onTriggered: {
      Hyprland.refreshToplevels()
      root.rebuildWindows()
    }
  }

  Timer {
    id: appRefreshDebounce
    interval: 250
    repeat: false
    onTriggered: root.probeAppLibrary()
  }

  Timer {
    id: snapshotDebounce
    interval: 90
    repeat: false
    onTriggered: root.requestSnapshot()
  }

  Timer {
    interval: 10000
    repeat: true
    running: true
    onTriggered: {
      if (!root.activeJob && root.backendQueue.length === 0)
        root.enqueueBackend(["version-json"], "version", "")
      root.requestSnapshot()
    }
  }

  onShellChanged: probeAppLibrary()

  Component.onCompleted: {
    probeAppLibrary()
    enqueueBackend(["version-json"], "version", "")
    enqueueBackend(["snapshot"], "snapshot", "")
    rebuildWindows()
  }

  function status(): string {
    return JSON.stringify({
      backendHealthy: root.backendHealthy,
      backendVersion: root.backendVersion,
      protocolCompatible: root.protocolCompatible,
      appLibraryHealthy: root.appLibraryHealthy,
      appLibraryDiagnostic: root.appLibraryDiagnostic,
      windows: windowModel.count,
      minimized: Object.keys(root.minimizedByAddress).length,
      pinnedApplications: root.pinnedDesktopIds.length,
      pinsPath: root.pinsPath,
      overridePath: root.overridePath,
      batchBusy: root.batchBusy,
      orphanHiddenCount: root.orphanHiddenCount,
      lastError: root.lastError
    })
  }

  function refreshApps(): string {
    root.probeAppLibrary()
    return root.appLibraryHealthy ? "ok" : root.appLibraryDiagnostic
  }

  function model(): string {
    var rows = []
    for (var i = 0; i < windowModel.count; i++) rows.push(windowModel.get(i))
    return JSON.stringify(rows)
  }

}
