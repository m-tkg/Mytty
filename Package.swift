// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "mytty",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
    ],
    products: [
        .executable(name: "Mytty", targets: ["MyTTYApp"]),
        .executable(
            name: "mytty-agent-hook",
            targets: ["MyTTYAgentHook"]
        ),
        .executable(
            name: "mytty-ctl",
            targets: ["MyTTYCtl"]
        ),
        .executable(
            name: "mytty-clamshell-helper",
            targets: ["MyTTYClamshellHelper"]
        ),
        .library(name: "MyTTYCore", targets: ["MyTTYCore"]),
        .library(name: "GhosttyAdapter", targets: ["GhosttyAdapter"]),
        .library(name: "MyTTYRemoteKit", targets: ["MyTTYRemoteKit"]),
    ],
    targets: [
        .binaryTarget(
            name: "GhosttyKit",
            path: "Vendor/ghostty/macos/GhosttyKit.xcframework"
        ),
        .target(
            name: "MyTTYCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "GhosttyAdapter",
            dependencies: ["GhosttyKit"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
        .executableTarget(
            name: "MyTTYApp",
            dependencies: [
                "MyTTYCore",
                "GhosttyAdapter",
                "MyTTYRemoteKit",
            ],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Security"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("WebKit"),
            ]
        ),
        .executableTarget(
            name: "MyTTYAgentHook",
            dependencies: ["MyTTYCore"]
        ),
        .executableTarget(
            name: "MyTTYCtl",
            dependencies: ["MyTTYCore"]
        ),
        .executableTarget(
            name: "MyTTYClamshellHelper",
            dependencies: ["MyTTYCore"]
        ),
        .target(
            name: "MyTTYRemoteKit"
        ),
        .testTarget(
            name: "MyTTYCoreTests",
            dependencies: ["MyTTYCore"]
        ),
        .testTarget(
            name: "MyTTYRemoteKitTests",
            dependencies: ["MyTTYRemoteKit"]
        ),
        .testTarget(
            name: "GhosttyAdapterTests",
            dependencies: ["GhosttyAdapter"]
        ),
        .testTarget(
            name: "MyTTYAppTests",
            dependencies: ["MyTTYApp"]
        ),
    ]
)
