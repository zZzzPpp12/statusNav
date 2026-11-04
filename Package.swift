// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusNav",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "StatusNav", targets: ["StatusNav"])],
    targets: [
        .target(name: "StatusNavCore"),
        .executableTarget(name: "StatusNav", dependencies: ["StatusNavCore"]),
        .testTarget(name: "StatusNavCoreTests", dependencies: ["StatusNavCore"])
    ],
    swiftLanguageModes: [.v6]
)
