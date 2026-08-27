#!/usr/bin/env node
"use strict"

var assert = require("assert")
var Model = require("../Model.js")

var ssSample = [
  "LISTEN 0      4096       127.0.0.1:3000       0.0.0.0:*    users:((\"node\",pid=4242,fd=23))",
  "LISTEN 0      511              *:22                 *:*    users:((\"sshd\",pid=1,fd=3))",
  "LISTEN 0      4096           [::1]:5173            [::]:*    users:((\"node\",pid=99,fd=18))",
  "LISTEN 0      4096         0.0.0.0:8080         0.0.0.0:*"
].join("\n")

var listeners = Model.parseSs(ssSample)
assert.equal(listeners.length, 4)
assert.equal(listeners[0].port, 3000)
assert.equal(listeners[0].host, "127.0.0.1")
assert.equal(listeners[0].pid, 4242)
assert.equal(listeners[0].comm, "node")
assert.equal(listeners[0].proto, "tcp")
assert.equal(listeners[0].exposed, false)
assert.equal(listeners[1].port, 22)
assert.equal(listeners[1].exposed, true)
assert.equal(listeners[1].pid, 1)
assert.equal(listeners[2].host, "::1")
assert.equal(listeners[2].port, 5173)
assert.equal(listeners[3].pid, 0)
assert.equal(listeners[3].port, 8080)
assert.equal(listeners[3].exposed, true)

var mixedProtocol = Model.parseSs([
  "udp UNCONN 0 0 127.0.0.1:5355 0.0.0.0:* users:((\"dns\",pid=88,fd=4))",
  "tcp LISTEN 0 128 127.0.0.1:5355 0.0.0.0:* users:((\"web\",pid=89,fd=5))"
].join("\n"))
assert.equal(mixedProtocol.length, 2)
assert.equal(mixedProtocol[0].proto, "udp")
assert.equal(mixedProtocol[0].port, 5355)
assert.equal(mixedProtocol[1].proto, "tcp")

var ignored = Model.parsePortSet("53,631,8000-8010")
assert.ok(Model.portSetHas(ignored, 53))
assert.ok(Model.portSetHas(ignored, 8005))
assert.ok(!Model.portSetHas(ignored, 3000))

var kept = Model.dropIgnored(listeners, ignored)
assert.equal(kept.length, 4)
assert.equal(Model.dropIgnored([{ port: 53 }], ignored).length, 0)

assert.equal(Model.filterListeners(listeners, "3000").length, 1)
assert.equal(Model.filterListeners(listeners, "node").length, 2)
assert.equal(Model.filterListeners(listeners, "next").length, 0)

var named = Model.applyNames(listeners, { "3000": "Next.js", "22": "SSH" })
assert.equal(named[0].label, "Next.js")
assert.equal(Model.filterListeners(named, "next").length, 1)

assert.equal(Model.parseNames("{not json"), null)
assert.deepEqual(Model.parseNames('{"3000":"Next.js"}'), { "3000": "Next.js" })
assert.deepEqual(Model.parseNames(JSON.stringify({ "3000": "Next.js", "nope": "x", "80": "" })), { "3000": "Next.js" })

var names = Model.upsertName({}, 5173, "Vite")
assert.equal(names["5173"], "Vite")
assert.deepEqual(Model.removeName(names, 5173), {})

assert.equal(Model.canSignalProcess({ pid: 4242, uid: 1000, startTime: 99 }, 1000, 99), true)
assert.equal(Model.canSignalProcess({ pid: 1, uid: 1000, startTime: 99 }, 1000, 99), false)
assert.equal(Model.canSignalProcess({ pid: 4242, uid: 0, startTime: 99 }, 1000, 99), false)
assert.equal(Model.canSignalProcess({ pid: 4242, uid: 1000, startTime: 0 }, 1000, 0), false)
assert.equal(Model.canSignalProcess({ pid: 4242, uid: 1000, startTime: 1 }, 1000, 99), false)
assert.equal(Model.canSignalProcess({ pid: 4242, uid: 1000, startTime: 99 }, 1000, 98), false)

