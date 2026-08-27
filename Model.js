// Pure listener math for Omaports. Qt-free so node can unit-test it.

var MAX_ROWS = 256
var MAX_OUTPUT_BYTES = 262144
var MAX_META_FIELD_BYTES = 4096

function maxOutputBytes() {
  return MAX_OUTPUT_BYTES
}

function maxMetaFieldBytes() {
  return MAX_META_FIELD_BYTES
}

var COMMANDS = [
  {
    id: "open-ports",
    name: "Open Ports",
    description: "Find processes that are listening on TCP ports"
  },
  {
    id: "kill-port",
    name: "Kill Process Listening on",
    description: "Terminate every process listening on a port"
  },
  {
    id: "named-ports",
    name: "Named Ports",
    description: "Assign memorable labels to ports"
  }
]

function trim(value) {
  return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
}

function parsePort(value) {
  var n = parseInt(String(value), 10)
  if (!isFinite(n) || n < 1 || n > 65535) return 0
  return n
}

function parsePortQuery(text) {
  return parsePort(trim(text))
}

function parseNamedInput(text) {
  var raw = trim(text)
  var match = raw.match(/^(\d{1,5})\s*[=:]\s*(.+)$/)
  if (!match) match = raw.match(/^(\d{1,5})\s+(.+)$/)
  if (!match) return null
  var port = parsePort(match[1])
  var label = trim(match[2])
  if (!port || !label) return null
  return { port: port, label: label }
}

function splitHostPort(addr) {
  var text = String(addr || "")
  if (!text || text === "*") return { host: "0.0.0.0", port: 0 }
  if (text.charAt(0) === "[") {
    var close = text.lastIndexOf("]:")
    if (close < 0) return { host: text, port: 0 }
    return { host: text.slice(1, close), port: parsePort(text.slice(close + 2)) }
  }
  var colon = text.lastIndexOf(":")
  if (colon < 0) return { host: text, port: 0 }
  var host = text.slice(0, colon)
  if (host === "*" || host === "") host = "0.0.0.0"
  return { host: host, port: parsePort(text.slice(colon + 1)) }
}

function isLoopback(host) {
  var h = String(host || "")
  return h === "127.0.0.1" || h === "::1" || h === "localhost"
}

function isWildcard(host) {
  var h = String(host || "")
  return h === "0.0.0.0" || h === "::" || h === "*"
}

function parseUsers(field) {
  var text = String(field || "")
  var match = text.match(/users:\(\("((?:\\.|[^"\\])*)",pid=(\d+)/)
  if (!match) return { comm: "", pid: 0 }
  return { comm: match[1], pid: parseInt(match[2], 10) || 0 }
}

function parseSs(raw) {
  var lines = String(raw || "").split(/\n/)
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = trim(lines[i])
    if (!line) continue
    var usersAt = line.indexOf("users:(")
    var head = usersAt >= 0 ? trim(line.slice(0, usersAt)) : line
    var users = usersAt >= 0 ? line.slice(usersAt) : ""
    var parts = head.split(/\s+/)
    if (parts.length < 4) continue
    var netid = String(parts[0] || "").toLowerCase()
    var hasNetid = netid === "tcp" || netid === "udp"
    var proto = hasNetid ? netid : "tcp"
    var local = splitHostPort(parts[hasNetid ? 4 : 3])
    if (!local.port) continue
    var proc = parseUsers(users)
    out.push({
      kind: "process",
      proto: proto,
      host: local.host,
      port: local.port,
      pid: proc.pid,
      comm: proc.comm,
      command: proc.comm,
      cwd: "",
      exe: "",
      uid: -1,
      startTime: 0,
      exposed: !isLoopback(local.host),
      containerId: "",
      containerName: "",
      label: ""
    })
    if (out.length >= MAX_ROWS) break
  }
  return out
}

function parsePortSet(text) {
  var set = {}
  var chunks = trim(text).split(",")
  for (var i = 0; i < chunks.length; i++) {
    var chunk = trim(chunks[i])
    if (!chunk) continue
    var range = chunk.split("-")
    if (range.length === 2) {
      var from = parsePort(range[0])
      var to = parsePort(range[1])
      if (!from || !to || to < from) continue
      for (var p = from; p <= to; p++) set[String(p)] = true
    } else {
      var port = parsePort(chunk)
      if (port) set[String(port)] = true
    }
  }
  return set
}

