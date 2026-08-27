import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var collector: null
  property var names: ({})
  property var bar: null
  property var barIdentity: null
  property bool allowPanelSwitch: false
  property color contentForeground: Color.foreground
  property string contentFontFamily: Style.font.family

  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool confirmOpen: false
  property var pendingRow: null
  property string statusText: ""
  readonly property bool searchFocused: !!(searchField && searchField.activeFocus)
  readonly property bool listFocused: !searchFocused && cursorActive
  readonly property var selectedRow: {
    if (!listFocused) return null
    if (selectedIndex < 0 || selectedIndex >= rows.length) return null
    return rows[selectedIndex]
  }
  readonly property var hintItems: {
    if (!listFocused) {
      return [
        { keys: ["Tab"], label: "list" }
      ]
    }
    var items = [
      { keys: ["Tab"], label: "search" },
      { keys: ["↑/↓/j/k"], label: "move" }
    ]
    if (selectedRow) {
      items = items.concat([
        { keys: ["Enter"], label: "open" },
        { keys: ["y/c"], label: "copy" },
        { keys: ["x/K"], label: "kill" }
      ])
    }
    items.push({ keys: ["r"], label: "refresh" })
    return items
  }

  readonly property var fullHintItems: [
    { keys: ["Tab"], label: "search" },
    { keys: ["↑/↓/j/k"], label: "move" },
    { keys: ["Enter"], label: "open" },
    { keys: ["y/c"], label: "copy" },
    { keys: ["x/K"], label: "kill" },
    { keys: ["r"], label: "refresh" }
  ]
  readonly property int preferredHintWidth: Math.ceil(hintMeasureRow.implicitWidth)

  readonly property var rows: Model.filterListeners(collector ? collector.listeners : [], filterText)
  readonly property int portCount: collector && collector.listeners ? collector.listeners.length : 0
  readonly property int uid: collector ? collector.uid : 0
  readonly property string killSig: Model.killSignal(collector && collector.parsedSettings ? collector.parsedSettings.killSignal : "TERM")
  readonly property string countLabel: portCount === 1 ? "1 port" : portCount + " ports"

  signal closeRequested()
  signal switchPanelRequested(int direction)

  property alias searchInput: searchField
  property alias listCatcher: keyCatcher

  function prepareOpen() {
    filterText = ""
    selectedIndex = 0
    cursorActive = false
    confirmOpen = false
    pendingRow = null
    statusText = ""
    statusClear.stop()
    if (collector) collector.refresh()
    Qt.callLater(focusSearch)
    searchFocusRetry.restart()
  }

  function focusSearch() {
    cursorActive = false
    if (searchField) searchField.forceActiveFocus()
  }

  function focusList() {
    if (searchField) searchField.focus = false
    if (keyCatcher) keyCatcher.forceActiveFocus()
  }

  function enterList(index) {
    if (rows.length === 0) return
    if (index === undefined || index === null) index = 0
    if (index < 0) index = 0
    if (index >= rows.length) index = rows.length - 1
    selectedIndex = index
    cursorActive = true
    focusList()
  }

  function flashStatus(message) {
    statusText = message || ""
    if (message) statusClear.restart()
    else statusClear.stop()
  }

  function clampSelection() {
    if (rows.length === 0) {
      selectedIndex = 0
      cursorActive = false
      return
    }
    if (selectedIndex >= rows.length) selectedIndex = rows.length - 1
    if (selectedIndex < 0) selectedIndex = 0
    cursorActive = true
  }

  function setFilter(next) {
    filterText = next
    selectedIndex = 0
    cursorActive = false
  }

  function move(delta) {
    if (rows.length === 0) return
    if (searchFocused) {
      if (delta > 0) enterList(0)
      return
    }
    if (!cursorActive) {
      enterList(delta < 0 ? rows.length - 1 : 0)
      return
    }
    var next = selectedIndex + delta
    if (next < 0) {
      focusSearch()
      return
    }
    if (next >= rows.length) next = rows.length - 1
    selectedIndex = next
  }

  function togglePane() {
    if (searchFocused) {
      if (rows.length === 0) {
        cursorActive = true
        focusList()
        return
      }
      enterList(selectedIndex)
      return
    }
    focusSearch()
  }

  function currentRow() {
    if (selectedIndex < 0 || selectedIndex >= rows.length) return null
    return rows[selectedIndex]
  }

  function openRow(row) {
    if (!row) return
    var url = Model.openUrl(row, collector.parsedSettings.httpsPorts)
    if (url) Quickshell.execDetached(["xdg-open", url])
  }

  function copyRow(row) {
    if (!row) return
    var url = Model.openUrl(row, collector.parsedSettings.httpsPorts)
    if (url) Quickshell.execDetached(["wl-copy", url])
    flashStatus("Copied")
  }

  function askKill(row) {
    if (!row) return
    var dockerHost = collector && collector.parsedSettings ? collector.parsedSettings.dockerHost : ""
    if (!Model.canKillRow(row, uid, dockerHost)) {
      flashStatus(row.kind === "container"
        ? "Docker target is not a verified local socket"
        : "Can only stop processes you own")
      return
    }
    pendingRow = row
    confirmOpen = true
    confirmDialog.selectedIndex = 0
    Qt.callLater(function() { if (confirmDialog) confirmDialog.forceActiveFocus() })
  }

  function cancelPending() {
    confirmOpen = false
    pendingRow = null
    Qt.callLater(root.focusList)
  }

  function confirmPending() {
    var row = pendingRow
    confirmOpen = false
    pendingRow = null
    root.runKill(row)
  }

  // Same-invocation check: live /proc Uid + stat starttime (field 20 after last ")")
  // must match the confirmed row, and the PID must still own the selected port.
  // $1 pid, $2 uid, $3 start, $4 TERM|KILL, $5 port, $6 tcp|udp.
  readonly property string killScript: [
    "pid=$1; want_uid=$2; want_start=$3; sig=$4; port=$5; proto=$6",
    "if [ \"$pid\" -le 1 ] 2>/dev/null; then exit 1; fi",
    "case $port in ''|*[!0-9]*) exit 1 ;; esac",
    "case $proto in tcp) ss_args=-ltnp ;; udp) ss_args=-lunp ;; *) exit 1 ;; esac",
    "status=$(cat \"/proc/$pid/status\") || exit 1",
    "stat=$(cat \"/proc/$pid/stat\") || exit 1",
    "live_uid=",
    "while IFS= read -r line; do",
    "  case \"$line\" in",
    "    Uid:*) set -- $line; live_uid=$2; break ;;",
    "  esac",
    "done <<EOF",
    "$status",
    "EOF",
    "rest=${stat##*)}",
    "set -- $rest",
    "live_start=${20}",
    "[ -n \"$live_uid\" ] && [ -n \"$live_start\" ] || exit 1",
    "[ \"$live_uid\" = \"$want_uid\" ] || exit 1",
    "[ \"$live_start\" = \"$want_start\" ] || exit 1",
    "ss -H \"$ss_args\" 2>/dev/null | grep -Eq \":$port[[:space:]].*\\\",pid=$pid,\" || exit 1",
    "exec kill -s \"$sig\" \"$pid\""
  ].join("\n")

  function runKill(row) {
    if (!row) return
    if (row.kind === "container") {
      if (!Model.canStopContainer(row, collector.parsedSettings.dockerHost)) {
        flashStatus("Refusing to stop this container")
        return
      }
      stopProc.command = [
        "docker", "--host", row.dockerHost,
        "stop", row.containerId
      ]
      stopProc.running = false
      stopProc.running = true
      return
    }
    if (!Model.canSignalProcess(row, collector.uid, row.startTime)) {
      flashStatus("Refusing to signal this process")
      return
    }
    killProc.command = [
      "sh",
      "-c",
      killScript,
      "omaports-kill",
      String(row.pid),
      String(collector.uid),
      String(row.startTime),
      killSig,
      String(row.port),
      String(row.proto || "tcp")
    ]
    killProc.running = false
    killProc.running = true
  }

  Process {
    id: killProc
    running: false
    onExited: function(code) {
      flashStatus(code === 0 ? "Signaled" : "Kill failed")
      if (collector) collector.refresh()
    }
  }

  Process {
    id: stopProc
    running: false
    onExited: function(code) {
      flashStatus(code === 0 ? "Container stopped" : "docker stop failed")
      if (collector) collector.refresh()
    }
  }

  Timer {
    id: statusClear
    interval: 2000
    repeat: false
    onTriggered: root.statusText = ""
  }

  Timer {
    id: searchFocusRetry
    interval: 80
    repeat: false
    onTriggered: if (!root.cursorActive) root.focusSearch()
  }

  Row {
    id: hintMeasureRow
    x: -10000
    y: -10000
    spacing: Style.space(8)
    opacity: 0

    Repeater {
      model: root.fullHintItems

      delegate: Row {
        id: measureGroup
        required property var modelData
        spacing: Style.space(3)

        Repeater {
          model: measureGroup.modelData.keys || []

          delegate: HintKbd {
            required property var modelData
            key: String(modelData)
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }
        }

        Text {
          text: String(measureGroup.modelData.label || "")
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }
      }
    }
  }

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    blocked: root.confirmOpen || !!(searchField && searchField.activeFocus)

    onMoveRequested: function(dx, dy) {
      if (root.confirmOpen) {
        if (dx !== 0 || dy !== 0) confirmDialog.selectedIndex = confirmDialog.selectedIndex === 0 ? 1 : 0
        return
      }
      if (dy !== 0) root.move(dy)
    }
    onActivateRequested: {
      if (root.confirmOpen) {
        if (confirmDialog.selectedIndex === 0) root.cancelPending()
        else root.confirmPending()
        return
      }
      root.openRow(root.currentRow())
    }
    onCloseRequested: {
      if (root.confirmOpen) root.cancelPending()
      else root.closeRequested()
    }
    onTabRequested: function(direction) {
      if (root.confirmOpen) {
        confirmDialog.selectedIndex = confirmDialog.selectedIndex === 0 ? 1 : 0
        return
      }
      root.togglePane()
    }
    onDeleteRequested: if (!root.confirmOpen && !root.searchFocused) root.askKill(root.currentRow())
    onTextKey: function(t) {
      if (root.confirmOpen || root.searchFocused) return
      var raw = String(t || "")
      var key = raw.toLowerCase()
      if (raw === "K") root.askKill(root.currentRow())
      else if (key === "y" || key === "c") root.copyRow(root.currentRow())
      else if (key === "r") { if (collector) collector.refresh() }
    }

    ConfirmDialog {
      id: confirmDialog
      anchors.fill: parent
      opened: root.confirmOpen
      z: 10
      focus: root.confirmOpen
      message: root.pendingRow ? Model.confirmMessage(root.pendingRow, root.killSig) : ""
      confirmText: root.pendingRow && root.pendingRow.kind === "container" ? "Stop" : "Kill"
      background: Color.menu.background
      foreground: Color.menu.text
      scrim: Color.menu.scrim
      selectedBackground: Color.menu.selectedBackground
      selectedText: Color.menu.selectedText
      fontFamily: root.contentFontFamily
      cornerRadius: Style.cornerRadius
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (confirmDialog.handleKey(event)) event.accepted = true
      }
      onCanceled: root.cancelPending()
      onConfirmed: root.confirmPending()
    }

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(12)

      PanelHero {
        id: hero
        width: parent.width
        title: "Port Manager"
        meta: root.countLabel
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        iconComponent: Component {
          PortIcon {
            iconSize: Style.font.display
            fontSize: Style.font.display
            fontFamily: root.contentFontFamily
            color: root.contentForeground
          }
        }
      }

      BorderSurface {
        id: searchPane
        width: parent.width
        implicitHeight: searchField.implicitHeight + Style.space(8)
        color: "transparent"
        radius: Style.cornerRadius
        borderSpec: root.searchFocused
          ? Border.controlSpec("focus", root.contentForeground, Color.accent)
          : Border.none()

        TextField {
          id: searchField
          anchors.fill: parent
          anchors.margins: Style.space(4)
          foreground: root.contentForeground
          font.family: root.contentFontFamily
          placeholderText: "Search ports..."
          text: root.filterText
          onTextChanged: if (text !== root.filterText) root.setFilter(text)
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (root.confirmOpen) {
              if (confirmDialog.handleKey(event)) event.accepted = true
              return
            }
            if (event.key === Qt.Key_Escape) {
              if (root.filterText) root.setFilter("")
              else root.closeRequested()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              root.togglePane()
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.enterList(0)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.enterList(0)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.enterList(0)
              event.accepted = true
            } else if (event.modifiers & Qt.ControlModifier) {
              if (event.key === Qt.Key_U) { root.setFilter(""); event.accepted = true }
            }
          }
        }
      }

      PanelSeparator {
        id: rule
        foreground: root.contentForeground
      }

      Text {
        width: parent.width
        visible: !!(collector && collector.errorText)
        height: visible ? implicitHeight : 0
        text: collector ? collector.errorText : ""
        color: Color.urgent
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

      Item {
        id: listPane
        width: parent.width
        height: Math.max(Style.space(80), column.height - hero.height - searchPane.height - rule.height - hint.height - hintStatus.height - column.spacing * 5)

        BorderSurface {
          anchors.fill: parent
          color: "transparent"
          radius: Style.cornerRadius
          borderSpec: root.listFocused
            ? Border.controlSpec("focus", root.contentForeground, Color.accent)
            : Border.none()
        }

        ListView {
          id: list
          anchors.fill: parent
          anchors.margins: Style.space(6)
          spacing: Style.space(4)
          clip: true
          model: root.rows
          currentIndex: root.selectedIndex
          boundsBehavior: Flickable.StopAtBounds
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: Item {
            required property var modelData
            required property int index
            width: list.width
            height: portRow.implicitHeight

            PortRow {
              id: portRow
              width: parent.width
              row: modelData
              rowIndex: index
              selectedIndex: root.listFocused ? root.selectedIndex : -1
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              onRowHovered: root.enterList(index)
              onRowActivated: {
                root.enterList(index)
                root.openRow(modelData)
              }
            }
          }

          Text {
            visible: list.count === 0
            anchors.centerIn: parent
            text: root.filterText ? "No matching ports" : "No listening TCP ports"
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }
        }
      }

      Text {
        id: hintStatus
        width: parent.width
        visible: root.statusText !== ""
        height: visible ? implicitHeight : 0
        text: root.statusText
        color: Qt.darker(root.contentForeground, 1.5)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      Row {
        id: hint
        visible: root.statusText === ""
        height: visible ? implicitHeight : 0
        spacing: Style.space(8)

        Repeater {
          model: root.hintItems

          delegate: Row {
            id: group
            required property var modelData
            spacing: Style.space(3)

            Repeater {
              model: group.modelData.keys || []

              delegate: HintKbd {
                required property var modelData
                key: String(modelData)
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }
            }

            Text {
              visible: String(group.modelData.label || "") !== ""
              text: String(group.modelData.label || "")
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
            }
          }
        }
      }
    }
  }
}
