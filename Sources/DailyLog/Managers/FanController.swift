import Foundation
import AppKit
import HardwareKit

enum FanControlError: Error, Equatable, LocalizedError {
    case cancelled
    case helperMissing
    case authorizationFailed(String)
    case helperUnreachable
    case timedOut
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Authorization was cancelled."
        case .helperMissing: return "Fan helper is missing from the app bundle. Rebuild with ./build.sh."
        case .authorizationFailed(let detail): return "Could not start the fan helper: \(detail)"
        case .helperUnreachable: return "The fan helper is not running."
        case .timedOut: return "The fan helper did not answer in time."
        case .rejected(let reason):
            switch reason {
            case "thermal": return "Mac is too hot for manual fan speeds; macOS took control back."
            case "bad-command": return "The fan helper did not understand the request."
            default: return "This Mac refused the fan change: \(reason)"
            }
        }
    }
}

/// App-side client for the root fan helper. Reading fan speeds needs no privileges (see
/// `SystemMonitorManager`); *changing* them requires writing SMC keys as root, so the first manual
/// request asks macOS for an admin password once and starts `DailyLogFanHelper` for this session.
final class FanController: ObservableObject {
    static let shared = FanController()

    enum Status: Equatable {
        case notConnected
        case authorizing
        case connected
    }

    @Published private(set) var status: Status = .notConnected
    /// What the helper last confirmed to the app (the SMC readout in the dashboard is the ground truth).
    @Published private(set) var appliedMode: FanControlMode = .auto
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?

    private let queue = DispatchQueue(label: "com.user.DailyLog.fan-control")
    private var socketFD: Int32 = -1
    private var lineBuffer = LineBuffer()
    private var keepAlive: DispatchSourceTimer?

    private var socketPath: String { FanControlPaths.socketPath(uid: getuid()) }

    // MARK: Public API (call from the main thread)

    /// Applies `mode`. `fraction` (0...1) is the position inside each fan's min...max range.
    /// The completion runs on the main thread with the error, if any.
    func apply(mode: FanControlMode, fraction: Double, completion: ((FanControlError?) -> Void)? = nil) {
        isBusy = true
        lastError = nil
        queue.async { [weak self] in
            guard let self else { return }
            let error = self.performApply(mode: mode, fraction: fraction)
            DispatchQueue.main.async {
                self.isBusy = false
                self.lastError = error?.errorDescription
                completion?(error)
            }
        }
    }

    /// Hands the fans back to macOS and drops the helper. Blocks briefly; used when the app quits.
    func shutdown() {
        // Bounded wait: if the queue is stuck behind an unanswered admin prompt we must still be able to quit.
        let finished = DispatchSemaphore(value: 0)
        queue.async { [self] in
            if socketFD >= 0 { _ = exchange(.auto, timeout: 4) }
            closeConnection()
            finished.signal()
        }
        _ = finished.wait(timeout: .now() + 6)
    }

    // MARK: Queue-confined implementation

    private func performApply(mode: FanControlMode, fraction: Double) -> FanControlError? {
        switch mode {
        case .auto:
            // Nothing is overridden if we never connected, so there is nothing to undo.
            guard socketFD >= 0 else { publish(applied: .auto); return nil }
            switch exchange(.auto, timeout: 15) {
            case .success:
                stopKeepAlive()
                publish(applied: .auto)
                return nil
            case .failure(let error):
                handleConnectionLoss(after: error)
                return error
            }

        case .manual:
            if let error = ensureConnected() { return error }
            let clamped = min(max(fraction, 0), 1)
            switch exchange(.manual(fraction: clamped), timeout: 30) {
            case .success:
                startKeepAlive()
                publish(applied: .manual)
                return nil
            case .failure(let error):
                if case .rejected = error {
                    // The helper already restored automatic mode itself.
                    stopKeepAlive()
                    publish(applied: .auto)
                } else {
                    handleConnectionLoss(after: error)
                }
                return error
            }
        }
    }