function portSetHas(set, port) {
  return !!(set && set[String(port)])
}

function dropIgnored(listeners, ignored) {
  var out = []
  for (var i = 0; i < (listeners || []).length; i++) {
    if (!portSetHas(ignored, listeners[i].port)) out.push(listeners[i])
  }
  return out
}

function haystack(row) {
  return [
    row.port,
    row.host,
    row.pid,
    row.comm,
    row.command,
    row.cwd,
    row.label,
    row.containerName,
    row.containerId
  ].join(" ").toLowerCase()
}

function filterListeners(listeners, query) {
  var q = trim(query).toLowerCase()
  if (!q) return (listeners || []).slice()
  var out = []
  for (var i = 0; i < (listeners || []).length; i++) {
    if (haystack(listeners[i]).indexOf(q) !== -1) out.push(listeners[i])
  }
  return out
}

function listenersOnPort(listeners, port) {
  var n = parsePort(port)
  var out = []
  if (!n) return out
  for (var i = 0; i < (listeners || []).length; i++) {
    if (listeners[i].port === n) out.push(listeners[i])
  }
  return out
}

function parseNames(raw) {
  if (raw === undefined || raw === null || trim(raw) === "") return {}
  var parsed
  try {
    parsed = JSON.parse(String(raw))
  } catch (e) {
    return null
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
  var out = {}
  for (var key in parsed) {
    if (!Object.prototype.hasOwnProperty.call(parsed, key)) continue
    var port = parsePort(key)
    var label = trim(parsed[key])
    if (port && label) out[String(port)] = label
  }
  return out
}

function applyNames(listeners, names) {
  var map = names || {}
  var out = []
  for (var i = 0; i < (listeners || []).length; i++) {
    var row = {}
    for (var key in listeners[i]) row[key] = listeners[i][key]
    var label = map[String(row.port)]
    row.label = label ? String(label) : ""
    out.push(row)
  }
  return out
}

function upsertName(names, port, label) {
  var next = {}
  for (var key in (names || {})) next[key] = names[key]
  var n = parsePort(port)
  var text = trim(label)
  if (!n || !text) return next
  next[String(n)] = text
  return next
}

function removeName(names, port) {
  var next = {}
  var skip = String(parsePort(port))
  for (var key in (names || {})) {
    if (key !== skip) next[key] = names[key]
  }
  return next
}

function namedPortRows(names) {
  var out = []
  var map = names || {}
  var keys = []
  for (var key in map) keys.push(key)
  keys.sort(function (a, b) { return parsePort(a) - parsePort(b) })
  for (var i = 0; i < keys.length; i++) {
    out.push({ port: parsePort(keys[i]), label: map[keys[i]] })
  }
  return out
}

function canSignalProcess(proc, currentUid, expectedStartTime) {
  if (!proc) return false
  var pid = Number(proc.pid)
  if (!isFinite(pid) || pid <= 1) return false
  if (Number(proc.uid) !== Number(currentUid)) return false
  if (Number(proc.startTime) <= 0) return false
  if (Number(proc.startTime) !== Number(expectedStartTime)) return false
  return true
}

function liveIdentityMatches(row, liveUid, liveStartTime, currentUid) {
  return canSignalProcess(
    { pid: row && row.pid, uid: liveUid, startTime: liveStartTime },
    currentUid,
    row && row.startTime
  )
}

function killSignal(value) {
  return String(value || "").toUpperCase() === "KILL" ? "KILL" : "TERM"
}

function dockerHost(value) {
  var path = trim(value || "/var/run/docker.sock")
  if (path.indexOf("unix://") === 0) path = path.slice(7)
  if (!path || path.charAt(0) !== "/") return ""
  if (/[\u0000\r\n]/.test(path)) return ""
  var parts = path.split("/")
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === "..") return ""
  }
  return "unix://" + path
}

function validContainerId(value) {
  return /^[0-9a-f]{12,64}$/i.test(trim(value))
}

function canStopContainer(row, expectedDockerHost) {
  if (!row || row.kind !== "container") return false
  var expected = dockerHost(expectedDockerHost)
  var actual = row.dockerHost ? dockerHost(row.dockerHost) : ""
  return !!expected && actual === expected && validContainerId(row.containerId)
}

