import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Screensaver Lock service.
//
// Stock omarchy.idle only locks if the screensaver is still up at idle.lock;
// dismissing it earlier skips the lock. This service locks on every dismissal.
//
// Locking after the screensaver closes would show the desktop until the lock
// screen is up, so a black curtain covers that gap. While a screensaver is open
// the curtain is mapped on the Top layer but transparent: Hyprland draws the
// Top layer above the fullscreen screensaver, so it cannot be opaque yet. When
// the screensaver window closes the curtain turns black in the same frame (a
// buffer commit, not a new surface, so no layer fade-in), and the lock is
// requested behind it. The curtain drops lockSettleMs after the lock is
// confirmed, when the lock screen covers everything, so nothing polls while
// locked. It is click-through and drops after curtainTimeoutMs if the lock
// never arrives.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  readonly property string screensaverClass: "org.omarchy.screensaver"
  readonly property int curtainTimeoutMs: 8000
  readonly property int lockSettleMs: 2000

  property var screensavers: ({})
  property bool curtain: false
  // Test mode (IPC): raise the curtain but do not lock on dismissal.
  property bool dryRun: false

  function log(message) {
    console.log("screensaver-lock: " + message)
  }

  function eventParts(event, count) {
    try {
      if (event && event.parse) return event.parse(count)
    } catch (error) {
    }
    return String(event && event.data ? event.data : "").split(",")
  }

  function raiseCurtain(reason) {
    if (!root.curtain) log("curtain up (" + reason + ")")
    root.curtain = true
  }

  function dropCurtain(reason) {
    if (root.curtain) log("curtain down (" + reason + ")")
    root.curtain = false
    curtainTimeout.stop()
    lockPoll.stop()
    lockSettle.stop()
  }

  function screensaverOpened(address) {
    var next = Object.assign({}, root.screensavers)
    next[address] = true
    root.screensavers = next
  }

  function screensaverClosed(address) {
    var next = Object.assign({}, root.screensavers)
    delete next[address]
    root.screensavers = next

    // Lock (or confirm we already are) behind the curtain.
    raiseCurtain("screensaver " + address + " closed")
    curtainTimeout.restart()
    if (root.dryRun) {
      log("dry run: screensaver " + address + " closed, not locking")
      return
    }
    if (!lockProcess.running) lockProcess.running = true
    lockPoll.restart()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      if (name === "openwindow") {
        var open = root.eventParts(event, 4)
        if (String(open[2] || "") === root.screensaverClass) root.screensaverOpened(String(open[0]))
      } else if (name === "closewindow") {
        var address = String(root.eventParts(event, 1)[0] || "")
        if (root.screensavers[address]) root.screensaverClosed(address)
      }
    }
  }

  // Locks unless the session is already locked (the stock idle lock is what
  // closes the screensaver in that case).
  Process {
    id: lockProcess
    command: ["bash", "-lc", "if [[ $(omarchy-shell lock isLocked 2>/dev/null) == true ]]; then echo already-locked; else echo locking; omarchy-system-lock; fi"]
    stdout: SplitParser { onRead: line => root.log(line) }
  }

  // Wait for the lock, then let the lock screen settle before dropping.
  Timer {
    id: lockPoll
    interval: 100
    repeat: true
    onTriggered: if (!lockState.running) lockState.running = true
  }

  Process {
    id: lockState
    command: ["omarchy-shell", "lock", "isLocked"]
    stdout: SplitParser {
      onRead: line => {
        if (String(line).trim() !== "true" || !lockPoll.running) return
        lockPoll.stop()
        curtainTimeout.stop()
        root.log("locked")
        lockSettle.restart()
      }
    }
  }

  Timer {
    id: lockSettle
    interval: root.lockSettleMs
    onTriggered: root.dropCurtain("lock screen up")
  }

  Timer {
    id: curtainTimeout
    interval: root.curtainTimeoutMs
    onTriggered: {
      root.log("lock not confirmed within " + root.curtainTimeoutMs + " ms")
      root.dropCurtain("timeout")
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.curtain || Object.keys(root.screensavers).length > 0
      anchors { top: true; bottom: true; left: true; right: true }
      color: root.curtain ? "black" : "transparent"
      WlrLayershell.namespace: "davidboulay-screensaver-curtain"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}
    }
  }

  IpcHandler {
    target: "screensaverLock"

    function status(): string {
      return JSON.stringify({ curtain: root.curtain, dryRun: root.dryRun, screensavers: Object.keys(root.screensavers) })
    }
    function curtainUp(): string { root.raiseCurtain("ipc"); curtainTimeout.restart(); return "ok" }
    function curtainDown(): string { root.dropCurtain("ipc"); return "ok" }
    function setDryRun(value: bool): string { root.dryRun = value; return "dryRun=" + value }
  }
}
