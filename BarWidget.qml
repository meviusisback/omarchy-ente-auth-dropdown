import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget for the Ente Auth dropdown. Single lock button: click toggles the
// real Ente Auth app on special:ente-auth; the icon tracks visibility polled
// every 2s. No secrets ever reach this process: the poll prints VISIBLE=[01]
// and the toggle takes no input.
Panel {
  id: root

  moduleName: "meviusisback.ente-auth"
  ipcTarget: "meviusisback.ente-auth"
  manageIpc: false

  // Residual sizing note: root takes implicit size from the button while the
  // button fills root. Benign (implicit size stays intrinsic, same pattern as
  // the reference widget) but resizes may log binding-loop warnings.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool authedVisible: false
  property bool busy: false
  // True once the installed copy exists and is executable. The widget prefers
  // that copy (see scriptPath) so `omarchy plugin update` cannot silently
  // change the code the button runs without install.sh.
  property bool scriptInstalled: false

  function scriptPath() {
    const home = Quickshell.env("HOME") || ""
    // Prefer the installed copy ~/.local/bin/ente-auth-dropdown when it
    // exists; fall back to the sibling copy inside the plugin dir. The
    // plugin dir is replaced on every `omarchy plugin update`, but
    // install.sh is what makes the toggle live (keybind, watcher), so the
    // button must run the same code the rest of the install uses.
    if (home !== "" && root.scriptInstalled) return home + "/.local/bin/ente-auth-dropdown"
    // Fallback: ente-auth-dropdown ships next to this file inside the plugin
    // folder. plugin dir comes from `omarchy plugin add` (fixed path, no
    // spaces), so plain file:// stripping is enough; no percent-decoding layer.
    return Qt.resolvedUrl("ente-auth-dropdown").toString().replace(/^file:\/\//, "")
  }

  // Every automatic process starts with a CLEARED environment plus an explicit
  // allowlist: hyprctl needs the compositor address, nothing else. Residual:
  // allowlisted values are visible in /proc cmdline to local users; the socket
  // dir itself (0700) remains the real boundary, and no secrets pass here.
  readonly property var cliEnvPassthrough: [
    "XDG_RUNTIME_DIR", "HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS"
  ]

  function cliArgv(args) {
    const argv = ["/usr/bin/env", "-i", "HOME=" + (Quickshell.env("HOME") || "")]
    for (const name of root.cliEnvPassthrough) {
      const value = Quickshell.env(name) || ""
      if (value !== "") argv.push(name + "=" + value)
    }
    return argv.concat([root.scriptPath()], args)
  }

  // Single-flight poll: skip the tick while the previous poll is alive or a
  // toggle is running. The status verb answers in well under the 2s interval;
  // a 10s watchdog below still kills a stuck poll so the icon never wedges.
  function refresh() {
    if (statusProc.running || busy) return
    statusProc.running = true
  }

  function runToggle() {
    if (busy) return
    busy = true
    pollTimer.running = false
    actionProc.command = root.cliArgv(["toggle"])
    actionProc.running = true
  }

  Process {
    id: statusProc
    command: root.cliArgv(["status"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Strict shape only: anything else fails closed to inactive, and the
        // raw output is never logged or rendered anywhere.
        const line = (text || "").trim()
        root.authedVisible = (line === "VISIBLE=1")
      }
    }
    stderr: StdioCollector {
    }
    // Recovery if the poll itself fails to spawn or exit: never wedge the icon.
    // Success keeps the parsed value; only a real failure clears to inactive
    // and re-probes the installed copy (it may have appeared via install.sh).
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.authedVisible = false
        if (!installProbe.running) installProbe.running = true
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.busy = false
        pollTimer.running = true
        root.refresh()
      }
    }
    stderr: StdioCollector {
    }
    // stdout always closes at process end, but a failed spawn might not: the
    // exit signal is the authoritative busy-clear.
    onExited: {
      root.busy = false
      pollTimer.running = true
      root.refresh()
    }
  }

  // Probe for the installed copy (no shell, absolute path only). Decides
  // whether the button runs ~/.local/bin or the sibling fallback, and
  // whether the tooltip may advertise SUPER + E. Re-probed on a slow timer
  // and after a failed poll: right after ./install.sh the copy appears while
  // the shell is still running, and the tooltip must stop advertising setup.
  Process {
    id: installProbe
    command: ["/usr/bin/test", "-x", (Quickshell.env("HOME") || "") + "/.local/bin/ente-auth-dropdown"]
    onExited: function(exitCode) {
      root.scriptInstalled = (exitCode === 0)
    }
  }

  Timer {
    id: installReprobeTimer
    interval: 30000
    repeat: true
    // Only while the installed copy is missing: the removal direction is
    // already covered by the failed-poll re-probe, so a permanent 30s fork
    // after ./install.sh would be pure cost.
    running: !root.scriptInstalled
    onTriggered: {
      if (!installProbe.running) installProbe.running = true
    }
  }

  // Watchdogs (both directions): worst legitimate toggle is ~33s under a
  // responsive compositor (15s launch wait + bounded snapshot reads + show
  // retries); worst legitimate status poll is ~2s. Past the bound the
  // action is treated as stuck: terminate it and recover instead of leaving
  // the button disabled (toggle) or the icon frozen (status) for the session.
  Timer {
    id: statusWatchdog
    interval: 10000
    repeat: false
    running: statusProc.running
    onTriggered: {
      statusProc.running = false
      root.authedVisible = false
    }
  }

  Timer {
    id: toggleWatchdog
    interval: 45000
    repeat: false
    running: root.busy
    onTriggered: {
      actionProc.running = false
      root.busy = false
      pollTimer.running = true
      root.refresh()
    }
  }

  Timer {
    id: pollTimer
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "meviusisback.ente-auth"
    function toggle(): void { root.runToggle() }
    function status(): void { root.refresh() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    enabled: !root.busy
    text: "\uf023"
    // The keybind exists only after ./install.sh step 4; before that (or when
    // the probe found no installed copy) say so instead of advertising it.
    tooltipText: !root.scriptInstalled
      ? "Ente Auth: install not completed (run ./install.sh for SUPER + E)"
      : root.authedVisible
      ? "Ente Auth: shown (SUPER + E to hide)"
      : "Ente Auth: hidden (SUPER + E to show)"
    active: root.authedVisible
    useActiveColor: true
    activeColor: root.accent

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.runToggle()
    }
  }

  Component.onCompleted: {
    installProbe.running = true
    root.refresh()
  }
  Component.onDestruction: {
    statusProc.running = false
    actionProc.running = false
  }
}
