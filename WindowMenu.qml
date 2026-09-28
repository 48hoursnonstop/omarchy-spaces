pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

Item {
  id: root
  property var manifest: null
  // The host injects our own service directly. No menu-side shell facade is
  // needed: on 4.0.4 its QVariantList capability path can revoke the service's
  // healthy facade. AppLibrary remains exclusively in SpacesService.
  property var service: null
  readonly property var bar: service && service.menuHost ? service.menuHost.bar : null
  property bool menuOpen: false
  readonly property bool opened: menuOpen
  property string menuKind: "window"
  property string menuPage: "main"
  property var menuTarget: ({})
  property int menuFocusIndex: -1
  readonly property bool menuTargetMinimized: service && menuTarget.address
    ? service.isMinimized(menuTarget.address) : false

  onMenuOpenChanged: {
    if (root.service) root.service.menuOpened = root.menuOpen
    root.menuFocusIndex = -1
    if (root.menuOpen) root.scheduleMenuFocus()
  }
  onMenuPageChanged: if (root.menuOpen) root.scheduleMenuFocus()
  onMenuFocusIndexChanged: Qt.callLater(root.revealMenuCursor)
  onBarChanged: if (!root.bar) root.close()
  Component.onDestruction: if (root.service) root.service.menuOpened = false

  function open(payloadJson) {
    root.close()
    if (!root.service || !root.bar) return
    let payload
    try { payload = JSON.parse(payloadJson || "{}") }
    catch (error) { root.service.lastError = "Invalid context menu payload"; return }
    root.menuKind = payload.kind === "launcher" || payload.kind === "workspace" ? payload.kind : "window"
    if (root.menuKind === "launcher") {
      if (!root.service.isApplicationPinned(payload.desktopId)) return
      root.menuTarget = payload
    } else if (root.menuKind === "workspace") {
      root.menuTarget = payload
    } else if (payload.addresses && payload.addresses.length > 1) {
      root.menuKind = "group"
      root.menuTarget = { addresses: payload.addresses }
    } else {
      const address = payload.address || root.service.activeWindowAddress()
      const target = root.service.windowForAddress(address)
      if (!target) return
      root.menuTarget = target
    }
    root.menuPage = "main"
    Hyprland.refreshMonitors()
    root.menuOpen = true
  }

  function close() {
    root.menuOpen = false
    root.menuFocusIndex = -1
  }
  function closeForPopoutSwitch() { root.close() }

  // Omarchy's KeyboardPanel owns real layer-shell keyboard focus. PopupCard
  // is an xdg-popup and cannot reliably receive arrow keys immediately after
  // a bar right-click, which is exactly the failure this menu must avoid.
  KeyboardPanel {
    id: windowMenu
    objectName: "windowActionsPanel"

    anchorItem: root.service && root.service.menuHost ? root.service.menuHost.menuAnchor : null
    bar: root.bar
    owner: root
    open: root.menuOpen
    focusTarget: menuKeyCatcher
    contentWidth: windowMenu.fittedContentWidth(Style.space(270))
    contentHeight: windowMenu.fittedContentHeight(menuColumn.implicitHeight)

    PanelKeyCatcher {
      id: menuKeyCatcher

      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveMenuCursor(dx, dy) }
      onActivateRequested: root.activateMenuCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.focusMenuDelta(direction) }

      Flickable {
        id: menuScroll
        objectName: "windowActionsScroll"
        anchors.fill: parent
        contentWidth: width
        contentHeight: menuColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: menuColumn

          width: menuScroll.width
          spacing: Style.spacing.xs

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.menuKind === "workspace" ? "Workspace " + root.displayWorkspace(root.menuTarget.workspaceName, root.menuTarget.workspace)
              : root.menuKind === "group" ? "Choose a window"
              : root.menuKind === "launcher"
              ? String(root.menuTarget.appName || "Pinned launcher")
              : (root.menuPage === "workspace"
                  ? "Move to workspace"
                  : (root.menuPage === "monitor"
                      ? "Move to monitor"
                      : (root.menuPage === "more"
                          ? "More window actions"
                          : String(root.menuTarget.title || root.menuTarget.appName || "Window"))))
            color: Color.menu.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.weight: Font.Medium
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            visible: root.menuKind === "launcher" || !!root.menuTarget.appName
            text: {
              if (root.menuKind === "launcher") return "Pinned launcher · not running"
              const workspace = root.displayWorkspace(root.menuTarget.workspaceName, root.menuTarget.workspace)
              if (root.menuPage === "workspace")
                return String(root.menuTarget.appName || "Window") + (workspace ? " · from " + workspace : "")
              if (root.menuPage === "more")
                return String(root.menuTarget.appName || "Window") + (workspace ? " · " + workspace : "")
              return String(root.menuTarget.appName || "") + (workspace ? " · " + workspace : "")
            }
            color: Color.menu.text
            opacity: 0.60
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Repeater {
            id: menuRepeater

            model: root.menuActions()

            delegate: Button {
              id: actionButton

              required property int index
              required property var modelData

              width: menuColumn.width
              implicitHeight: Math.max(Style.space(30), actionLabel.implicitHeight + verticalPadding * 2)
              text: ""
              enabled: modelData.enabled !== false && (!modelData.requiresBackend
                || (!!root.service && root.service.backendHealthy && root.service.protocolCompatible && !root.service.batchBusy
                  && !root.menuTarget.busy))
              opacity: enabled ? 1.0 : 0.45
              leftAlign: false
              focusable: false
              hasCursor: index === root.menuFocusIndex
              foreground: modelData.action === "close" ? Color.urgent : Color.menu.text
              accent: modelData.action === "close" ? Color.urgent : Color.menu.selectedBorder
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              horizontalPadding: Style.spacing.rowPaddingX
              verticalPadding: Style.spacing.controlPaddingY

              Text {
                id: actionIcon

                anchors.left: parent.left
                anchors.leftMargin: actionButton.horizontalPadding
                anchors.verticalCenter: parent.verticalCenter
                text: root.menuGlyph(actionButton.modelData)
                font.family: actionButton.fontFamily
                font.pixelSize: Style.font.body
                color: actionButton.modelData.action === "close"
                  ? Color.urgent
                  : (actionButton.hasCursor ? Color.menu.selectedText : Color.menu.text)
                opacity: 0.88
              }

              Text {
                id: actionLabel

                anchors.left: actionIcon.right
                anchors.leftMargin: Style.spacing.controlGap
                anchors.right: submenuChevron.visible ? submenuChevron.left : parent.right
                anchors.rightMargin: submenuChevron.visible ? Style.spacing.controlGap : actionButton.horizontalPadding
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: String(actionButton.modelData.label || "")
                color: actionButton.modelData.action === "close"
                  ? Color.urgent
                  : (actionButton.hasCursor ? Color.menu.selectedText : Color.menu.text)
                font.family: actionButton.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                id: submenuChevron

                visible: root.menuActionHasSubmenu(actionButton.modelData)
                anchors.right: parent.right
                anchors.rightMargin: actionButton.horizontalPadding
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf054"
                font.family: actionButton.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: actionButton.hasCursor ? Color.menu.selectedText : Color.menu.text
                opacity: 0.65
              }

              Accessible.role: Accessible.MenuItem
              Accessible.name: modelData.label
              Accessible.focusable: enabled
              Accessible.onPressAction: if (enabled) root.runMenuAction(modelData)

              onHovered: function(isHovered) {
                if (isHovered && enabled) root.menuFocusIndex = index
              }
              onClicked: root.runMenuAction(modelData)
            }
          }
        }
      }
    }
  }

  Connections {
    target: root.service
    function onWindowRowsChanged() {
      if (!root.menuOpen || root.menuKind !== "window") return
      var row = root.service.windowForAddress(root.menuTarget.address)
      if (!row) root.close()
      else root.menuTarget = row
    }
  }

  function menuGlyph(data) {
    const glyphs = {
      "arrow-left": "\uf060", "arrow-right": "\uf061", "square-plus": "\uf067",
      "square-arrow-out-up-right": "\uf08e", "pin": "\uf08d", "pin-off": "\uf08d",
      "minus": "\uf068", "undo-2": "\uf2d2", "minimize-2": "\uf066", "maximize-2": "\uf065",
      "picture-in-picture-2": "\uf24d", "layout-grid": "\uf00a", "monitor": "\uf108",
      "square-dashed": "\uf096", "move-right": "\uf061", "ellipsis": "\uf141",
      "panels-top-left": "\uf009", "scaling": "\uf065", "group": "\uf247", "x": "\uf00d"
    }
    return glyphs[root.menuIconFor(data)] || "\uf141"
  }

  function scheduleMenuFocus() {
    menuScroll.contentY = 0
    Qt.callLater(function() { root.focusFirstMenuAction() })
  }

  function revealMenuCursor() {
    const item = menuRepeater.itemAt(root.menuFocusIndex)
    if (!item) return
    const top = item.y
    const bottom = top + item.height
    if (top < menuScroll.contentY) menuScroll.contentY = top
    else if (bottom > menuScroll.contentY + menuScroll.height)
      menuScroll.contentY = Math.min(bottom - menuScroll.height, Math.max(0, menuScroll.contentHeight - menuScroll.height))
  }

  function focusFirstMenuAction() {
    if (!root.menuOpen) return
    for (let i = 0; i < menuRepeater.count; i++) {
      const item = menuRepeater.itemAt(i)
      if (!item || !item.enabled) continue
      root.menuFocusIndex = i
      return
    }
    root.menuFocusIndex = -1
  }

  function focusMenuDelta(delta) {
    if (!root.menuOpen || menuRepeater.count <= 0) return
    const count = menuRepeater.count
    let start = root.menuFocusIndex
    if (start < 0 || start >= count) start = delta >= 0 ? -1 : 0

    for (let step = 1; step <= count; step++) {
      const index = (start + delta * step + count * 2) % count
      const item = menuRepeater.itemAt(index)
      if (!item || !item.enabled) continue
      root.menuFocusIndex = index
      return
    }
  }

  function currentMenuAction() {
    if (root.menuFocusIndex < 0 || root.menuFocusIndex >= menuRepeater.count) return null
    const item = menuRepeater.itemAt(root.menuFocusIndex)
    return item && item.enabled ? item.modelData : null
  }

  function activateMenuCursor() {
    const action = root.currentMenuAction()
    if (action) root.runMenuAction(action)
  }

  function moveMenuCursor(dx, dy) {
    if (dy !== 0) {
      root.focusMenuDelta(dy > 0 ? 1 : -1)
      return
    }

    if (dx < 0) {
      if (root.menuPage !== "main") root.menuPage = "main"
      else root.close()
      return
    }

    if (dx > 0) {
      const action = root.currentMenuAction()
      if (!action) return
      if (root.menuActionHasSubmenu(action)) root.runMenuAction(action)
    }
  }

  function menuActionHasSubmenu(item) {
    const name = String(item && item.action || "")
    return name === "windows-menu" || name === "workspace-menu" || name === "monitor-menu" || name === "more-menu"
  }

  function menuIconFor(item) {
    const data = item || ({})
    const name = String(data.action || "")
    const label = String(data.label || "")
    const argument = String(data.argument || "")

    if (name === "menu-back") return "arrow-left"
    if (name === "show-desktop" || name === "workspace-layout") return "monitor"
    if (name === "restore-workspace") return "undo-2"
    if (name === "windows-menu" || name === "select-window") return "layout-grid"
    if (name === "launch-app") return label.indexOf("new") !== -1 ? "square-plus" : "square-arrow-out-up-right"
    if (name === "pin-app") return "pin"
    if (name === "unpin-app") return "pin-off"
    if (name === "pin-move") return Number(argument || 0) < 0 ? "arrow-left" : "arrow-right"
    if (name === "minimize") return "minus"
    if (name === "restore") return "undo-2"
    if (name === "maximized-toggle") return label.indexOf("Restore") === 0 ? "minimize-2" : "maximize-2"
    if (name === "pop-toggle") return "picture-in-picture-2"
    if (name === "workspace-menu") return "layout-grid"
    if (name === "monitor-menu" || name === "move-monitor") return "monitor"
    if (name === "move-workspace") return argument === "special:scratchpad" ? "square-dashed" : "move-right"
    if (name === "more-menu") return "ellipsis"
    if (name === "float-toggle") return label.indexOf("Tile") === 0 ? "panels-top-left" : "square-arrow-out-up-right"
    if (name === "fullscreen-toggle") return label.indexOf("Exit") === 0 ? "minimize-2" : "maximize-2"
    if (name === "pseudo-toggle") return "scaling"
    if (name === "group-toggle") return "group"
    if (name === "float-pin-toggle") return label.indexOf("Unpin") === 0 ? "pin-off" : "pin"
    if (name === "close") return "x"
    return "ellipsis"
  }

  function displayWorkspace(workspaceName, workspaceId) {
    const name = String(workspaceName || "")
    if (name === "special:scratchpad") return "Scratchpad"
    if (name.indexOf("special:") === 0) return "Special · " + name.slice("special:".length)
    if (name) return name
    const id = Number(workspaceId || 0)
    return id > 0 ? (id === 10 ? "0" : String(id)) : ""
  }

  function monitorRows() {
    const rows = []
    const values = Hyprland.monitors ? Hyprland.monitors.values : []
    for (let i = 0; i < values.length; i++) {
      const monitor = values[i]
      if (!monitor || !monitor.name) continue
      rows.push({
        id: Number(monitor.id),
        name: String(monitor.name),
        description: String(monitor.description || ""),
        focused: !!monitor.focused
      })
    }
    rows.sort(function(left, right) { return left.id - right.id })
    return rows
  }

  function monitorCount() {
    return root.monitorRows().length
  }

  function monitorMenuActions() {
    const actions = [{ label: "Back", action: "menu-back" }]
    const current = Number(root.menuTarget.monitorId)
    const monitors = root.monitorRows()
    for (let i = 0; i < monitors.length; i++) {
      const monitor = monitors[i]
      const isCurrent = monitor.id === current
      actions.push({
        label: monitor.name + (isCurrent ? " · current" : ""),
        action: "move-monitor",
        argument: monitor.name,
        enabled: !isCurrent
      })
    }
    return actions
  }

  function workspaceIds() {
    const host = root.service ? root.service.menuHost : null
    const count = host && host.cfg ? host.cfg.persistentWorkspaces : 5
    const ids = []
    for (let n = 1; n <= Math.max(1, count); n++) ids.push(n)
    const values = Hyprland.workspaces.values
    for (let i = 0; i < values.length; i++) {
      const id = Number(values[i].id)
      if (id > 0 && ids.indexOf(id) === -1) ids.push(id)
    }
    const rows = root.service ? root.service.windowRows : []
    for (let j = 0; j < rows.length; j++) {
      if (rows[j].workspace > 0 && ids.indexOf(rows[j].workspace) === -1) ids.push(rows[j].workspace)
    }
    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusedWorkspaceId() {
    return Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id || 0) : 0
  }

  function workspaceMenuActions() {
    const actions = [{ label: "Back", action: "menu-back" }]
    const current = Number(root.menuTarget.workspace || 0)
    const currentName = String(root.menuTarget.workspaceName || "")
    const ids = root.workspaceIds()
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i]
      actions.push({
        label: "Workspace " + (id === 10 ? "0" : String(id)) + (id === current && currentName.indexOf("special:") !== 0 ? " · current" : ""),
        action: "move-workspace",
        argument: String(id),
        enabled: !(id === current && currentName.indexOf("special:") !== 0)
      })
    }
    actions.push({
      label: "Scratchpad" + (currentName === "special:scratchpad" ? " · current" : ""),
      action: "move-workspace",
      argument: "special:scratchpad",
      enabled: currentName !== "special:scratchpad"
    })
    return actions
  }

  function moreMenuActions() {
    const actions = [{ label: "Back", action: "menu-back" }]
    actions.push({ label: root.menuTarget.floating ? "Tile window" : "Float window", action: "float-toggle" })
    actions.push({
      label: Number(root.menuTarget.fullscreen || 0) === 2 || Number(root.menuTarget.fullscreenClient || 0) === 2
        ? "Exit fullscreen"
        : "Enter fullscreen",
      action: "fullscreen-toggle"
    })
    actions.push({ label: root.menuTarget.pseudo ? "Disable pseudo" : "Enable pseudo", action: "pseudo-toggle" })
    actions.push({
      label: Number(root.menuTarget.groupedCount || 0) > 0
        ? "Toggle window group · " + String(root.menuTarget.groupedCount)
        : "Toggle window group",
      action: "group-toggle"
    })
    actions.push({ label: root.menuTarget.pinned ? "Unpin + tile" : "Float + pin", action: "float-pin-toggle" })
    return actions
  }

  function launcherMenuActions() {
    const id = String(root.menuTarget.desktopId || "")
    const index = root.service ? root.service.pinIndex(id) : -1
    const count = root.service ? root.service.pinnedDesktopIds.length : 0
    return [
      { label: "Open", action: "launch-app" },
      { label: "Move pin left", action: "pin-move", argument: "-1", enabled: index > 0 },
      { label: "Move pin right", action: "pin-move", argument: "1", enabled: index >= 0 && index < count - 1 },
      { label: "Unpin from Spaces", action: "unpin-app" }
    ]
  }

  function windowMenuActions() {
    const here = root.focusedWorkspaceId()
    const current = Number(root.menuTarget.workspace || 0)

    if (root.menuTargetMinimized) {
      const minimizedActions = []
      if (root.menuTarget.desktopId) {
        minimizedActions.push({ label: "Open new window", action: "launch-app" })
        minimizedActions.push({
          label: root.service && root.service.isApplicationPinned(root.menuTarget.desktopId)
            ? "Unpin from Spaces"
            : "Pin to Spaces",
          action: root.service && root.service.isApplicationPinned(root.menuTarget.desktopId) ? "unpin-app" : "pin-app"
        })
      }
      minimizedActions.push({ label: "Restore", action: "restore" })
      if (here > 0 && here !== current)
        minimizedActions.push({ label: "Move here · Workspace " + (here === 10 ? "0" : String(here)), action: "move-workspace", argument: String(here) })
      minimizedActions.push({ label: "Move to workspace…", action: "workspace-menu" })
      minimizedActions.push({ label: "Close", action: "close" })
      return minimizedActions
    }

    const maximized = Number(root.menuTarget.fullscreen || 0) === 1 || Number(root.menuTarget.fullscreenClient || 0) === 1
    const actions = []
    if (root.menuTarget.desktopId) {
      actions.push({ label: "Open new window", action: "launch-app" })
      actions.push({
        label: root.service && root.service.isApplicationPinned(root.menuTarget.desktopId)
          ? "Unpin from Spaces"
          : "Pin to Spaces",
        action: root.service && root.service.isApplicationPinned(root.menuTarget.desktopId) ? "unpin-app" : "pin-app"
      })
    }
    actions.push({ label: "Minimize", action: "minimize" })
    actions.push({ label: maximized ? "Restore size" : "Maximize", action: "maximized-toggle" })

    if (root.menuTarget.popped)
      actions.push({ label: "Return popped window", action: "pop-toggle" })
    else if (!root.menuTarget.floating && !root.menuTarget.pinned
        && Number(root.menuTarget.fullscreen || 0) === 0
        && Number(root.menuTarget.fullscreenClient || 0) === 0)
      actions.push({ label: "Pop out window", action: "pop-toggle" })

    if (here > 0 && here !== current)
      actions.push({ label: "Move here · Workspace " + (here === 10 ? "0" : String(here)), action: "move-workspace", argument: String(here) })

    actions.push({ label: "Move to workspace…", action: "workspace-menu" })
    if (root.monitorCount() > 1) actions.push({ label: "Move to monitor…", action: "monitor-menu" })
    if (!root.menuTarget.popped) actions.push({ label: "More window actions…", action: "more-menu" })
    actions.push({ label: "Close", action: "close" })
    return actions
  }

  function selectedWorkspaceRows() {
    return root.service ? root.service.windowRows.filter(function(row) {
      return row.workspace === Number(root.menuTarget.workspace)
    }) : []
  }

  function windowChoices() {
    const addresses = root.menuTarget.addresses || []
    const rows = root.menuKind === "group" && root.service ? root.service.windowRows.filter(function(row) {
      return addresses.indexOf(row.address) !== -1
    }) : root.selectedWorkspaceRows()
    const actions = root.menuKind === "workspace" ? [{ label: "Back", action: "menu-back" }] : []
    rows.forEach(function(row) {
      actions.push({ label: row.title + (row.minimized ? " · minimized" : ""), action: "select-window", argument: row.address, enabled: !row.busy })
    })
    return actions
  }

  function workspaceActions() {
    const rows = root.selectedWorkspaceRows()
    const hidden = rows.some(function(row) { return !!row.desktopBatch })
    const workspace = root.menuTarget.workspace
    const actions = [
      { label: hidden ? "Restore desktop" : "Show desktop", action: "show-desktop", argument: String(workspace), enabled: workspace > 0 && rows.length > 0 && !rows.some(function(row) { return row.busy }), requiresBackend: true },
      { label: "Restore minimized windows", action: "restore-workspace", argument: String(workspace), enabled: rows.some(function(row) { return row.minimized }), requiresBackend: true },
      { label: "Windows…", action: "windows-menu", enabled: rows.length > 0 }
    ]
    if (workspace === root.focusedWorkspaceId()) actions.push({ label: "Switch layout · Dwindle / Scrolling", action: "workspace-layout", argument: String(workspace) })
    return actions
  }

  function menuActions() {
    let actions
    if (root.menuKind === "launcher") actions = root.launcherMenuActions()
    else if (root.menuKind === "group" || root.menuPage === "windows") actions = root.windowChoices()
    else if (root.menuKind === "workspace") actions = root.workspaceActions()
    else if (root.menuPage === "workspace") actions = root.workspaceMenuActions()
    else if (root.menuPage === "monitor") actions = root.monitorMenuActions()
    else if (root.menuPage === "more") actions = root.moreMenuActions()
    else actions = root.windowMenuActions()
    const mutations = ["minimize", "restore", "maximized-toggle", "pop-toggle", "move-workspace", "move-monitor", "float-toggle", "fullscreen-toggle", "pseudo-toggle", "group-toggle", "float-pin-toggle"]
    return actions.map(function(action) {
      return mutations.indexOf(action.action) < 0 ? action : Object.assign({}, action, { requiresBackend: true })
    })
  }

  function runMenuAction(item) {
    if (!root.service) return
    const data = item || ({})
    const name = typeof data === "string" ? String(data) : String(data.action || "")
    const argument = typeof data === "string" ? "" : String(data.argument || "")

    if (name === "select-window") {
      const row = root.service.windowForAddress(argument)
      if (!row) return
      root.menuKind = "window"
      root.menuTarget = row
      root.menuPage = "main"
      root.scheduleMenuFocus()
      return
    }
    if (name === "windows-menu") { root.menuPage = "windows"; return }
    if (name === "show-desktop") { root.service.showDesktop(argument); root.close(); return }
    if (name === "restore-workspace") { root.service.restoreWorkspace(argument); root.close(); return }
    if (name === "workspace-layout") {
      if (root.service.menuHost) root.service.menuHost.toggleWorkspaceLayout(argument)
      root.close()
      return
    }

    if (name === "workspace-menu") {
      root.menuPage = "workspace"
      return
    }
    if (name === "monitor-menu") {
      root.menuPage = "monitor"
      return
    }
    if (name === "more-menu") {
      root.menuPage = "more"
      return
    }
    if (name === "menu-back") {
      root.menuPage = "main"
      return
    }

    if (root.menuKind === "launcher") {
      const desktopId = String(root.menuTarget.desktopId || "")
      if (name === "launch-app") root.service.launchApplication(desktopId, String(root.menuTarget.appName || ""))
      else if (name === "unpin-app") root.service.unpinApplication(desktopId)
      else if (name === "pin-move") root.service.movePinnedApplication(desktopId, Number(argument || 0))
      root.close()
      return
    }

    if (name === "launch-app") {
      root.service.launchApplication(String(root.menuTarget.desktopId || ""), String(root.menuTarget.appName || ""))
      root.close()
      return
    }

    if (name === "pin-app" || name === "unpin-app") {
      const desktopId = String(root.menuTarget.desktopId || "")
      if (name === "pin-app") root.service.pinApplication(desktopId)
      else root.service.unpinApplication(desktopId)
      root.close()
      return
    }

    if (!root.menuTarget.address) return
    root.service.menuAction(name, String(root.menuTarget.address), argument)
    root.close()
  }
}