assert.equal(Model.liveIdentityMatches({ pid: 4242, uid: 1000, startTime: 99 }, 1000, 99, 1000), true)
assert.equal(Model.liveIdentityMatches({ pid: 4242, uid: 1000, startTime: 99 }, 1000, 100, 1000), false)
assert.equal(Model.liveIdentityMatches({ pid: 4242, uid: 1000, startTime: 99 }, 0, 99, 1000), false)

var overflowSs = []
for (var i = 0; i < Model.MAX_ROWS + 40; i++) {
  overflowSs.push("LISTEN 0 1 127.0.0.1:" + (3000 + (i % 40000)) + " 0.0.0.0:* users:((\"n\",pid=" + (100 + i) + ",fd=1))")
}
assert.equal(Model.parseSs(overflowSs.join("\n")).length, Model.MAX_ROWS)

var overflowDocker = []
for (var d = 0; d < Model.MAX_ROWS + 10; d++) {
  var dockerId = ("000000000000" + d.toString(16)).slice(-12)
  overflowDocker.push(dockerId + "\tc" + d + "\t0.0.0.0:" + (4000 + (d % 20000)) + "->80/tcp")
}
assert.equal(Model.parseDockerPs(overflowDocker.join("\n")).length, Model.MAX_ROWS)

assert.equal(Model.killSignal("KILL"), "KILL")
assert.equal(Model.killSignal("TERM"), "TERM")
assert.equal(Model.killSignal("nope"), "TERM")

assert.equal(Model.openUrl({ host: "127.0.0.1", port: 3000 }, ""), "http://127.0.0.1:3000")
assert.equal(Model.openUrl({ host: "0.0.0.0", port: 443 }, "443,8443"), "https://127.0.0.1:443")
assert.equal(Model.openUrl({ host: "::", port: 8080 }, ""), "http://[::1]:8080")

var dockerId = "abc123def456"
var localDockerHost = "unix:///var/run/docker.sock"
var docker = Model.parseDockerPs(dockerId + "\tweb\t0.0.0.0:3000->80/tcp, 127.0.0.1:3001->80/tcp\n", localDockerHost)
assert.equal(docker.length, 2)
assert.equal(docker[0].containerId, dockerId)
assert.equal(docker[0].containerName, "web")
assert.equal(docker[0].port, 3000)
assert.equal(docker[0].kind, "container")
assert.equal(docker[0].proto, "tcp")
assert.equal(docker[0].exposed, true)
assert.equal(docker[0].dockerHost, localDockerHost)
assert.equal(docker[1].port, 3001)
assert.equal(docker[1].exposed, false)

var dualStackDocker = Model.parseDockerPs(dockerId + "\tweb\t0.0.0.0:3000->80/tcp, [::]:3000->80/tcp\n", localDockerHost)
assert.equal(dualStackDocker.length, 2)
var collapsedDocker = Model.dedupeSockets(dualStackDocker)
assert.equal(collapsedDocker.length, 1)
assert.equal(collapsedDocker[0].port, 3000)
assert.equal(collapsedDocker[0].host, "0.0.0.0")
assert.equal(collapsedDocker[0].exposed, true)

var dualStackSs = Model.dedupeSockets([
  { port: 3000, host: "127.0.0.1", pid: 4242, comm: "node", exposed: false, kind: "process" },
  { port: 3000, host: "::1", pid: 4242, comm: "node", exposed: false, kind: "process" }
])
assert.equal(dualStackSs.length, 1)
assert.equal(dualStackSs[0].pid, 4242)

var separateProtocols = Model.dedupeSockets([
  { proto: "tcp", port: 3000, host: "127.0.0.1", pid: 4242, comm: "node", exposed: false, kind: "process" },
  { proto: "udp", port: 3000, host: "127.0.0.1", pid: 4242, comm: "node", exposed: false, kind: "process" }
])
assert.equal(separateProtocols.length, 2)

