import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Env.js" as Env
import "Fmt.js" as Fmt

// NetMode on the Omarchy bar: the glyph of the active profile and the current
// ping. The mode itself is read from /run/netmode/state.json (written by the
// root helper), so the bar can never disagree with what is really applied.
// Left click opens the card, middle click cycles the profiles.
BarWidget {
  id: root
  moduleName: "noxqd.netmode"

  property string mode: "balanced"
  property var modeList: []
  property var pulse: null
  property var snap: null
  property var benchResult: null
  property bool benching: false
  property string switchingTo: ""
  property bool autoVideo: true
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  readonly property var current: {
    for (var i = 0; i < modeList.length; i++)
      if (modeList[i].id === mode) return modeList[i]
    return null
  }
  readonly property string glyph: current ? current.icon : "󰖩"
  readonly property string label: pulse && pulse.rtt !== undefined && pulse.rtt !== null ? Math.round(pulse.rtt) + "" : ""

  FileView {
    path: Env.stateFile
    watchChanges: true
    printErrors: false
    onLoaded: {
      var s = Fmt.parse(text())
      if (s && s.mode) root.mode = s.mode
    }
    onFileChanged: reload()
  }

  Process {
    id: modesProc
    command: [Env.exe, "modes", "--json"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: { var m = Fmt.parse(text); if (m) root.modeList = m }
    }
  }

  // Performance modes keep the radio awake with a 100 Hz trickle of packets:
  // an idle link here has 100-200 ms latency spikes, a busy one has none.
  Process {
    id: keepaliveProc
    command: [Env.exe, "keepalive"]
    running: root.current ? root.current.keepalive === true : false
  }

  Process {
    id: pulseProc
    command: [Env.exe, "pulse"]
    stdout: StdioCollector {
      onStreamFinished: { var p = Fmt.parse(text); if (p) root.pulse = p }
    }
  }

  Process {
    id: statusProc
    command: [Env.exe, "status", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        var s = Fmt.parse(text)
        if (!s) return
        root.snap = s
        root.autoVideo = s.auto === true
        if (s.bench && !root.benchResult) root.benchResult = s.bench
        if (s.modes && s.modes.length) root.modeList = s.modes
      }
    }
  }

  Process {
    id: setProc
    onExited: { root.switchingTo = ""; pulseProc.running = true }
  }

  Process {
    id: autoProc
    onExited: statusProc.running = true
  }

  Process {
    id: benchProc
    command: [Env.exe, "bench", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.benching = false
        var b = Fmt.parse(text)
        if (b) root.benchResult = b
        pulseProc.running = true
      }
    }
  }

  // Poll the ping only while the bar is on screen; a pulse costs ~0.7 s of three pings.
  Timer {
    interval: 12000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!pulseProc.running && !root.benching) pulseProc.running = true
  }

  function setMode(id) {
    if (!id || id === root.mode || setProc.running) return
    root.switchingTo = id
    setProc.command = [Env.exe, "set", id]
    setProc.running = true
  }

  function cycle() {
    if (modeList.length === 0) return
    var idx = 0
    for (var i = 0; i < modeList.length; i++) if (modeList[i].id === mode) idx = i
    setMode(modeList[(idx + 1) % modeList.length].id)
  }

  function setAuto(on) {
    root.autoVideo = on
    autoProc.command = [Env.exe, "auto", on ? "on" : "off"]
    autoProc.running = true
  }

  function runBench() {
    if (root.benching) return
    root.benching = true
    benchProc.running = true
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() { if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle() }
  function close() { if (panelLoader.item && panelLoader.item.close) panelLoader.item.close() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Popup.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  IpcHandler {
    target: "netmode"
    function toggle(): void { root.togglePanel() }
    function close(): void { root.close() }
    function cycle(): void { root.cycle() }
    function set(id: string): void { root.setMode(id) }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    active: root.mode !== "balanced"
    fixedWidth: root.vertical ? -1 : content.implicitWidth + button.scaledHorizontalMargin * 2
    tooltipText: root.opened || !root.current ? "" : "Сеть: " + root.current.name + (root.label !== "" ? "  ·  " + root.label + " мс" : "")

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.cycle()
      else root.togglePanel()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph
        color: button.foreground
        opacity: root.switchingTo !== "" ? 0.5 : 1
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.vertical && root.label !== ""
        textFormat: Text.PlainText
        text: root.label
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.features: ({ "tnum": 1 })
        renderType: Text.NativeRendering
      }
    }
  }
}