function browseHost(host) {
  if (isWildcard(host) || !host) return "127.0.0.1"
  if (host.indexOf(":") >= 0 && host.charAt(0) !== "[") return host
  return host
}

function openUrl(listener, httpsPorts) {
  var port = listener && listener.port
  if (!port) return ""
  var https = parsePortSet(httpsPorts)
  var scheme = portSetHas(https, port) ? "https" : "http"
  var host = browseHost(listener.host)
  if (host.indexOf(":") >= 0) host = "[" + host + "]"
  if (isWildcard(listener.host)) host = host.indexOf(":") >= 0 ? "[::1]" : "127.0.0.1"
  if (listener.host === "::" || listener.host === "[::]") host = "[::1]"
  return scheme + "://" + host + ":" + port
}

function parseDockerPorts(field) {
  var text = trim(field)
  if (!text || text === "-") return []
  var chunks = text.split(",")
  var out = []
  for (var i = 0; i < chunks.length; i++) {
    var chunk = trim(chunks[i])
    var match = chunk.match(/([0-9A-Fa-f.:\[\]]+):(\d+)->[^/]+\/(tcp|udp)/i)
    if (!match) continue
    var host = match[1]
    if (host.charAt(0) === "[") host = host.slice(1, host.length - 1)
    out.push({ host: host, port: parsePort(match[2]), proto: match[3].toLowerCase(), exposed: !isLoopback(host) })
  }
  return out
}

function parseDockerPs(raw, expectedDockerHost) {
  var localDockerHost = dockerHost(expectedDockerHost)
  if (!localDockerHost) return []
  var lines = String(raw || "").split(/\n/)
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = trim(lines[i])
    if (!line) continue
    var parts = line.split("\t")
    if (parts.length < 3) continue
    var id = trim(parts[0])
    if (!validContainerId(id)) continue
    var name = trim(parts[1])
    var published = parseDockerPorts(parts.slice(2).join("\t"))
    for (var p = 0; p < published.length; p++) {
      out.push({
        kind: "container",
        proto: published[p].proto,
        host: published[p].host,
        port: published[p].port,
        pid: 0,
        comm: name,
        command: name,
        cwd: "",
        exe: "",
        uid: -1,
        startTime: 0,
        exposed: published[p].exposed,
        containerId: id,
        containerName: name,
        dockerHost: localDockerHost,
        label: ""
      })
      if (out.length >= MAX_ROWS) return out
    }
  }
  return out
}

function listenerKey(row) {
  return String(row.proto || "tcp") + "|" + String(row.host) + "|" + String(row.port)
}

function socketIdentity(row) {
  if (!row) return ""
  if (row.kind === "container" && row.containerId)
    return "c:" + row.containerId + ":" + (row.proto || "tcp") + ":" + row.port
  if (row.comm === "docker-proxy")
    return "n:docker-proxy:" + (row.proto || "tcp") + ":" + row.port
  if (Number(row.pid) > 0)
    return "p:" + row.pid + ":" + (row.proto || "tcp") + ":" + row.port
  if (row.comm)
    return "n:" + row.comm + ":" + (row.proto || "tcp") + ":" + row.port
  return "h:" + row.host + ":" + (row.proto || "tcp") + ":" + row.port
}

function hostRank(host) {
  var h = String(host || "")
  if (h === "0.0.0.0") return 0
  if (h === "*" || h === "::") return 1
  if (!isLoopback(h) && h) return 2
  if (h === "127.0.0.1") return 3
  return 4
}

function pickSocket(a, b) {
  var out = {}
  var primary = hostRank(a.host) <= hostRank(b.host) ? a : b
  var other = primary === a ? b : a
  for (var key in primary) out[key] = primary[key]
  if (other.kind === "container" && primary.kind !== "container") {
    out = {}
    for (var k in other) out[k] = other[k]
    out.host = primary.host
  }
  out.exposed = !!(a.exposed || b.exposed)
  if (!out.label && other.label) out.label = other.label
  if (!out.command && other.command) out.command = other.command
  if (!out.cwd && other.cwd) out.cwd = other.cwd
  if (!out.exe && other.exe) out.exe = other.exe
  return out
}