var merged = Model.mergeListeners(
  [
    { port: 3000, host: "0.0.0.0", pid: 9, comm: "docker-proxy", exposed: true, kind: "process" },
    { port: 3000, host: "::", pid: 10, comm: "docker-proxy", exposed: true, kind: "process" }
  ],
  dualStackDocker
)
assert.equal(merged.length, 1)
assert.equal(merged[0].kind, "container")
assert.equal(merged[0].containerName, "web")
assert.equal(merged[0].port, 3000)

var mixed = Model.mergeListeners(
  [{ port: 3000, host: "0.0.0.0", pid: 9, comm: "docker-proxy", exposed: true, kind: "process" }],
  docker
)
assert.equal(mixed.length, 2)
assert.equal(mixed[0].kind, "container")
assert.equal(mixed[1].port, 3001)

var cmds = Model.filterCommands("kill")
assert.equal(cmds.length, 1)
assert.equal(cmds[0].id, "kill-port")
assert.equal(Model.filterCommands("").length, 3)

var onPort = Model.listenersOnPort(named, 3000)
assert.equal(onPort.length, 1)
assert.equal(Model.parsePortQuery("3000"), 3000)
assert.equal(Model.parsePortQuery("  80 "), 80)
assert.equal(Model.parsePortQuery("next"), 0)
assert.equal(Model.parsePortQuery("70000"), 0)
assert.deepEqual(Model.parseNamedInput("3000=Next.js"), { port: 3000, label: "Next.js" })
assert.deepEqual(Model.parseNamedInput("5173 Vite"), { port: 5173, label: "Vite" })
assert.equal(Model.parseNamedInput("nope"), null)

assert.equal(Model.dockerHost("/var/run/docker.sock"), localDockerHost)
assert.equal(Model.dockerHost("unix:///run/user/1000/docker.sock"), "unix:///run/user/1000/docker.sock")
assert.equal(Model.dockerHost("tcp://prod.example:2376"), "")
assert.equal(Model.dockerHost("ssh://prod.example"), "")
assert.equal(Model.dockerHost("/var/run/../tmp/docker.sock"), "")
assert.equal(Model.validContainerId(dockerId), true)
assert.equal(Model.validContainerId("--help"), false)
assert.equal(Model.canStopContainer(docker[0], localDockerHost), true)
assert.equal(Model.canStopContainer(docker[0], "unix:///run/user/1000/docker.sock"), false)
assert.equal(Model.canStopContainer({ kind: "container", containerId: dockerId }, localDockerHost), false)
assert.equal(Model.parseDockerPs("--help\tweb\t0.0.0.0:3000->80/tcp\n", localDockerHost).length, 0)

var maliciousConfirmation = Model.confirmMessage({
  kind: "process",
  comm: '<img src="https://example.invalid/pixel">',
  pid: 4242,
  port: 3000
}, "TERM")
assert.equal(/[<>]/.test(maliciousConfirmation), false)

var meta = Model.parseProcMeta("4242\t1000\t99\tnode server.js\t/tmp/app\t/usr/bin/node\n")
assert.equal(meta["4242"].uid, 1000)
assert.equal(meta["4242"].startTime, 99)
assert.equal(meta["4242"].command, "node server.js")
assert.deepEqual(Model.parseProcMeta("1\t0\t1\tinit\t/\t/usr/bin/init\n"), {})
var longMeta = Model.parseProcMeta("4242\t1000\t99\t" + "x".repeat(Model.MAX_META_FIELD_BYTES + 20) + "\t/tmp/app\t/usr/bin/node\n")
assert.equal(longMeta["4242"].command.length, Model.MAX_META_FIELD_BYTES)

var defaultSettings = Model.parseSettings("{}")
assert.equal(defaultSettings.includeDocker, false)
assert.equal(defaultSettings.dockerSocket, localDockerHost)
var unsafeSettings = Model.parseSettings('{"includeDocker":true,"dockerSocket":"tcp://prod.example:2376"}')
assert.equal(unsafeSettings.includeDocker, true)
assert.equal(unsafeSettings.dockerSocket, "")

var count = Model.devPortCount(named, 1000)
assert.ok(count >= 1)

console.log("ok")
