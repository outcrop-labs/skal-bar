import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Desktop notifications for the quick action toggles. Lives on the bar, not
// the menu widget: the widget is instantiated once per bar surface (per
// monitor) and would toast once per screen, while the toggled state is
// machine-wide. Watching the services themselves — rather than the buttons —
// means every source dispatches: panel tiles, hotkeys, the `omarchy` CLI,
// even another plugin flipping the same service.
Item {
  id: root

  // Injected by the host shell, same handle the bar passes its widgets.
  property var shell: null
  // The bar singleton, which owns the file-watched ground-truth state the
  // toasts below read. Service objects die with the host's scoped api
  // (Omarchy 4.0.3); the bar's watchers do not.
  property var barHost: null

  // Services attach asynchronously and re-apply persisted state shortly
  // after load (the idle service probes its flag file, night light reads its
  // schedule). Announcing those load-time flips would toast on every shell
  // start, so stay quiet for a short grace after the bar comes up.
  property bool armed: false

  readonly property var nightlightService: shell ? shell.firstPartyServiceFor("omarchy.nightlight") : null

  // Each action keeps one notification id, so re-toggling replaces the toast
  // instead of stacking a new one.
  readonly property int dndNotificationId: 101
  readonly property int nightlightNotificationId: 102
  readonly property int stayAwakeNotificationId: 103
  readonly property int dictationNotificationId: 104

  function send(glyph, headline, description, replaceId) {
    // Default app-name (omarchy-action) on purpose: the notification daemon
    // lets user-action confirmations through do-not-disturb, and these are
    // exactly that — the user just flipped a switch.
    var argv = ["omarchy-notification-send",
      "-g", glyph, "-u", "low", "-r", String(replaceId), headline]
    if (description !== undefined && description !== null && description !== "")
      argv.push(String(description))
    Util.execArgv(argv)
  }

  function notify(glyph, headline, description, replaceId) {
    if (!armed) return
    send(glyph, headline, description, replaceId)
  }

  // Dictation is the one action with no service to watch — voxtype keeps its
  // state inside the daemon — so both the panel tile and the hotkey IPC call
  // this instead: toggle, give the daemon a beat to flip, then read its
  // status once for the announcement.
  function toggleDictation() {
    Util.execArgv(["voxtype", "record", "toggle"])
    dictationProbeDelay.restart()
  }

  // The quick menu probes on open so the tile reflects the daemon state.
  function probeDictation() {
    if (!dictationProbe.running) dictationProbe.running = true
  }

  // The daemon is probed on every panel open (for the tile's active state),
  // so toast only when the state actually changes — never for a first read.
  property bool dictationSeen: false
  property string lastDictationState: ""

  function notifyDictationState(status) {
    var state = String(status || "").trim()
    if (root.barHost) root.barHost.dictationActive = state.indexOf("record") !== -1
    if (!root.dictationSeen) {
      root.dictationSeen = true
      root.lastDictationState = state
      return
    }
    if (state === root.lastDictationState) return
    root.lastDictationState = state
    if (state.indexOf("record") !== -1)
      root.send("󰍬", "Dictation recording", "Speech is being transcribed", root.dictationNotificationId)
    else if (state === "idle")
      root.send("󰍬", "Dictation stopped", "", root.dictationNotificationId)
    else
      root.send("󰍬", "Dictation", state, root.dictationNotificationId)
  }

  Component.onCompleted: armTimer.start()

  Timer {
    id: armTimer
    interval: 3000
    onTriggered: root.armed = true
  }

  Timer {
    id: dictationProbeDelay
    interval: 500
    onTriggered: if (!dictationProbe.running) dictationProbe.running = true
  }

  Process {
    id: dictationProbe
    command: ["voxtype", "status"]
    stdout: SplitParser {
      onRead: function(line) { root.notifyDictationState(line) }
    }
  }

  // DND and stay-awake toast from the bar's file-watched state, so every
  // source dispatches — panel tiles, hotkeys, the omarchy CLI, even the
  // host's own notification center — including while the scoped api is
  // dead. (Same philosophy as the service watchers below, one level down.)
  Connections {
    target: root.barHost
    function onDndStateChanged() {
      var on = root.barHost && root.barHost.dndState === true
      root.notify("󰂛", on ? "Notifications silenced" : "Notifications on",
        on ? "Do not disturb is holding notifications" : "", root.dndNotificationId)
    }
    function onStayAwakeStateChanged() {
      var on = root.barHost && root.barHost.stayAwakeState === true
      root.notify("󰅶", on ? "Stay awake on" : "Stay awake off",
        on ? "Screen won't dim, lock, or sleep" : "Idle screensaver and lock re-enabled",
        root.stayAwakeNotificationId)
    }
  }

  // Night light keeps no state file (it lives in hyprsunset), so the live
  // service remains its only change signal.
  Connections {
    target: root.nightlightService
    function onEnabledChanged() {
      var on = root.nightlightService && root.nightlightService.enabled === true
      root.notify("󰔎", on ? "Night light on" : "Night light off", "", root.nightlightNotificationId)
    }
  }
}
