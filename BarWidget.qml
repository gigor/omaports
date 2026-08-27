import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "yuler.omaports"

  readonly property string namesPath: Quickshell.env("HOME") + "/.local/state/omarchy/omaports/names.json"
  property var names: ({})

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("collector" in target) target.collector = collector
    if ("namesPath" in target) target.namesPath = root.namesPath
    if ("names" in target) target.names = root.names
  }

  function saveNames(next) {
    root.names = next || {}
    namesFile.setText(JSON.stringify(root.names, null, 2) + "\n")
    injectPanel()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    settingsFile.setText(JSON.stringify({
      killSignal: root.setting("killSignal", "TERM"),
      includeDocker: root.setting("includeDocker", "Off") === "On",
      dockerSocket: root.setting("dockerSocket", "/var/run/docker.sock"),
      includeUdp: root.setting("includeUdp", "Off") === "On",
      ignoredPorts: root.setting("ignoredPorts", "53,631,5353"),
      httpsPorts: root.setting("httpsPorts", "443,8443"),
      refreshIntervalSec: root.setting("refreshIntervalSec", 5)
    }, null, 2) + "\n")
  }

  PortCollector {
    id: collector
    settings: root.settings
    names: root.names
  }

  Timer {
    interval: Math.max(2, parseInt(root.setting("refreshIntervalSec", 5), 10) || 5) * 1000
    running: true
    repeat: true
    onTriggered: collector.refresh()
  }

  Component.onCompleted: {
    mkdirProc.running = true
    collector.refresh()
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/omarchy/omaports"]
    running: false
  }

  FileView {
    id: settingsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/omaports/settings.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
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
      collector.rebuild()
      root.injectPanel()
    }
    onLoadFailed: root.names = ({})
    onFileChanged: reload()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "yuler.omaports"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { collector.refresh() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    active: false
    iconComponent: Component {
      PortIcon {
        iconSize: Style.bar.iconCanvas
        fontSize: Style.bar.iconFont + 2
        fontFamily: button.fontFamily
        color: button.foreground
      }
    }
    tooltipText: collector.errorText || "Port Manager"
    onPressed: function(b) {
      if (b === Qt.RightButton) collector.refresh()
      else root.togglePanel()
    }
  }
}
