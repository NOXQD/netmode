import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Fmt.js" as Fmt

// Card body: hero with the active profile, one row per profile, the live
// state of the line, the speed test and the auto-video switch.
ColumnLayout {
  id: root

  property var host: null

  readonly property color fg: Commons.Color.foreground
  readonly property color muted: Qt.darker(Commons.Color.foreground, 1.4)
  readonly property var modeList: host ? host.modeList : []
  readonly property string mode: host ? host.mode : "balanced"
  readonly property var current: host ? host.current : null
  readonly property var rows: host ? Fmt.stats(host.snap, host.current && host.current.keepalive === true) : []
  readonly property var benchRows: host ? Fmt.benchRows(host.benchResult) : []
  readonly property string pingText: host && host.pulse && host.pulse.rtt !== undefined && host.pulse.rtt !== null
    ? Fmt.ms(host.pulse.rtt) : ""

  spacing: Style.space(10)

  PanelHero {
    Layout.fillWidth: true
    title: "Сеть"
    meta: root.current ? root.current.name : ""
    detail: root.pingText
    iconComponent: Component {
      Text {
        text: root.current ? root.current.icon : ""
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.display
      }
    }
  }

  PanelSeparator { Layout.fillWidth: true }

  PanelSectionHeader { text: "РЕЖИМ" }

  Repeater {
    model: root.modeList
    delegate: CursorSurface {
      id: row
      required property var modelData
      required property int index
      Layout.fillWidth: true
      implicitHeight: Style.space(46)
      current: modelData.id === root.mode
      hasCursor: rowMouse.containsMouse
      opacity: root.host && root.host.switchingTo !== "" && root.host.switchingTo !== modelData.id ? 0.55 : 1

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(12)

        Text {
          Layout.preferredWidth: Style.space(26)
          horizontalAlignment: Text.AlignHCenter
          text: row.modelData.icon
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(1)
          Text {
            textFormat: Text.PlainText
            text: row.modelData.name
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: row.modelData.blurb
            color: root.muted
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          text: row.current ? "●" : String(row.index + 1)
          color: root.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.features: ({ "tnum": 1 })
        }
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.host) root.host.setMode(row.modelData.id)
      }
    }
  }

  PanelSeparator { Layout.fillWidth: true }

  PanelSectionHeader { text: "КАНАЛ" }

  Repeater {
    model: root.rows
    delegate: RowLayout {
      required property var modelData
      Layout.fillWidth: true
      spacing: Style.space(10)
      Text {
        Layout.preferredWidth: Style.space(92)
        text: parent.modelData.k
        color: root.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: parent.modelData.v
        color: root.fg
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.features: ({ "tnum": 1 })
      }
    }
  }

  Text {
    visible: root.rows.length === 0
    text: "измеряю…"
    color: root.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: root.benchRows
    delegate: RowLayout {
      required property var modelData
      Layout.fillWidth: true
      spacing: Style.space(10)
      Text {
        Layout.preferredWidth: Style.space(92)
        text: parent.modelData.k
        color: root.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: parent.modelData.v
        color: root.fg
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.features: ({ "tnum": 1 })
      }
    }
  }

  PanelSeparator { Layout.fillWidth: true }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(10)
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(1)
      Text {
        text: "Авто-видео"
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        text: "режим «Видео» сам, пока открыт AnimeLib"
        color: root.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
    ToggleSwitch {
      checked: root.host ? root.host.autoVideo : false
      onToggled: if (root.host) root.host.setAuto(!root.host.autoVideo)
    }
  }

  Button {
    Layout.fillWidth: true
    bordered: true
    text: root.host && root.host.benching ? "Измеряю…  (около 25 с)" : "Тест скорости  (t)"
    enabled: !(root.host && root.host.benching)
    onClicked: if (root.host) root.host.runBench()
  }
}
