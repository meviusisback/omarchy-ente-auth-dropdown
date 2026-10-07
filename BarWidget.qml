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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool authedVisible: false
  property bool busy: false

  function scriptPath() {
    // ente-auth-dropdown ships next to this file inside the plugin folder.
    return Qt.resolvedUrl("ente-auth-dropdown").toString().replace(/^file:\/\//, "")
  }

  // Every automatic process starts with a CLEARED environment plus an explicit
  // allowlist: hyprctl needs the compositor address, nothing else.
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
  // toggle is running. The status verb answers in well under the 2s interval.
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
    tooltipText: root.authedVisible
      ? "Ente Auth: shown (SUPER + E to hide)"
      : "Ente Auth: hidden (SUPER + E to show)"
    active: root.authedVisible
    useActiveColor: true
    activeColor: root.accent

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.runToggle()
    }
  }

  Component.onCompleted: root.refresh()
  Component.onDestruction: {
    statusProc.running = false
    actionProc.running = false
  }
}
