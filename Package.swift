// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Klip",
    platforms: [.macOS(.v13)],
    targets: [
        // Core library: no AppKit. Storage, limits, search, configuration.
        .target(
            name: "KlipCore",
            path: "Sources/KlipCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // The app: pasteboard, hotkey, panel, settings.
        .executableTarget(name: "Klip", dependencies: ["KlipCore"], path: "Sources/Klip"),
        // Tests are a plain executable run with `swift run KlipCoreTests`:
        // this machine has Command Line Tools only, and XCTest ships with Xcode.
        .executableTarget(
            name: "KlipCoreTests",
            dependencies: ["KlipCore"],
            path: "Tests/KlipCoreTests"
        ),
    ]
)
