import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// A separate end-of-bar strip; the Spaces workspace pills keep upstream's UI.
BarWidget {
  id: root
  moduleName: "tornikegomareli.spaces.desktop"
  implicitWidth: vertical ? barSize : Style.space(8)
  implicitHeight: vertical ? Style.space(8) : barSize
  readonly property var monitor: {
    var window = root.QsWindow.window
    return window && window.screen ? Hyprland.monitorFor(window.screen) : null
  }
  readonly property int workspace: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id
    : Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  property string errorMessage: ""
  readonly property string label: errorMessage || "Show / restore desktop"
  enabled: workspace > 0 && !request.running
  activeFocusOnTab: enabled
  Accessible.role: Accessible.Button
  Accessible.name: label
  Accessible.onPressAction: toggleDesktop()
  Keys.onReturnPressed: toggleDesktop()
  Keys.onEnterPressed: toggleDesktop()
  Keys.onSpacePressed: toggleDesktop()

  function toggleDesktop() {
    if (!enabled) return
    errorMessage = ""
    // Public IPC shares Spaces' serialized transactions, including its batch
    // restoration rules. This custom bar entry owns no second window service.
    request.command = ["omarchy-shell", "tornikegomareli.spaces", "showDesktop", String(workspace)]
    request.running = true
  }
  Process {
    id: request
    stdout: StdioCollector { id: reply }
    onExited: function(code) {
      if (code !== 0 || reply.text.trim() !== "ok") {
        root.errorMessage = "Desktop controls unavailable. Check Spaces settings."
        if (root.bar) root.bar.showTooltip(root, root.errorMessage)
      }
    }
  }
  // Omarchy 4's native bar reserves 8px after the final slot. Extend the
  // hit area through that margin so the screen corner is clickable too.
  Item {
    anchors.fill: parent
    anchors.rightMargin: root.vertical ? 0 : -Style.space(8)
    anchors.bottomMargin: root.vertical ? -Style.space(8) : 0
    Rectangle {
      anchors.fill: parent
      color: mouse.containsMouse || root.activeFocus ? Util.alpha(root.foreground, 0.15) : "transparent"
      opacity: mouse.pressed ? 0.65 : 1
    }
    Rectangle {
      width: root.vertical ? parent.width : 1
      height: root.vertical ? 1 : parent.height
      color: Util.alpha(root.foreground, 0.3)
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleDesktop()
      onContainsMouseChanged: {
        if (!root.bar) return
        if (containsMouse) root.bar.showTooltip(root, root.label)
        else root.bar.hideTooltip(root)
      }
    }
  }
}
