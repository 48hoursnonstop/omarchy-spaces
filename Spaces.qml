import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Workspace switcher that shows which apps are open on each workspace.
//
// Each workspace is a pill. The active pill (and, depending on settings, the
// hovered or every occupied pill) slides open to reveal the app icons of its
// windows. Left-click a pill to focus the workspace, left-click an icon to
// focus that window, scroll to step through workspaces, right-click for
// settings. Settings persist inline on this widget's shell.json entry.
Panel {
  id: root
  moduleName: "insanearts.spaces"
  ipcTarget: "insanearts.spaces"
  manageIpc: false

  // ------------------------------------------------------------ settings

  readonly property var cfg: Model.resolveSettings(root.settings)

  function applySetting(delta) {
    var entry = Model.mergedEntry(root.moduleName, root.settings, delta)
    // Applied locally first so the widget redraws on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function resetSettings() {
    var entry = { id: root.moduleName }
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ------------------------------------------------------------ geometry & colors

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color bg: bar ? bar.background : Color.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int pillThickness: Math.max(16, barSize - Style.space(6))
  readonly property int iconPx: Math.min(cfg.iconSize, pillThickness - Style.space(4))
  readonly property int pillRadius: Style.cornerRadius > 0 ? Math.round(pillThickness * 0.32) : 0
  readonly property int dur: Model.durationFor(cfg, 280)
  readonly property int fastDur: Model.durationFor(cfg, 160)
  readonly property real trailingGap: vertical ? 0 : Style.spaceReal(1.5)
  readonly property var metrics: Model.densityMetrics(cfg.density)
  readonly property bool widgetHovered: widgetHover.hovered

  function activeFill() {
    if (cfg.activeStyle === "solid") return root.fg
    if (cfg.activeStyle === "accent") return Color.accent
    return Util.alpha(root.fg, 0.18)
  }

  function activeText() {
    return cfg.activeStyle === "subtle" ? root.fg : root.bg
  }

  // ------------------------------------------------------------ Hyprland state

  // Bumped after Hyprland reports window moves, so positions (and therefore
  // icon order) re-read the freshly refreshed IPC objects.
  property int revision: 0

  readonly property var monitor: {
    var w = root.QsWindow.window
    return w && w.screen ? Hyprland.monitorFor(w.screen) : null
  }

  readonly property int currentWorkspaceId: {
    if (cfg.perMonitor && root.monitor && root.monitor.activeWorkspace) return root.monitor.activeWorkspace.id
    return Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  }

  // Workspace focused before the current one, for "click active = go back".
  property int previousWorkspaceId: -1
  property int lastWorkspaceId: -1
  onCurrentWorkspaceIdChanged: {
    if (root.lastWorkspaceId > 0 && root.lastWorkspaceId !== root.currentWorkspaceId)
      root.previousWorkspaceId = root.lastWorkspaceId
    root.lastWorkspaceId = root.currentWorkspaceId
  }

  // Addresses (normalized) of windows that requested attention and have not
  // been focused since.
  property var urgentAddresses: ({})

  function setUrgent(address, urgent) {
    var key = Model.normalizeAddress(address)
    if (key === "" || (!!root.urgentAddresses[key]) === urgent) return
    var next = ({})
    for (var k in root.urgentAddresses) if (k !== key) next[k] = true
    if (urgent) next[key] = true
    root.urgentAddresses = next
  }

  function isUrgent(address) {
    return root.cfg.urgentHighlight && !!root.urgentAddresses[Model.normalizeAddress(address)]
  }

  function appIdOf(toplevel) {
    if (toplevel.wayland && toplevel.wayland.appId) return toplevel.wayland.appId
    var ipc = toplevel.lastIpcObject
    return ipc && ipc["class"] ? ipc["class"] : ""
  }

  // { [workspaceId]: { id, active, windows: [{ address, appId, title, focused, at }] } }
  readonly property var workspaceMap: {
    root.revision
    var values = Hyprland.workspaces.values
    var activeToplevel = Hyprland.activeToplevel
    var perMonitor = cfg.perMonitor && root.monitor !== null
    var map = ({})

    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      if (ws.id <= 0) continue
      if (perMonitor && ws.monitor !== root.monitor) continue

      var windows = []
      var toplevels = ws.toplevels.values
      for (var j = 0; j < toplevels.length; j++) {
        var tl = toplevels[j]
        var ipc = tl.lastIpcObject || {}
        windows.push({
          address: String(tl.address),
          appId: root.appIdOf(tl),
          title: String(tl.title || ""),
          focused: activeToplevel ? tl === activeToplevel : !!(tl.wayland && tl.wayland.activated),
          at: ipc.at && ipc.at.length === 2 ? [ipc.at[0], ipc.at[1]] : null
        })
      }
      map[ws.id] = { id: ws.id, windows: Model.sortWindows(windows) }
    }
    return map
  }

  readonly property var workspaceIds: {
    var occupied = ({})
    for (var id in workspaceMap) occupied[id] = workspaceMap[id].windows.length
    var active = root.currentWorkspaceId > 0 ? [root.currentWorkspaceId] : []
    return Model.workspaceIds(occupied, active, cfg.persistentWorkspaces, cfg.hideEmpty)
  }

  function focusWorkspace(id) {
    run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function focusWindow(address) {
    var target = "address:0x" + String(address).replace(/^0x/, "")
    run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ window = \"" + target + "\" })")
      + " >/dev/null 2>&1 || hyprctl dispatch focuswindow " + Util.shellQuote(target))
  }

  function closeWindow(address) {
    var target = "address:0x" + Model.normalizeAddress(address)
    run("hyprctl dispatch " + Util.shellQuote("hl.dsp.window.close({ window = \"" + target + "\" })")
      + " >/dev/null 2>&1 || hyprctl dispatch closewindow " + Util.shellQuote(target))
  }

  function clickWorkspace(id) {
    if (id === root.currentWorkspaceId) {
      if (root.cfg.activeClick === "previous" && root.previousWorkspaceId > 0) focusWorkspace(root.previousWorkspaceId)
      return
    }
    focusWorkspace(id)
  }

  function activateItem(item) {
    // A grouped icon that is already focused cycles through its windows.
    if (item.focused && item.addresses.length > 1) {
      var idx = item.addresses.indexOf(item.address)
      focusWindow(item.addresses[(idx + 1) % item.addresses.length])
    } else {
      focusWindow(item.address)
    }
  }

  function scrollBy(delta) {
    if (!cfg.scrollSwitch || delta === 0) return
    var next = Model.stepWorkspace(root.workspaceIds, root.currentWorkspaceId, delta < 0 ? 1 : -1)
    if (next !== root.currentWorkspaceId) focusWorkspace(next)
  }

  function showTip(target, text) {
    if (root.bar && root.cfg.tooltips && text) root.bar.showTooltip(target, text)
  }

  function hideTip(target) {
    if (root.bar) root.bar.hideTooltip(target)
  }

  function run(command) {
    if (root.bar && typeof root.bar.run === "function") root.bar.run(command)
    else Quickshell.execDetached(["bash", "-c", command])
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      switch (event.name) {
      case "urgent":
        root.setUrgent(event.data, true)
        break
      case "activewindowv2":
        root.setUrgent(event.data, false)
        refreshDebounce.restart()
        break
      case "closewindow":
        root.setUrgent(event.data, false)
        refreshDebounce.restart()
        break
      case "openwindow":
      case "movewindow":
      case "movewindowv2":
      case "changefloatingmode":
      case "windowtitle":
      case "windowtitlev2":
        refreshDebounce.restart()
        break
      }
    }
  }

  Timer {
    id: refreshDebounce
    interval: 120
    onTriggered: {
      Hyprland.refreshToplevels()
      revisionBump.restart()
    }
  }

  Timer {
    id: revisionBump
    interval: 80
    onTriggered: root.revision++
  }

  // ------------------------------------------------------------ app icons

  property var iconIndex: ({})
  property var pendingIconIndex: ({})
  property var iconCache: ({})
  property int iconRevision: 0

  function findDesktopEntry(appId) {
    if (!appId) return null
    var entry = DesktopEntries.heuristicLookup(appId)
    if (entry) return entry

    var host = Model.webAppHost(appId)
    if (host === "") return null
    var apps = DesktopEntries.applications.values
    for (var i = 0; i < apps.length; i++) {
      var exec = String(apps[i].execString || "")
      if (exec.indexOf("//" + host) !== -1) return apps[i]
    }
    var candidates = Model.appIdCandidates(appId)
    for (var c = 0; c < candidates.length; c++) {
      var byId = DesktopEntries.byId(candidates[c])
      if (byId) return byId
    }
    return null
  }

  function iconUrl(name) {
    var value = String(name || "")
    if (value === "") return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var indexed = root.iconIndex[value]
    if (indexed) return Util.fileUrl(indexed)
    return Quickshell.iconPath(value, true)
  }

  // Returns { source, name } for an app id; cached until icons rescan.
  function appInfo(appId) {
    root.iconRevision
    var key = Model.appKey(appId)
    var cached = root.iconCache[key]
    if (cached) return cached

    var entry = findDesktopEntry(appId)
    var source = iconUrl(entry && entry.icon ? entry.icon : appId)
    if (source === "" && key !== appId) source = iconUrl(key)
    var info = { source: source, name: entry && entry.name ? String(entry.name) : String(appId || "") }
    root.iconCache[key] = info
    return info
  }

  function invalidateIcons() {
    root.iconCache = ({})
    root.iconRevision++
  }

  function indexIconLine(line) {
    var path = String(line || "").trim()
    if (path === "") return
    var name = Model.iconNameFromPath(path)
    var existing = root.pendingIconIndex[name]
    if (!existing || Model.iconPathScore(path) > Model.iconPathScore(existing))
      root.pendingIconIndex[name] = path
  }

  Process {
    id: iconScan
    // Non-login shell on purpose: a login shell can touch ~/.local/share and
    // retrigger desktop-entry watchers.
    command: ["bash", "-c", [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for base in $dirs; do [[ -d $base ]] && find "$base" -path "*/apps/*" \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null; done;',
      'find /usr/share/pixmaps -maxdepth 1 \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null'
    ].join(" ")]
    stdout: SplitParser { onRead: function(line) { root.indexIconLine(line) } }
    onStarted: root.pendingIconIndex = ({})
    onExited: {
      root.iconIndex = root.pendingIconIndex
      root.invalidateIcons()
    }
  }

  Connections {
    target: DesktopEntries
    function onApplicationsChanged() { iconDebounce.restart() }
  }

  Timer {
    id: iconDebounce
    interval: 1500
    onTriggered: root.invalidateIcons()
  }

  Component.onCompleted: {
    // Touching the list starts Quickshell's desktop-entry scan.
    DesktopEntries.applications.values
    iconScan.running = true
    Hyprland.refreshToplevels()
  }

  // ------------------------------------------------------------ IPC

  IpcHandler {
    target: "insanearts.spaces"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // ------------------------------------------------------------ bar widget

  implicitWidth: vertical ? barSize : pillFlow.implicitWidth + trailingGap
  implicitHeight: vertical ? pillFlow.implicitHeight : barSize

  HoverHandler { id: widgetHover }

  // Right-click anywhere opens settings; wheel steps workspaces. Pills and
  // icons only take the left button, so other buttons fall through to here.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.RightButton | Qt.MiddleButton
    onClicked: function(mouse) { if (mouse.button === Qt.RightButton) root.toggle() }
    onWheel: function(wheel) { root.scrollBy(wheel.angleDelta.y || wheel.angleDelta.x) }
  }

  Grid {
    id: pillFlow
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.leftMargin: root.vertical ? Math.round((root.barSize - root.pillThickness) / 2) : 0
    anchors.topMargin: root.vertical ? 0 : Math.round((root.barSize - root.pillThickness) / 2)
    columns: root.vertical ? 1 : Math.max(1, root.workspaceIds.length + 1)
    spacing: Style.space(root.metrics.gap)

    Repeater {
      model: ScriptModel { values: root.workspaceIds }

      delegate: Item {
        id: pill

        required property var modelData
        readonly property int workspaceId: Number(modelData)
        readonly property var workspace: root.workspaceMap[workspaceId] || ({ id: workspaceId, windows: [] })
        readonly property bool active: workspaceId === root.currentWorkspaceId
        readonly property bool occupied: workspace.windows.length > 0
        readonly property bool hovered: pillMouse.containsMouse
        readonly property bool showApps: Model.showsApps(root.cfg, occupied, active, hovered)
        readonly property bool urgent: {
          if (!root.cfg.urgentHighlight || active) return false
          for (var i = 0; i < workspace.windows.length; i++)
            if (root.isUrgent(workspace.windows[i].address)) return true
          return false
        }
        readonly property var iconData: Model.iconItems(workspace.windows, root.cfg.groupApps, root.cfg.maxIcons)
        readonly property var itemMap: {
          var map = ({})
          for (var i = 0; i < iconData.items.length; i++) map[iconData.items[i].key] = iconData.items[i]
          return map
        }
        readonly property var itemKeys: iconData.items.map(function(item) { return item.key })
        readonly property color textColor: active ? root.activeText() : root.fg
        readonly property string label: Model.workspaceLabel(workspaceId, active, root.cfg.labelStyle)
        readonly property real pad: Style.space(label === "" ? 3 : root.metrics.pad)

        width: implicitWidth
        height: implicitHeight
        implicitWidth: root.vertical ? root.pillThickness : content.implicitWidth + pad * 2
        implicitHeight: root.vertical ? content.implicitHeight + pad * 2 : root.pillThickness

        Behavior on implicitWidth { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }
        Behavior on implicitHeight { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

        // Urgent pulse, under the regular fill so the active style still reads.
        Rectangle {
          id: urgentGlow
          anchors.fill: parent
          radius: root.pillRadius
          color: root.bar ? root.bar.urgent : Color.urgent
          opacity: 0
          visible: pill.urgent

          SequentialAnimation on opacity {
            running: pill.urgent
            loops: Animation.Infinite
            NumberAnimation { from: 0.15; to: 0.55; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.55; to: 0.15; duration: 700; easing.type: Easing.InOutSine }
          }
        }

        Rectangle {
          anchors.fill: parent
          radius: root.pillRadius
          color: pill.active ? root.activeFill()
            : pill.hovered ? Util.alpha(root.fg, 0.12)
            : pill.occupied ? Util.alpha(root.fg, 0.06)
            : "transparent"
          Behavior on color { enabled: root.fastDur > 0; ColorAnimation { duration: root.fastDur } }
        }

        MouseArea {
          id: pillMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton
          cursorShape: Qt.PointingHandCursor
          onClicked: root.clickWorkspace(pill.workspaceId)
          onWheel: function(wheel) { root.scrollBy(wheel.angleDelta.y || wheel.angleDelta.x) }
        }

        Grid {
          id: content
          anchors.centerIn: parent
          columns: root.vertical ? 1 : 2
          horizontalItemAlignment: Grid.AlignHCenter
          verticalItemAlignment: Grid.AlignVCenter
          spacing: pill.label !== "" && iconClip.shownExtent > 0 ? Style.space(5) : 0

          Text {
            visible: pill.label !== ""
            text: pill.label
            color: pill.textColor
            opacity: pill.occupied || pill.active ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: pill.active
            Behavior on color { enabled: root.fastDur > 0; ColorAnimation { duration: root.fastDur } }
            Behavior on opacity { enabled: root.fastDur > 0; NumberAnimation { duration: root.fastDur } }
          }

          // The icon strip is clipped and its extent animates, so icons slide
          // out of the pill rather than popping in.
          Item {
            id: iconClip
            readonly property real fullExtent: root.vertical ? icons.implicitHeight : icons.implicitWidth
            property real shownExtent: pill.showApps ? fullExtent : 0
            Behavior on shownExtent { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

            implicitWidth: root.vertical ? icons.implicitWidth : shownExtent
            implicitHeight: root.vertical ? shownExtent : icons.implicitHeight
            clip: true
            opacity: pill.showApps ? 1 : 0
            Behavior on opacity { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

            Grid {
              id: icons
              columns: root.vertical ? 1 : Math.max(1, pill.itemKeys.length + 1)
              spacing: Style.space(root.metrics.iconGap)
              verticalItemAlignment: Grid.AlignVCenter
              horizontalItemAlignment: Grid.AlignHCenter

              move: Transition {
                enabled: root.dur > 0
                NumberAnimation { properties: "x,y"; duration: root.dur; easing.type: Easing.OutCubic }
              }

              Repeater {
                model: ScriptModel { values: pill.itemKeys }

                delegate: Item {
                  id: appIcon

        // Appear animation lives on the delegate: positioner add transitions
        // can be interrupted and leave items stuck half faded.
        property real appear: root.dur > 0 ? 0 : 1
        opacity: appear
        scale: 0.6 + 0.4 * appear
        Component.onCompleted: if (root.dur > 0) pillAppear.start()
        NumberAnimation { id: pillAppear; target: pill; property: "appear"; to: 1; duration: root.dur; easing.type: Easing.OutBack }

                  required property var modelData
                  readonly property var item: pill.itemMap[modelData] || null
                  readonly property var info: item ? root.appInfo(item.appId) : ({ source: "", name: "" })
                  readonly property bool focusedHere: !!item && item.focused && pill.active
                  readonly property string titleText: root.cfg.focusedTitle && focusedHere && !root.vertical
                    ? Model.focusedLabel(item, info.name, root.cfg.titleLength) : ""
                  readonly property bool hovered: iconMouse.containsMouse

                  implicitWidth: iconRow.implicitWidth + Style.space(4)
                  implicitHeight: Math.max(root.iconPx, iconRow.implicitHeight) + Style.space(2)
                  width: implicitWidth
                  height: implicitHeight
                  property real dim: root.cfg.dimUnfocused && pill.active && !focusedHere && !hovered ? 0.5 : 1
                  Behavior on dim { enabled: root.fastDur > 0; NumberAnimation { duration: root.fastDur } }
                  property real appear: root.dur > 0 ? 0 : 1
                  opacity: dim * Math.min(1, appear)
                  scale: 0.4 + 0.6 * appear
                  Component.onCompleted: if (root.dur > 0) iconAppear.start()
                  NumberAnimation { id: iconAppear; target: appIcon; property: "appear"; to: 1; duration: root.dur; easing.type: Easing.OutBack }
                  Behavior on implicitWidth { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.cornerRadius > 0 ? Style.space(5) : 0
                    color: appIcon.focusedHere || appIcon.hovered ? Util.alpha(pill.textColor, 0.18) : "transparent"
                    Behavior on color { enabled: root.fastDur > 0; ColorAnimation { duration: root.fastDur } }
                  }

                  Row {
                    id: iconRow
                    anchors.centerIn: parent
                    spacing: Style.space(4)

                    Item {
                      width: root.iconPx
                      height: root.iconPx
                      scale: appIcon.hovered ? 1.12 : 1
                      Behavior on scale { enabled: root.fastDur > 0; NumberAnimation { duration: root.fastDur; easing.type: Easing.OutCubic } }

                      Image {
                        id: iconImage
                        anchors.fill: parent
                        source: appIcon.info.source
                        sourceSize.width: root.iconPx * 2
                        sourceSize.height: root.iconPx * 2
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        visible: status === Image.Ready
                        layer.enabled: root.cfg.iconStyle === "mono"
                        layer.effect: MultiEffect { saturation: -1.0 }
                      }

                      // Letter tile when no icon could be resolved.
                      Rectangle {
                        anchors.fill: parent
                        visible: iconImage.status !== Image.Ready
                        radius: Style.cornerRadius > 0 ? width * 0.25 : 0
                        color: Util.alpha(pill.textColor, 0.2)
                        Text {
                          anchors.centerIn: parent
                          text: String(appIcon.info.name || (appIcon.item ? appIcon.item.appId : "?")).charAt(0).toUpperCase()
                          color: pill.textColor
                          font.family: root.fontFamily
                          font.pixelSize: Math.round(root.iconPx * 0.62)
                          font.bold: true
                        }
                      }

                      // Attention dot for windows that asked to be looked at.
                      Rectangle {
                        visible: appIcon.item !== null && appIcon.item.addresses.some(function(a) { return root.isUrgent(a) })
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -Style.space(2)
                        anchors.topMargin: -Style.space(2)
                        width: Math.max(5, Math.round(root.iconPx * 0.36))
                        height: width
                        radius: width / 2
                        color: root.bar ? root.bar.urgent : Color.urgent
                        border.width: 1
                        border.color: root.bg
                      }

                      // Window count for grouped apps.
                      Rectangle {
                        visible: appIcon.item !== null && appIcon.item.count > 1
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -Style.space(3)
                        anchors.bottomMargin: -Style.space(2)
                        width: Math.max(height, countText.implicitWidth + Style.space(4))
                        height: Math.round(root.iconPx * 0.6)
                        radius: height / 2
                        color: root.fg
                        Text {
                          id: countText
                          anchors.centerIn: parent
                          text: appIcon.item ? String(appIcon.item.count) : ""
                          color: root.bg
                          font.family: root.fontFamily
                          font.pixelSize: Math.max(7, Math.round(root.iconPx * 0.45))
                          font.bold: true
                        }
                      }
                    }

                    Text {
                      visible: appIcon.titleText !== ""
                      anchors.verticalCenter: parent.verticalCenter
                      text: appIcon.titleText
                      color: pill.textColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }
                  }

                  MouseArea {
                    id: iconMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: root.cfg.middleClickClose ? (Qt.LeftButton | Qt.MiddleButton) : Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                      if (!appIcon.item) return
                      if (mouse.button === Qt.MiddleButton) root.closeWindow(appIcon.item.address)
                      else root.activateItem(appIcon.item)
                    }
                    onWheel: function(wheel) { root.scrollBy(wheel.angleDelta.y || wheel.angleDelta.x) }
                    onContainsMouseChanged: {
                      if (containsMouse && appIcon.item) {
                        var tip = appIcon.item.title || appIcon.info.name
                        if (appIcon.item.count > 1) tip = appIcon.info.name + " (" + appIcon.item.count + " windows)"
                        root.showTip(appIcon, tip)
                      } else {
                        root.hideTip(appIcon)
                      }
                    }
                  }
                }
              }

              // "+N" chip for windows beyond maxIcons.
              Text {
                visible: pill.iconData.overflow > 0
                text: "+" + pill.iconData.overflow
                color: pill.textColor
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }
        }
      }
    }

    // Settings gear. Slides in while the pointer is over the widget (or
    // always / never, per settings); also lit while the panel is open.
    Item {
      id: gear
      readonly property bool shown: root.opened || root.cfg.settingsButton === "always"
        || (root.cfg.settingsButton === "hover" && root.widgetHovered)
      readonly property real size: root.pillThickness
      property real extent: shown ? size : 0
      Behavior on extent { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }

      visible: extent > 0.5
      implicitWidth: root.vertical ? size : extent
      implicitHeight: root.vertical ? extent : size
      width: implicitWidth
      height: implicitHeight
      clip: true
      opacity: shown ? 1 : 0
      Behavior on opacity { enabled: root.dur > 0; NumberAnimation { duration: root.dur } }

      Rectangle {
        anchors.fill: parent
        radius: root.pillRadius
        color: root.opened ? root.activeFill() : gearMouse.containsMouse ? Util.alpha(root.fg, 0.12) : "transparent"
        Behavior on color { enabled: root.fastDur > 0; ColorAnimation { duration: root.fastDur } }
      }

      Text {
        anchors.centerIn: parent
        text: "\uf013"
        color: root.opened ? root.activeText() : root.fg
        opacity: root.opened || gearMouse.containsMouse ? 1 : 0.6
        rotation: root.opened ? 90 : 0
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Behavior on rotation { enabled: root.dur > 0; NumberAnimation { duration: root.dur; easing.type: Easing.OutCubic } }
      }

      MouseArea {
        id: gearMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
        onContainsMouseChanged: containsMouse ? root.showTip(gear, "Spaces settings") : root.hideTip(gear)
      }
    }
  }

  // ------------------------------------------------------------ settings panel

  KeyboardPanel {
    id: panel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(form.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: form.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
          id: form
          width: parent.width
          spacing: Style.space(14)

          Column {
            width: parent.width
            spacing: Style.space(2)
            Text {
              text: "Spaces"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: "SEE WHAT RUNS ON EVERY WORKSPACE"
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }

          PanelSeparator { foreground: root.fg }

          // ---- App icons
          SectionTitle { text: "APP ICONS" }

          ToggleSetting {
            label: "Show app icons"
            description: root.cfg.showIcons ? "Icons of open apps appear in workspace pills" : "Hidden: workspaces show numbers only"
            key: "showIcons"
          }

          ChoiceSetting {
            visible: root.cfg.showIcons
            title: "SHOW ICONS ON"
            key: "showApps"
            options: [
              { value: "all", label: "Always" },
              { value: "active", label: "Active" },
              { value: "hover", label: "Active + hover" },
              { value: "hoverOnly", label: "Hover" }
            ]
          }

          ChoiceSetting {
            visible: root.cfg.showIcons
            title: "ICON STYLE"
            key: "iconStyle"
            options: [
              { value: "color", label: "Color" },
              { value: "mono", label: "Monochrome" }
            ]
          }

          SliderSetting { visible: root.cfg.showIcons; title: "ICON SIZE"; key: "iconSize"; minimum: 12; maximum: 24; suffix: "px" }
          SliderSetting { visible: root.cfg.showIcons; title: "MAX ICONS PER WORKSPACE"; key: "maxIcons"; minimum: 1; maximum: 20 }

          ToggleSetting { visible: root.cfg.showIcons; label: "Group windows by app"; description: "One icon per app with a window count"; key: "groupApps" }
          ToggleSetting { visible: root.cfg.showIcons; label: "Dim unfocused windows"; description: "On the active workspace"; key: "dimUnfocused" }
          ToggleSetting { visible: root.cfg.showIcons; label: "Show focused window title"; description: "Next to its icon"; key: "focusedTitle" }

          PanelSeparator { foreground: root.fg }

          // ---- Appearance
          SectionTitle { text: "APPEARANCE" }

          ChoiceSetting {
            title: "ACTIVE WORKSPACE"
            key: "activeStyle"
            options: [
              { value: "subtle", label: "Subtle" },
              { value: "solid", label: "Solid" },
              { value: "accent", label: "Accent" }
            ]
          }

          ChoiceSetting {
            title: "WORKSPACE LABEL"
            key: "labelStyle"
            options: [
              { value: "number", label: "Number" },
              { value: "glyph", label: "Glyph" },
              { value: "none", label: "None" }
            ]
          }

          ChoiceSetting {
            title: "DENSITY"
            key: "density"
            options: [
              { value: "compact", label: "Compact" },
              { value: "normal", label: "Normal" },
              { value: "roomy", label: "Roomy" }
            ]
          }

          ChoiceSetting {
            title: "SETTINGS BUTTON"
            key: "settingsButton"
            options: [
              { value: "hover", label: "On hover" },
              { value: "always", label: "Always" },
              { value: "never", label: "Hidden" }
            ]
          }

          ToggleSetting { label: "Highlight urgent windows"; description: "Pulse workspaces with windows asking for attention"; key: "urgentHighlight" }
          ToggleSetting { label: "Tooltips"; description: "Window titles on hover"; key: "tooltips" }

          PanelSeparator { foreground: root.fg }

          // ---- Workspaces
          SectionTitle { text: "WORKSPACES" }

          SliderSetting { title: "ALWAYS SHOW WORKSPACES"; key: "persistentWorkspaces"; minimum: 0; maximum: 10 }
          ToggleSetting { label: "Hide empty workspaces"; key: "hideEmpty" }
          ToggleSetting { label: "Only this monitor's workspaces"; key: "perMonitor" }

          PanelSeparator { foreground: root.fg }

          // ---- Behavior
          SectionTitle { text: "BEHAVIOR" }

          ChoiceSetting {
            title: "CLICKING THE ACTIVE WORKSPACE"
            key: "activeClick"
            options: [
              { value: "none", label: "Does nothing" },
              { value: "previous", label: "Goes back" }
            ]
          }

          ToggleSetting { label: "Scroll to switch workspaces"; key: "scrollSwitch" }
          ToggleSetting { label: "Middle-click icon closes window"; key: "middleClickClose" }

          PanelSeparator { foreground: root.fg }

          // ---- Animation
          SectionTitle { text: "ANIMATION" }

          ToggleSetting { label: "Animations"; key: "animations" }

          ChoiceSetting {
            visible: root.cfg.animations
            title: "SPEED"
            key: "animationSpeed"
            options: [
              { value: "slow", label: "Slow" },
              { value: "normal", label: "Normal" },
              { value: "fast", label: "Fast" }
            ]
          }

          PanelSeparator { foreground: root.fg }

          Button {
            text: "Reset to defaults"
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.resetSettings()
          }
        }
      }
    }
  }

  component SectionTitle: Text {
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  component ChoiceSetting: Column {
    property string title: ""
    property string key: ""
    property var options: []

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    PanelSectionHeader {
      text: parent.title
      foreground: root.fg
      fontFamily: root.fontFamily
    }

    ButtonGroup {
      options: parent.options
      value: String(root.cfg[parent.key])
      foreground: root.fg
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      focusable: false
      onChanged: function(value) {
        var delta = ({})
        delta[parent.key] = value
        root.applySetting(delta)
      }
    }
  }

  component SliderSetting: Column {
    id: sliderSetting
    property string title: ""
    property string key: ""
    property int minimum: 0
    property int maximum: 10
    property string suffix: ""

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Item {
      width: parent.width
      implicitHeight: sliderHeader.implicitHeight
      PanelSectionHeader {
        id: sliderHeader
        text: sliderSetting.title
        foreground: root.fg
        fontFamily: root.fontFamily
      }
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(slider.liveValue) + sliderSetting.suffix
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }

    PanelSlider {
      id: slider
      width: parent.width
      bar: root.bar
      minimum: sliderSetting.minimum
      maximum: sliderSetting.maximum
      step: 1
      integer: true
      value: Number(root.cfg[sliderSetting.key])
      onReleased: function(value) {
        var delta = ({})
        delta[sliderSetting.key] = Math.round(value)
        root.applySetting(delta)
      }
    }
  }

  component ToggleSetting: Toggle {
    property string key: ""
    width: parent ? parent.width : 0
    checked: root.cfg[key] === true
    foreground: root.fg
    fontFamily: root.fontFamily
    onClicked: {
      var delta = ({})
      delta[key] = !checked
      root.applySetting(delta)
    }
  }
}
