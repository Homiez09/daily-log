// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DailyLog",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DailyLog", targets: ["DailyLog"]),
        .executable(name: "DailyLogFanHelper", targets: ["DailyLogFanHelper"])
    ],
    dependencies: [],
    targets: [
        // C struct layout for the AppleSMC user client (must match the kernel ABI exactly).
        .target(
            name: "CSMC",
            path: "Sources/CSMC"
        ),
        // SMC access, fan curve/protocol, and IOHID temperature sensors. Shared by the app
        // (read-only) and the privileged fan helper (read + write).
        .target(
            name: "HardwareKit",
            dependencies: ["CSMC"],
            path: "Sources/HardwareKit"
        ),
        .executableTarget(
            name: "DailyLog",
            dependencies: ["HardwareKit"],
            path: "Sources/DailyLog"
        ),
        // Runs as root (started by the app after an admin prompt) and is the only code
        // that ever writes fan keys to the SMC.
        .executableTarget(
            name: "DailyLogFanHelper",
            dependencies: ["HardwareKit"],
            path: "Sources/DailyLogFanHelper"
        ),
        .testTarget(
            name: "DailyLogTests",
            dependencies: ["DailyLog", "HardwareKit"],
            path: "Tests/DailyLogTests"
        )
    ]
)