    private func ensureConnected() -> FanControlError? {
        if socketFD >= 0 { return nil }

        if let fd = UnixSocket.connect(path: socketPath) {
            adopt(fd)
            return nil
        }

        DispatchQueue.main.async { self.status = .authorizing }
        if let error = launchHelperWithAdminPrompt() {
            DispatchQueue.main.async { self.status = .notConnected }
            return error
        }

        // The helper creates its socket a moment after being spawned.
        for _ in 0..<40 {
            if let fd = UnixSocket.connect(path: socketPath) {
                adopt(fd)
                return nil
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        DispatchQueue.main.async { self.status = .notConnected }
        return .authorizationFailed("the helper did not start (this Mac may have no controllable fans)")
    }

    private func adopt(_ fd: Int32) {
        socketFD = fd
        lineBuffer = LineBuffer()
        DispatchQueue.main.async { self.status = .connected }
    }

    private func closeConnection() {
        stopKeepAlive()
        if socketFD >= 0 { close(socketFD) }
        socketFD = -1
        publish(applied: .auto)
        DispatchQueue.main.async { self.status = .notConnected }
    }

    private func handleConnectionLoss(after error: FanControlError) {
        if error == .timedOut || error == .helperUnreachable { closeConnection() }
    }

    private func publish(applied: FanControlMode) {
        DispatchQueue.main.async { self.appliedMode = applied }
    }

    /// Sends one command and waits for its single reply line. Unsolicited `EVENT` lines from the
    /// helper (e.g. a thermal override) are consumed on the way.
    private func exchange(_ command: FanCommand, timeout: TimeInterval) -> Result<String, FanControlError> {
        guard socketFD >= 0 else { return .failure(.helperUnreachable) }
        guard UnixSocket.send(socketFD, line: command.line) else { return .failure(.helperUnreachable) }

        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return .failure(.timedOut) }

            var descriptor = pollfd(fd: socketFD, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(remaining, 1.0) * 1000))
            if ready < 0 && errno != EINTR { return .failure(.helperUnreachable) }
            guard ready > 0 else { continue }

            var chunk = [UInt8](repeating: 0, count: 512)
            let count = read(socketFD, &chunk, chunk.count)
            if count <= 0 { return .failure(.helperUnreachable) }

            for line in lineBuffer.append(Array(chunk.prefix(count))) {
                if line.hasPrefix("EVENT") {
                    stopKeepAlive()
                    publish(applied: .auto)
                    DispatchQueue.main.async { self.lastError = FanControlError.rejected("thermal").errorDescription }
                } else if line.hasPrefix("OK") {
                    return .success(line)
                } else if line.hasPrefix("ERR") {
                    return .failure(.rejected(String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)))
                }
            }
        }
    }

    // MARK: Keep-alive (the helper restores automatic mode if it hears nothing for a while)

    private func startKeepAlive() {
        guard keepAlive == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if case .failure(let error) = self.exchange(.ping, timeout: 5) {
                self.handleConnectionLoss(after: error)
                DispatchQueue.main.async { self.lastError = "Fan helper stopped; fans are back on automatic." }
            }
        }
        keepAlive = timer
        timer.resume()
    }

    private func stopKeepAlive() {
        keepAlive?.cancel()
        keepAlive = nil
    }

    // MARK: Admin authorization

    private func launchHelperWithAdminPrompt() -> FanControlError? {
        guard let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() else { return .helperMissing }
        let helperPath = executableDirectory.appendingPathComponent("DailyLogFanHelper").path
        guard FileManager.default.isExecutableFile(atPath: helperPath) else { return .helperMissing }

        let shellCommand = "\(Self.shellQuote(helperPath)) --uid \(getuid()) > /dev/null 2>&1 &"
        let prompt = "DailyLog needs permission to control your Mac's fans."
        let script = "do shell script \(Self.appleScriptString(shellCommand)) with administrator privileges with prompt \(Self.appleScriptString(prompt))"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        do { try process.run() } catch { return .authorizationFailed(error.localizedDescription) }
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }

        let detail = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // AppleScript error -128 is "User canceled."
        if detail.contains("-128") || detail.localizedCaseInsensitiveContains("cancel") { return .cancelled }
        return .authorizationFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ string: String) -> String {
        "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
