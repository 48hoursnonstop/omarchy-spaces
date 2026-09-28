import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugin" as Plugin

ShellRoot {
  id: testRoot
  property var spaces: null
  property var menu: null
  property var desktop: null
  property var original: null
  property string comparison: ""
  property bool comparisonDone: false
  property int comparisonStage: 0
  Component.onCompleted: {
    desktop = Qt.createComponent("plugin/ShowDesktop.qml").createObject(canvas, { bar: bar })
    desktop.x = Qt.binding(function() { return canvas.width - desktop.width - 8 })
    menu = Qt.createComponent("plugin/WindowMenu.qml").createObject(canvas, { service: service })
    spaces = Qt.createComponent("plugin/Spaces.qml").createObject(canvas, {
      bar: bar, settings: { showApps: "all", persistentWorkspaces: 5, animations: false, settingsButton: "always" }
    })
  }
  // Only the host's application catalog is a fixture. Windows, compositor,
  // service, transactions, menu focus and preview capture are real.
  QtObject {
    id: libraryApi
    function sortedEntries(query) { return [{ id: "foot", name: "Foot", icon: "foot", startupClass: "foot", execString: "foot" }] }
    function entryName(entry) { return entry.name }
    function iconSource(icon) { return "file:///usr/share/icons/HighContrast/48x48/apps/utilities-terminal.png" }
    function refreshIcons() {}
    function launch(id, name) {}
    signal appsChanged()
  }
  QtObject {
    id: facade
    property var appLibrary: libraryApi
    function serviceFor(id) { return service }
    function summon(id, payload) { menu.open(payload); return true }
    function hide(id) { menu.close() }
  }
  Plugin.SpacesService { id: service; shell: facade }
  QtObject {
    id: bar
    property var shell: facade
    property bool vertical: false
    property string position: "top"
    property int barSize: 36
    property color foreground: Color.foreground
    property color barForeground: Color.foreground
    property color background: Color.background
    property color urgent: Color.urgent
    property string fontFamily: "JetBrainsMono Nerd Font"
    property var activePopout: null
    function run(command) { Quickshell.execDetached(["bash", "-c", command]) }
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function moduleWidgets(id) { return [spaces] }
  }
  PanelWindow {
    visible: true
    anchors { top: true; left: true; right: true }
    implicitHeight: bar.barSize
    color: Color.background
    Rectangle { id: canvas; anchors.fill: parent; color: Color.background }
  }
  Timer {
    id: comparisonTimer
    interval: 700
    onTriggered: {
      if (testRoot.comparisonStage === 0) {
        spaces.grabToImage(function(result) {
          result.saveToFile(Quickshell.env("SPACES_UI_ARTIFACTS") + "/fork-" + comparison + ".png")
          spaces.visible = false
          original.visible = true
          testRoot.comparisonStage = 1
          comparisonTimer.restart()
        })
      } else {
        original.grabToImage(function(result) {
          result.saveToFile(Quickshell.env("SPACES_UI_ARTIFACTS") + "/upstream-" + comparison + ".png")
          original.destroy()
          original = null
          spaces.visible = true
          comparisonDone = true
        })
      }
    }
  }
  IpcHandler {
    target: "spaces-test"
    function status(): string {
      const status = JSON.parse(service.status())
      status.workspace = spaces ? spaces.currentWorkspaceId : 0
      status.projected = spaces && spaces.workspaceMap[3] ? spaces.workspaceMap[3].windows.length : 0
      status.menuOpen = menu && menu.opened
      const panel = menu ? menu.data.find(function(item) { return item.objectName === "windowActionsPanel" }) : null
      status.menuFocus = !!panel && panel.focusTarget.activeFocus
      status.comparisonDone = comparisonDone
      status.previewOpen = !!spaces && spaces.previewOpen
      return JSON.stringify(status)
    }
    function desktopClick(): void { desktop.toggleDesktop() }
    function compare(name: string, settings: string): void {
      spaces.hidePreview()
      comparison = name
      comparisonDone = false
      comparisonStage = 0
      spaces.settings = JSON.parse(settings)
      original = Qt.createComponent("upstream/Spaces.qml").createObject(canvas, { bar: bar, settings: JSON.parse(settings), visible: false })
      comparisonTimer.start()
    }
    function minimize(address: string): bool { return service.menuAction("minimize", address) }
    function restore(address: string): bool { return service.menuAction("restore", address) }
    function openMenu(address: string): void { spaces.openWindowMenu(spaces, { address: address }) }
    function preview(workspace: int): bool { return spaces.peek(workspace) }
  }
}
