import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
ShellRoot {
  id: testRoot
  property var spaces: null
  property var contextMenu: null
  property int stage: 0
  property int ticks: 0
  property bool keysDone: false
  property var menuPanel: null
  function check(value, message) {
    if (!value) { console.error("FAIL", message); Qt.quit(); throw new Error(message) }
  }
  function capture(item, name, nextStage) {
    if (nextStage !== undefined) testRoot.stage = -1
    check(item.grabToImage(function(result) {
      check(result.saveToFile(Quickshell.env("SPACES_UI_ARTIFACTS") + "/" + name + ".png"), "Could not save " + name)
      if (nextStage !== undefined) testRoot.stage = nextStage
    }), "Could not capture " + name)
  }
  function keys(args) {
    keysDone = false
    let command = ["wtype", "-s", "150"]
    for (let i = 0; i < args.length; i += 2) command = command.concat(args.slice(i, i + 2), ["-s", "70"])
    keySender.command = command
    keySender.running = true
  }
  Process {
    id: keySender
    onExited: function(code) { testRoot.check(code === 0, "Keyboard injection failed"); testRoot.keysDone = true }
  }
  Component.onCompleted: {
    var menuComponent = Qt.createComponent("plugin/WindowMenu.qml")
    contextMenu = menuComponent.createObject(canvas, { service: fixture })
    console.warn("MENU_CREATE", menuComponent.status, menuComponent.errorString(), contextMenu)
    var widgetComponent = Qt.createComponent("plugin/Spaces.qml")
    spaces = widgetComponent.createObject(canvas, { bar: fakeBar, x: 0, y: 0, settings: { showApps: "all", animations: false, persistentWorkspaces: 5, settingsButton: "always" } })
    console.warn("WIDGET_CREATE", widgetComponent.status, widgetComponent.errorString(), spaces)
  }
  QtObject {
    id: api
    function serviceFor(id) { return fixture }
    function summon(id, payload) { contextMenu.open(payload); return true }
    function hide(id) { contextMenu.close() }
    function updateEntryInline(id, settings) { return true }
  }
  QtObject {
    id: fakeBar
    property var shell: api
    property bool vertical: false
    property string position: "top"
    property int barSize: 36
    property color barForeground: Color.foreground
    property color foreground: Color.foreground
    property color background: Color.background
    property color urgent: Color.urgent
    property string fontFamily: "JetBrainsMono Nerd Font"
    property var activePopout: null
    function run(command) { console.warn("RUN", command) }
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { activePopout = null }
    function moduleWidgets(id) { return [spaces] }
  }
  QtObject {
    id: fixture
    property bool backendHealthy: true
    property bool protocolCompatible: true
    property bool appLibraryHealthy: true
    property bool batchBusy: false
    property bool menuOpened: false
    property int orphanHiddenCount: 0
    property string lastError: ""
    property string appLibraryDiagnostic: "ok"
    property var menuHost: null
    property var pinnedDesktopIds: ["files"]
    property var appPresentationById: ({ terminal: { name: "Terminal", icon: "file:///usr/share/icons/HighContrast/48x48/apps/utilities-terminal.png" }, browser: { name: "Browser", icon: "file:///usr/share/icons/HighContrast/48x48/apps/web-browser.png" }, files: { name: "Files", icon: "file:///usr/share/icons/HighContrast/48x48/apps/system-file-manager.png" } })
    property var minimizedRecordsByAddress: ({ "0xb": { at: [800, 0], size: [800, 900] } })
    property var windowRows: [
      { address: "0xa", title: "Project terminal", appName: "Terminal", appId: "terminal", desktopId: "terminal", workspace: 1, workspaceName: "1", monitorId: -1, minimized: false, active: true, busy: false, popped: false, pid: 101, floating: false, pinned: false, fullscreen: 0, groupedCount: 0 },
      { address: "0xb", title: "Documentation — a long title that should elide cleanly inside the minimized preview chip", appName: "Browser", appId: "browser", desktopId: "browser", workspace: 1, workspaceName: "1", monitorId: -1, minimized: true, active: false, busy: false, desktopBatch: "desktop:1:1", popped: false, pid: 102, floating: false, pinned: false, fullscreen: 0, groupedCount: 0 },
      { address: "0xc", title: "Agent terminal", appName: "Terminal", appId: "terminal", desktopId: "terminal", workspace: 3, workspaceName: "3", monitorId: -1, minimized: false, active: false, busy: false, popped: true, pid: 103, floating: true, pinned: true, fullscreen: 0, groupedCount: 0 }
    ]
    property var pinnedLaunchers: ListModel {
      ListElement { desktopId: "files"; appName: "Files"; iconSource: "file:///usr/share/icons/HighContrast/48x48/apps/system-file-manager.png"; pinIndex: 0 }
    }
    function windowForAddress(address) { return windowRows.find(function(row) { return row.address === address }) || null }
    function isMinimized(address) { var row = windowForAddress(address); return row ? row.minimized : false }
    function isApplicationPinned(id) { return pinnedDesktopIds.indexOf(id) >= 0 }
    function pinIndex(id) { return pinnedDesktopIds.indexOf(id) }
    function activateWindow(address, minimizeActive) { console.warn("ACTIVATE", address, minimizeActive); return true }
    function closeWindow(address) { console.warn("CLOSE", address); return true }
    function menuAction(action, address, argument) { console.warn("ACTION", action, address, argument); return true }
    function showDesktop(id) { console.warn("DESKTOP", id); return true }
    function restoreWorkspace(id) { console.warn("RESTORE", id); return true }
    function restoreLast() { return true }
    function restoreAll() { return true }
    function recover() { return true }
    function launchApplication(id, name) { return true }
  }
  PanelWindow {
    id: window
    visible: true
    anchors.top: fakeBar.position !== "bottom"
    anchors.bottom: fakeBar.vertical || fakeBar.position === "bottom"
    anchors.left: fakeBar.position !== "right"
    anchors.right: !fakeBar.vertical || fakeBar.position === "right"
    implicitWidth: fakeBar.barSize
    implicitHeight: fakeBar.barSize
    color: Color.background
    Rectangle {
      id: canvas
      color: Color.background
      anchors.fill: parent

    }
  }
  Timer {
    interval: 300
    repeat: true
    running: true
    onTriggered: {
      testRoot.ticks++
      testRoot.check(testRoot.ticks < 80, "UI test timed out at stage " + testRoot.stage)
      switch (testRoot.stage) {
      case 0:
        testRoot.check(!!spaces && !!contextMenu, "Components did not load")
        testRoot.check(spaces.workspaceMap[1].windows.length === 2, "Lost minimized window")
        spaces.applyAgent("fixture-agent", "waiting", "103")
        testRoot.capture(canvas, "horizontal")
        spaces.openWorkspaceMenu(spaces, spaces.workspaceMap[1])
        menuPanel = contextMenu.data.find(function(item) { return item.objectName === "windowActionsPanel" })
        testRoot.stage = 1
        break
      case 1:
        testRoot.check(contextMenu.opened && menuPanel.visible, "Workspace menu did not open")
        // labwc without a physical seat releases OnDemand focus when wtype
        // creates its virtual keyboard. Hold the host's focus prime in this
        // fixture; real Hyprland's focus handoff remains a release check.
        menuPanel.focusPrimed = false
        testRoot.capture(menuPanel.contentItem[0].parent.parent, "workspace-menu")
        // Actual Wayland keys through the native KeyboardPanel and PanelKeyCatcher.
        testRoot.keys(["-k", "Down", "-k", "Down", "-k", "Right"])
        testRoot.stage = 2
        break
      case 2:
        if (!testRoot.keysDone) break
        testRoot.check(contextMenu.menuPage === "windows", "Arrow keys did not open the window chooser")
        testRoot.keys(["-k", "Down", "-k", "Return"])
        testRoot.stage = 3
        break
      case 3:
        if (!testRoot.keysDone) break
        testRoot.check(contextMenu.menuKind === "window" && contextMenu.menuTarget.address === "0xa", "Keyboard selected wrong window")
        testRoot.capture(menuPanel.contentItem[0].parent.parent, "window-menu")
        testRoot.keys(["-k", "Escape"])
        testRoot.stage = 4
        break
      case 4:
        if (!testRoot.keysDone) break
        testRoot.check(!contextMenu.opened, "Escape did not dismiss the menu")
        spaces.openWindowMenu(spaces, { address: "0xb", addresses: ["0xa", "0xb"] })
        testRoot.stage = 5
        break
      case 5:
        testRoot.check(contextMenu.menuKind === "group", "Group did not offer an explicit window choice")
        testRoot.check(contextMenu.menuActions().length === 2, "Group lost a minimized window")
        contextMenu.runMenuAction(contextMenu.menuActions()[1])
        testRoot.check(contextMenu.menuTargetMinimized, "Group choice lost minimized state")
        testRoot.check(contextMenu.menuActions().some(function(a) { return a.action === "restore" }), "Restore action missing")
        testRoot.capture(menuPanel.contentItem[0].parent.parent, "minimized-menu", 51)
        break
      case 51:
        contextMenu.close()
        testRoot.check(spaces.peek(1), "Preview did not open")
        testRoot.stage = 6
        break
      case 6:
        testRoot.check(spaces.previewOpen, "Minimized workspace has no preview")
        const preview = spaces.data.find(function(item) { return item.objectName === "workspacePreview" })
        testRoot.check(preview.workspace.windows.filter(function(w) { return w.minimized }).length === 1 && preview.workspace.windows.length === 2, "Preview lost minimized window restore targets")
        testRoot.capture(preview.contentItem[0].parent.parent, "preview", 61)
        break
      case 61:
        fakeBar.vertical = true
        fakeBar.position = "left"
        spaces.hidePreview()
        testRoot.stage = 7
        break
      case 7:
        testRoot.check(spaces.implicitHeight > spaces.implicitWidth, "Vertical layout collapsed")
        testRoot.capture(canvas, "vertical", 71)
        break
      case 71:
        const many = fixture.windowRows.slice()
        for (let i = 0; i < 45; i++) many.push(Object.assign({}, many[0], { address: "0x" + (1000 + i).toString(16), title: "Window " + (i + 1), workspace: 4, active: false }))
        fixture.windowRows = many
        spaces.openWorkspaceMenu(spaces, spaces.workspaceMap[4])
        contextMenu.runMenuAction({ action: "windows-menu" })
        testRoot.stage = 8
        break
      case 8:
        contextMenu.menuFocusIndex = contextMenu.menuActions().length - 1
        testRoot.stage = 9
        break
      case 9:
        const scroll = menuPanel.contentItem[0].children[0]
        testRoot.check(scroll.contentHeight > scroll.height && scroll.contentY > 0, "Long menus are not scrollable")
        testRoot.check(contextMenu.currentMenuAction().label === "Window 45", "Last window is unreachable")
        testRoot.capture(menuPanel.contentItem[0].parent.parent, "long-menu")
        menuPanel.focusPrimed = false
        testRoot.keys(["-k", "Return"])
        testRoot.stage = 10
        break
      case 10:
        if (!testRoot.keysDone) break
        testRoot.check(contextMenu.menuKind === "window" && contextMenu.menuTarget.title === "Window 45", "Could not select a scrolled window")
        contextMenu.close()
        fixture.windowRows = fixture.windowRows.slice(0, 3)
        fixture.backendHealthy = false
        testRoot.check(spaces.healthMessage.length > 0, "Missing helper is not visible")
        spaces.openWindowMenu(spaces, { address: "0xa" })
        testRoot.stage = 11
        break
      case 11:
        contextMenu.menuFocusIndex = contextMenu.menuActions().findIndex(function(a) { return a.action === "minimize" })
        testRoot.check(!contextMenu.currentMenuAction(), "Broken helper still permits minimize")
        testRoot.capture(canvas, "helper-unavailable")
        testRoot.stage = 12
        break
      case 12:
        contextMenu.close()
        fakeBar.vertical = false
        fakeBar.position = "bottom"
        fixture.backendHealthy = true
        testRoot.stage = 13
        break
      case 13:
        testRoot.capture(canvas, "bottom", 131)
        break
      case 131:
        fakeBar.vertical = true
        fakeBar.position = "right"
        testRoot.stage = 14
        break
      case 14:
        testRoot.capture(canvas, "right", 15)
        break
      case 15:
        console.warn("UI_TESTS_OK")
        Qt.quit()
      }
    }
  }
}