function dedupeSockets(rows) {
  var seen = {}
  var order = []
  for (var i = 0; i < (rows || []).length; i++) {
    var row = rows[i]
    var id = socketIdentity(row)
    if (!seen[id]) {
      seen[id] = row
      order.push(id)
    } else {
      seen[id] = pickSocket(seen[id], row)
    }
  }
  var out = []
  for (var j = 0; j < order.length; j++) out.push(seen[order[j]])
  return out
}

function mergeListeners(processRows, dockerRows) {
  var out = []
  var dockerByPortHost = {}
  for (var d = 0; d < (dockerRows || []).length; d++) {
    dockerByPortHost[listenerKey(dockerRows[d])] = dockerRows[d]
  }
  var used = {}
  for (var i = 0; i < (processRows || []).length; i++) {
    var row = processRows[i]
    var hit = dockerByPortHost[listenerKey(row)]
    if (!hit && row.comm === "docker-proxy") {
      for (var key in dockerByPortHost) {
        if (dockerByPortHost[key].port === row.port && (dockerByPortHost[key].proto || "tcp") === (row.proto || "tcp")) {
          hit = dockerByPortHost[key]
          break
        }
      }
    }
    if (hit) {
      var merged = {}
      for (var k in hit) merged[k] = hit[k]
      merged.host = row.host || merged.host
      merged.exposed = row.exposed || merged.exposed
      out.push(merged)
      used[listenerKey(hit)] = true
      used[listenerKey(row)] = true
    } else {
      out.push(row)
    }
  }
  for (var j = 0; j < (dockerRows || []).length; j++) {
    var extra = dockerRows[j]
    var extraKey = listenerKey(extra)
    var taken = false
    for (var u in used) {
      if (u === extraKey) taken = true
    }
    if (!taken) {
      var already = false
      for (var o = 0; o < out.length; o++) {
        if (out[o].kind === "container" && out[o].containerId === extra.containerId && out[o].port === extra.port && (out[o].proto || "tcp") === (extra.proto || "tcp"))
          already = true
      }
      if (!already) out.push(extra)
    }
  }
  out.sort(function (a, b) { return a.port - b.port || String(a.host).localeCompare(String(b.host)) })
  return dedupeSockets(out)
}

function filterCommands(query) {
  var q = trim(query).toLowerCase()
  var out = []
  for (var i = 0; i < COMMANDS.length; i++) {
    var cmd = COMMANDS[i]
    var blob = (cmd.id + " " + cmd.name + " " + cmd.description).toLowerCase()
    if (!q || blob.indexOf(q) !== -1) out.push(cmd)
  }
  return out
}

function enrichProcess(row, meta) {
  var next = {}
  for (var key in row) next[key] = row[key]
  if (!meta) return next
  if (meta.uid !== undefined) next.uid = Number(meta.uid)
  if (meta.startTime !== undefined) next.startTime = Number(meta.startTime)
  if (meta.cwd) next.cwd = String(meta.cwd)
  if (meta.exe) next.exe = String(meta.exe)
  if (meta.command) next.command = String(meta.command)
  return next
}

function parseStatusUid(raw) {
  var match = String(raw || "").match(/^Uid:\s+(\d+)/m)
  return match ? parseInt(match[1], 10) : -1
}

function parseStatStartTime(raw) {
  var text = String(raw || "")
  var close = text.lastIndexOf(")")
  if (close < 0) return 0
  var rest = trim(text.slice(close + 1)).split(/\s+/)
  return parseInt(rest[19], 10) || 0
}

function parseCmdline(raw) {
  return String(raw || "").slice(0, MAX_META_FIELD_BYTES).replace(/\u0000/g, " ").replace(/\s+$/g, "")
}

function parseProcMeta(raw) {
  var lines = String(raw || "").split(/\n/)
  var out = {}
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var parts = lines[i].split("\t")
    if (parts.length !== 6) continue
    var pid = parseInt(parts[0], 10) || 0
    var uid = parseInt(parts[1], 10)
    var startTime = parseInt(parts[2], 10) || 0
    if (pid <= 1 || !isFinite(uid) || uid < 0 || startTime <= 0) continue
    out[String(pid)] = {
      uid: uid,
      startTime: startTime,
      command: trim(parts[3]).slice(0, MAX_META_FIELD_BYTES),
      cwd: trim(parts[4]).slice(0, MAX_META_FIELD_BYTES),
      exe: trim(parts[5]).slice(0, MAX_META_FIELD_BYTES)
    }
  }
  return out
}

