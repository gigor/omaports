import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property var names: ({})

  readonly property string pluginId: (manifest && manifest.id) || "yuler.omaports"
  readonly property string namesPath: Quickshell.env("HOME") + "/.local/state/omarchy/omaports/names.json"
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/omaports"

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(760), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    mkdirProc.running = true
    view.prepareOpen()
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  PortCollector {
    id: collector
    settings: ({
      killSignal: "TERM",
      includeDocker: "Off",
      dockerSocket: "/var/run/docker.sock",
      includeUdp: "Off",
      ignoredPorts: "53,631,5353",
      httpsPorts: "443,8443",
      refreshIntervalSec: 5
    })
    names: root.names
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateDir]
    running: false
  }

  FileView {
    id: namesFile
    path: root.namesPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var parsed = Model.parseNames(text())
      root.names = parsed || {}
      collector.names = root.names
    }
    onLoadFailed: root.names = ({})
    onFileChanged: reload()
  }

  FileView {
    id: settingsFile
    path: root.stateDir + "/settings.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var parsed = Model.parseSettings(text())
      collector.settings = {
        killSignal: parsed.killSignal,
        includeDocker: parsed.includeDocker ? "On" : "Off",
        dockerSocket: parsed.dockerSocket,
        includeUdp: parsed.includeUdp ? "On" : "Off",
        ignoredPorts: parsed.ignoredPorts,
        httpsPorts: parsed.httpsPorts,
        refreshIntervalSec: parsed.refreshIntervalSec
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-omaports"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    onVisibleChanged: if (visible) Qt.callLater(view.focusSearch)

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      PortManagerView {
        id: view
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        collector: collector
        names: root.names
        allowPanelSwitch: false
        contentForeground: root.foreground
        contentFontFamily: Style.font.menuFamily
        onCloseRequested: root.dismiss()
      }
    }
  }
}
