// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusNav",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "StatusNav", targets: ["StatusNav"])],
    targets: [
        .target(name: "StatusNavCore"),
        .target(name: "HardwareTelemetry", publicHeadersPath: "include",
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .executableTarget(name: "StatusNav", dependencies: ["StatusNavCore", "HardwareTelemetry"]),
        .testTarget(name: "StatusNavCoreTests", dependencies: ["StatusNavCore", "HardwareTelemetry"])
    ],
    swiftLanguageModes: [.v6]
)
