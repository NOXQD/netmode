import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The card under the widget. Keys: 1-4 pick a profile, a toggles auto-video,
// t runs the speed test, Esc closes.
Panel {
  id: root
  moduleName: "noxqd.netmode"
  ipcTarget: "noxqd.netmode"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property var barIdentity: hostWidget || root

  property real reveal: 1
  NumberAnimation { id: revealAnim; target: root; property: "reveal"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
  onOpenedChanged: {
    if (opened) {
      revealAnim.restart()
      if (hostWidget) hostWidget.refresh()
    }
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = String(text || "")
        var host = root.hostWidget
        if (!host) return
        var n = parseInt(key)
        if (n >= 1 && n <= host.modeList.length) host.setMode(host.modeList[n - 1].id)
        else if (key === "a") host.setAuto(!host.autoVideo)
        else if (key === "t") host.runBench()
      }

      PopupContent {
        id: content
        width: parent.width
        host: root.hostWidget
        opacity: root.reveal
      }
    }
  }
}
