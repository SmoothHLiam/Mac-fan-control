// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacFanControl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacFanControl", targets: ["MacFanControl"]),
        .executable(name: "FanHelper", targets: ["FanHelper"]),
    ],
    targets: [
        // Hardware-independent logic (curves, controller, profiles, SMC codec) + SMC client / XPC contract on macOS.
        .target(name: "FanCore"),
        // Privileged daemon: the only component that writes to the SMC.
        .executableTarget(name: "FanHelper", dependencies: ["FanCore"]),
        // Menu bar app + control center.
        .executableTarget(name: "MacFanControl", dependencies: ["FanCore"]),
        .testTarget(name: "FanCoreTests", dependencies: ["FanCore"]),
    ]
)
