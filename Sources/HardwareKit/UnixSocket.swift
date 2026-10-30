import Foundation
import Darwin

/// Minimal blocking Unix-domain-socket helpers shared by the app and the root fan helper.
public enum UnixSocket {
    public static func makeAddress(path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                    _ = strncpy(destination, source, capacity - 1)
                }
            }
        }
        return address
    }

    private static func disableSigPipe(_ fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Connects to a listening socket, or returns nil if nothing is listening (helper not running).
    public static func connect(path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = makeAddress(path: path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { close(fd); return nil }
        disableSigPipe(fd)
        return fd
    }

    /// Creates a listening socket that only `owner` can connect to.
    public static func listen(path: String, owner: uid_t, group: gid_t) -> Int32? {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        // Create it 0600 from the start so there is no window where others could connect.
        let previousMask = umask(0o177)
        var address = makeAddress(path: path)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previousMask)
        guard bound == 0 else { close(fd); return nil }

        guard chown(path, owner, group) == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 1) == 0 else {
            close(fd)
            unlink(path)
            return nil
        }
        disableSigPipe(fd)
        return fd
    }

    public static func accept(_ listenFD: Int32) -> Int32? {
        let fd = Darwin.accept(listenFD, nil, nil)
        guard fd >= 0 else { return nil }
        disableSigPipe(fd)
        return fd
    }

    public static func peerUID(_ fd: Int32) -> uid_t? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 ? uid : nil
    }

    @discardableResult
    public static func send(_ fd: Int32, line: String) -> Bool {
        let bytes = Array((line + "\n").utf8)
        var sent = 0
        while sent < bytes.count {
            let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + sent, bytes.count - sent) }
            if written <= 0 { return false }
            sent += written
        }
        return true
    }
}

/// Accumulates raw socket bytes and yields complete newline-terminated lines.
public struct LineBuffer {
    private var pending: [UInt8] = []
    public init() {}

    public mutating func append(_ bytes: [UInt8]) -> [String] {
        pending.append(contentsOf: bytes)
        // A peer that never sends a newline must not be able to grow this without bound.
        if pending.count > 4096 { pending.removeAll() }
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineBytes = pending[..<newline]
            pending.removeSubrange(...newline)
            if let line = String(bytes: lineBytes, encoding: .utf8) { lines.append(line) }
        }
        return lines
    }
}