function canKillRow(row, currentUid, expectedDockerHost) {
  if (!row) return false
  if (row.kind === "container") return canStopContainer(row, expectedDockerHost)
  return canSignalProcess(row, currentUid, row.startTime)
}

function safeConfirmFragment(value) {
  return String(value || "")
    .replace(/</g, "‹")
    .replace(/>/g, "›")
    .replace(/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/g, " ")
}

function titleFor(row) {
  if (row.label) return row.label
  if (row.containerName) return row.containerName
  if (row.comm) return row.comm
  return "port " + row.port
}

function subtitleFor(row) {
  var bits = [String(row.host) + ":" + String(row.port)]
  if (row.pid) bits.push("pid " + row.pid)
  if (row.command && row.command !== row.comm) bits.push(row.command)
  else if (row.cwd) bits.push(row.cwd)
  if (row.kind === "container") bits.push("container")
  return bits.join(" · ")
}

function confirmMessage(row, signalName) {
  var signal = killSignal(signalName)
  var title = safeConfirmFragment(titleFor(row))
  if (row.kind === "container")
    return "Stop container " + title + " (port " + row.port + ")?"
  return "Send SIG" + signal + " to " + title + " (pid " + row.pid + ", port " + row.port + ")?"
}

function devPortCount(listeners, currentUid) {
  var n = 0
  for (var i = 0; i < (listeners || []).length; i++) {
    var row = listeners[i]
    if (row.label || isLoopback(row.host) || Number(row.uid) === Number(currentUid) || row.kind === "container")
      n += 1
  }
  return n
}

function parseSettings(raw) {
  var parsed
  try {
    parsed = raw ? JSON.parse(String(raw)) : {}
  } catch (e) {
    parsed = {}
  }
  if (!parsed || typeof parsed !== "object") parsed = {}
  var socketValue = parsed.dockerSocket === undefined ? "/var/run/docker.sock" : parsed.dockerSocket
  return {
    killSignal: killSignal(parsed.killSignal),
    includeUdp: parsed.includeUdp === true,
    includeDocker: parsed.includeDocker === true,
    dockerSocket: dockerHost(socketValue),
    ignoredPorts: String(parsed.ignoredPorts === undefined ? "53,631,5353" : parsed.ignoredPorts),
    httpsPorts: String(parsed.httpsPorts || "443,8443"),
    refreshIntervalSec: Math.max(2, Math.min(120, parseInt(parsed.refreshIntervalSec, 10) || 5))
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_ROWS: MAX_ROWS,
    MAX_OUTPUT_BYTES: MAX_OUTPUT_BYTES,
    MAX_META_FIELD_BYTES: MAX_META_FIELD_BYTES,
    maxOutputBytes: maxOutputBytes,
    maxMetaFieldBytes: maxMetaFieldBytes,
    COMMANDS: COMMANDS,
    parsePort: parsePort,
    parsePortQuery: parsePortQuery,
    parseNamedInput: parseNamedInput,
    parseSs: parseSs,
    parsePortSet: parsePortSet,
    portSetHas: portSetHas,
    dropIgnored: dropIgnored,
    filterListeners: filterListeners,
    listenersOnPort: listenersOnPort,
    parseNames: parseNames,
    applyNames: applyNames,
    upsertName: upsertName,
    removeName: removeName,
    namedPortRows: namedPortRows,
    canSignalProcess: canSignalProcess,
    liveIdentityMatches: liveIdentityMatches,
    canKillRow: canKillRow,
    killSignal: killSignal,
    dockerHost: dockerHost,
    validContainerId: validContainerId,
    canStopContainer: canStopContainer,
    openUrl: openUrl,
    parseDockerPs: parseDockerPs,
    mergeListeners: mergeListeners,
    dedupeSockets: dedupeSockets,
    filterCommands: filterCommands,
    enrichProcess: enrichProcess,
    parseStatusUid: parseStatusUid,
    parseStatStartTime: parseStatStartTime,
    parseCmdline: parseCmdline,
    parseProcMeta: parseProcMeta,
    titleFor: titleFor,
    subtitleFor: subtitleFor,
    confirmMessage: confirmMessage,
    devPortCount: devPortCount,
    parseSettings: parseSettings,
    isLoopback: isLoopback
  }
}
