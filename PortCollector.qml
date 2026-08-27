import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property var names: ({})
  property var listeners: []
  property int uid: 0
  property string errorText: ""
  property bool loading: false
  property var pendingMeta: ({})
  property var rawProcess: []
  property var rawDocker: []
  property bool dockerPending: false
  property bool enrichPending: false

  readonly property var parsedSettings: {
    var docker = settings && settings.includeDocker
    var udp = settings && settings.includeUdp
    return {
      killSignal: Model.killSignal(settings && settings.killSignal),
      includeUdp: udp === true || udp === "On",
      includeDocker: docker === true || docker === "On",
      dockerHost: Model.dockerHost(settings && settings.dockerSocket),
      ignoredPorts: String((settings && settings.ignoredPorts) || "53,631,5353"),
      httpsPorts: String((settings && settings.httpsPorts) || "443,8443"),
      refreshIntervalSec: Math.max(2, Math.min(120, parseInt(settings && settings.refreshIntervalSec, 10) || 5))
    }
  }

  readonly property int count: Model.devPortCount(listeners, uid)
  readonly property bool exposed: {
    for (var i = 0; i < listeners.length; i++) if (listeners[i].exposed) return true
    return false
  }

  function refresh() {
    if (root.loading) return
    root.loading = true
    root.errorText = ""
    root.rawProcess = []
    root.rawDocker = []
    root.pendingMeta = ({})
    root.dockerPending = false
    root.enrichPending = false
    ssProc.running = false
    ssProc.command = root.cappedCommand(root.parsedSettings.includeUdp
      ? ["ss", "-ltunpH"]
      : ["ss", "-ltnpH"])
    ssProc.running = true
  }

  function cappedCommand(argv) {
    var command = [
      "sh", "-c",
      "limit=$1; shift; \"$@\" | head -c \"$limit\"",
      "omaports-cap",
      String(Model.maxOutputBytes())
    ]
    for (var i = 0; i < argv.length; i++) command.push(String(argv[i]))
    return command
  }

  function rebuild() {
    var ignored = Model.parsePortSet(root.parsedSettings.ignoredPorts)
    var rows = Model.dropIgnored(Model.mergeListeners(root.rawProcess, root.rawDocker), ignored)
    rows = Model.applyNames(rows, root.names)
    for (var i = 0; i < rows.length; i++) {
      rows[i] = Model.enrichProcess(rows[i], root.pendingMeta[String(rows[i].pid)] || {})
    }
    root.listeners = rows
    root.loading = root.enrichPending || root.dockerPending
  }

  function startEnrich(rows) {
    var pids = []
    var seen = {}
    for (var i = 0; i < rows.length; i++) {
      var pid = rows[i].pid
      if (pid > 1 && !seen[pid]) {
        seen[pid] = true
        pids.push(pid)
      }
    }
    root.pendingMeta = ({})
    if (!pids.length) {
      root.enrichPending = false
      rebuild()
      return
    }
    root.enrichPending = true
    var command = [
      "sh", "-c", root.metaScript, "omaports-meta",
      String(Model.maxMetaFieldBytes())
    ]
    for (var p = 0; p < pids.length; p++) command.push(String(pids[p]))
    metaProc.running = false
    metaProc.command = command
    metaProc.running = true
  }

  // Print one tab-separated, size-limited record per PID. Tabs, newlines,
  // carriage returns, and NUL bytes are replaced before QML parses the data.
  readonly property string metaScript: [
    "limit=$1; shift",
    "clean() { head -c \"$limit\" | tr '\\000\\011\\012\\015' '    '; }",
    "for pid do",
    "  case $pid in ''|*[!0-9]*) continue ;; esac",
    "  [ \"$pid\" -gt 1 ] || continue",
    "  uid=",
    "  while IFS= read -r line; do",
    "    case $line in Uid:*) set -- $line; uid=$2; break ;; esac",
    "  done < \"/proc/$pid/status\"",
    "  stat=$(cat \"/proc/$pid/stat\" 2>/dev/null) || continue",
    "  rest=${stat##*)}",
    "  set -- $rest",
    "  start=${20}",
    "  [ -n \"$uid\" ] && [ -n \"$start\" ] || continue",
    "  cmd=$(clean < \"/proc/$pid/cmdline\" 2>/dev/null)",
    "  cwd=$(readlink \"/proc/$pid/cwd\" 2>/dev/null | clean)",
    "  exe=$(readlink \"/proc/$pid/exe\" 2>/dev/null | clean)",
    "  printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \"$pid\" \"$uid\" \"$start\" \"$cmd\" \"$cwd\" \"$exe\"",
    "done"
  ].join("\n")

  Process {
    id: uidProc
    command: ["id", "-u"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.uid = parseInt(String(text || "").trim(), 10) || 0
    }
  }

  Process {
    id: ssProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.rawProcess = Model.parseSs(text)
        if (root.parsedSettings.includeDocker && root.parsedSettings.dockerHost) {
          root.dockerPending = true
          dockerProc.running = false
          dockerProc.command = root.cappedCommand([
            "docker", "--host", root.parsedSettings.dockerHost,
            "ps", "--format", "{{.ID}}\\t{{.Names}}\\t{{.Ports}}"
          ])
          dockerProc.running = true
        } else {
          root.rawDocker = []
          root.dockerPending = false
        }
        root.startEnrich(root.rawProcess)
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code !== 0 && code !== 141) {
        root.errorText = "Could not read listening sockets"
        root.rawProcess = []
        root.dockerPending = false
        root.enrichPending = false
        root.loading = false
      }
    }
  }

  Process {
    id: dockerProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.rawDocker = Model.parseDockerPs(text, root.parsedSettings.dockerHost)
        root.dockerPending = false
        root.rebuild()
      }
    }
    onExited: function(code) {
      if (code !== 0 && code !== 141) {
        root.rawDocker = []
        root.dockerPending = false
        root.rebuild()
      }
    }
  }

  Process {
    id: metaProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.pendingMeta = Model.parseProcMeta(text)
    }
    onExited: {
      root.enrichPending = false
      root.rebuild()
    }
  }
}
