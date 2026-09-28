import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
  id: test
  property int stage: 0
  property int ticks: 0
  function check(value, message) {
    if (!value) { console.error("FAIL", message); Qt.quit() }
  }

  QtObject {
    id: libraryApi
    function sortedEntries(query) { return [{ id: "terminal", name: "Terminal", icon: "terminal", startupClass: "Foot", execString: "foot" }] }
    function entryName(entry) { return entry.name }
    function iconSource(icon) { return "image://icon/" + icon }
    function refreshIcons() {}
    function launch(id, name) {}
    signal appsChanged()
  }
  QtObject { id: facade; property var appLibrary: libraryApi }
  Plugin.SpacesService { id: service; shell: facade }

  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      test.ticks++
      if (test.ticks > 80) { console.error("FAIL timeout", service.status()); Qt.quit(); return }
      if (test.stage === 0 && service.backendHealthy && service.windowRows.length === 2) {
        test.check(service.appLibraryHealthy, "AppLibrary unavailable")
        test.check(service.windowRows[0].matched, "Minimized application was not matched")
        test.check(service.windowRows[0].workspace === 3 && service.windowRows[0].monitorId === 2, "Lost original workspace/monitor")
        test.check(service.pinApplication("terminal"), "Could not pin an application")
        test.check(service.pinnedLaunchers.count === 0, "Pinned app duplicates a minimized running window")
        test.check(service.showDesktop(3), "Workspace action was not enqueued")
        test.check(!service.showDesktop(3), "Duplicate workspace action was accepted")
        test.check(service.windowRows.every(function(row) { return row.busy }), "Batch busy feedback missing")
        test.stage = 1
      } else if (test.stage === 1 && !service.batchBusy && !service.activeJob) {
        test.check(service.windowRows.every(function(row) { return !row.busy }), "Batch left windows busy")
        test.check(service.menuAction("float-toggle", "0xaaa"), "Action was not enqueued")
        test.check(!service.menuAction("float-toggle", "0xbbb"), "A grouped sibling accepted a duplicate operation")
        test.stage = 2
      } else if (test.stage === 2 && !service.activeJob && service.lastError === "fixture action failure") {
        service.requestSnapshot()
        test.stage = 3
      } else if (test.stage === 3 && !service.activeJob && service.backendQueue.length === 0) {
        test.check(service.lastError === "fixture action failure", "Snapshot erased the action error")
        test.check(service.windowRows.every(function(row) { return !row.busy }), "Failed action left windows busy")
        service.parsePins("broken JSON")
        test.check(service.pinnedDesktopIds[0] === "terminal", "Invalid preference file discarded pins")
        console.warn("SERVICE_TESTS_OK")
        Qt.quit()
      }
    }
  }
}
