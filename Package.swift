// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DailyLog",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DailyLog", targets: ["DailyLog"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DailyLog",
            dependencies: [],
            path: "Sources/DailyLog"
        ),
        .testTarget(
            name: "DailyLogTests",
            dependencies: ["DailyLog"],
            path: "Tests/DailyLogTests"
        )
    ]
)
