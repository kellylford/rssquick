// swift-tools-version: 6.0
import PackageDescription

// The executable is a thin shell: everything it does lives in RSSQuickUI, so the window and its
// focus handling can be built by a test without launching an application. That split is the
// macOS equivalent of the WPF FocusHarness, and it exists for the same reason - focus behaviour
// is the part of this program most worth testing and the part hardest to check by hand.
let package = Package(
    name: "RSSQuick",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure functions and value types. No AppKit, so it builds and tests under Swift 6's
        // strict concurrency checking without qualification.
        .target(
            name: "RSSQuickCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The window, the menus and the focus management.
        .target(
            name: "RSSQuickUI",
            dependencies: ["RSSQuickCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Only the test targets depend on this. It is a target rather than test-local files
        // because both test targets need the loopback server and the sample documents.
        .target(
            name: "RSSQuickTestSupport",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "rssquick",
            dependencies: ["RSSQuickUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RSSQuickCoreTests",
            dependencies: ["RSSQuickCore", "RSSQuickTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RSSQuickUITests",
            dependencies: ["RSSQuickUI", "RSSQuickCore", "RSSQuickTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
