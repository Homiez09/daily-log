import Foundation
import Darwin
import HardwareKit

// DailyLogFanHelper — started as root by DailyLog after the user approves an admin prompt.
//
// It is deliberately tiny: it accepts three commands (AUTO / MANUAL <0-1> / PING) from a single
// client (the app's user) and translates them into SMC fan-key writes. It always hands fan
// control back to macOS when the app disconnects, goes silent, receives a signal, or when the
// SoC gets dangerously hot.

func log(_ message: String) {
    FileHandle.standardError.write(Data(("[fan-helper] " + message + "\n").utf8))
}

guard geteuid() == 0 else {
    log("must run as root")
    exit(1)
}

var uid: uid_t?
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    if argument == "--uid", let value = arguments.next(), let parsed = uid_t(value) { uid = parsed }
}
guard let ownerUID = uid, ownerUID != 0 else {
    log("usage: DailyLogFanHelper --uid <non-root uid>")
    exit(2)
}

var terminateRequested: sig_atomic_t = 0
for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
    signal(signalNumber) { _ in terminateRequested = 1 }
}
signal(SIGPIPE, SIG_IGN)

let smc: SMCConnection
do { smc = try SMCConnection() } catch {
    log("cannot open SMC: \(error)")
    exit(3)
}
let sensors = ThermalSensors()

guard !smc.readFans().isEmpty else {
    log("this Mac has no controllable fans")
    exit(4)
}

let socketPath = FanControlPaths.socketPath(uid: ownerUID)
let ownerGroup = getpwuid(ownerUID)?.pointee.pw_gid ?? 20
guard let listenFD = UnixSocket.listen(path: socketPath, owner: ownerUID, group: ownerGroup) else {
    log("cannot create socket at \(socketPath)")
    exit(5)
}

var clientFD: Int32 = -1
var lineBuffer = LineBuffer()
var isManual = false
var desiredFraction = 0.0
var lastCommandAt = Date()
let startedAt = Date()

@discardableResult
func restoreAutomatic(reason: String) -> Bool {
    var succeeded = true
    do { try smc.setFansAuto() } catch {
        succeeded = false
        log("restore auto failed (\(reason)): \(error)")
    }
    if isManual { log("restored automatic fan control: \(reason)") }
    isManual = false
    return succeeded
}

func rpmSummary(_ fans: [FanReading]) -> String {
    fans.map { "\($0.index):\(Int($0.targetRPM))" }.joined(separator: ",")
}

func handle(_ command: FanCommand) -> String {
    lastCommandAt = Date()
    switch command {
    case .ping:
        let die = sensors?.read()?.dieMax
        return "OK \(isManual ? "manual" : "auto") \(String(format: "%.3f", desiredFraction)) die=\(die.map { String(format: "%.1f", $0) } ?? "n/a")"

    case .auto:
        return restoreAutomatic(reason: "requested by app") ? "OK auto" : "ERR could-not-restore-auto"

    case .manual(let requested):
        let dieMax = sensors?.read()?.dieMax
        if FanSafety.shouldForceAuto(dieMax: dieMax) {
            restoreAutomatic(reason: "die temperature \(dieMax ?? 0)°C is too high for manual mode")
            return "ERR thermal"
        }
        let fraction = FanSafety.allowedFraction(requested: requested, dieMax: dieMax)
        do {
            let fans = try smc.setFansManual(fraction: fraction)
            isManual = true
            desiredFraction = fraction
            return "OK manual \(String(format: "%.3f", fraction)) \(rpmSummary(fans))"
        } catch {
            // Never leave the fans half-configured if a write failed part-way through.
            restoreAutomatic(reason: "manual write failed")
            return "ERR \(error)"
        }
    }
}

func periodicChecks() {
    guard isManual else { return }

    if Date().timeIntervalSince(lastCommandAt) > FanSafety.watchdogSeconds {
        restoreAutomatic(reason: "app stopped responding")
        return
    }

    let dieMax = sensors?.read()?.dieMax
    if FanSafety.shouldForceAuto(dieMax: dieMax) {
        restoreAutomatic(reason: "thermal safety override at \(dieMax ?? 0)°C")
        if clientFD >= 0 { UnixSocket.send(clientFD, line: "EVENT thermal") }
        return
    }

    // thermalmonitord can reclaim a fan on its own; put our setting back if it did.
    if smc.readFans().contains(where: { !$0.isManual }) {
        do { try smc.setFansManual(fraction: desiredFraction) }
        catch { restoreAutomatic(reason: "could not re-assert manual mode: \(error)") }
    }
}

log("ready for uid \(ownerUID)")

mainLoop: while terminateRequested == 0 {
    var descriptors = [pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)]
    if clientFD >= 0 { descriptors.append(pollfd(fd: clientFD, events: Int16(POLLIN), revents: 0)) }
    let ready = poll(&descriptors, nfds_t(descriptors.count), 1000)

    if ready > 0 {
        if descriptors[0].revents & Int16(POLLIN) != 0, let newClient = UnixSocket.accept(listenFD) {
            // The socket file is already 0600 and owned by the user; this is a second line of defense.
            if clientFD < 0, let peer = UnixSocket.peerUID(newClient), peer == ownerUID {
                clientFD = newClient
                lastCommandAt = Date()
            } else {
                close(newClient)
            }
        }

        if descriptors.count > 1, descriptors[1].revents != 0 {
            var chunk = [UInt8](repeating: 0, count: 512)
            let count = read(clientFD, &chunk, chunk.count)
            if count <= 0 { break mainLoop } // app quit or crashed
            for line in lineBuffer.append(Array(chunk.prefix(count))) {
                let reply = FanCommand(line: line).map(handle) ?? "ERR bad-command"
                UnixSocket.send(clientFD, line: reply)
            }
        }
    }

    periodicChecks()

    // Nobody ever connected: do not linger as a root process.
    if clientFD < 0, Date().timeIntervalSince(startedAt) > 30 { break mainLoop }
}

restoreAutomatic(reason: "helper exiting")
if clientFD >= 0 { close(clientFD) }
close(listenFD)
unlink(socketPath)
exit(0)
