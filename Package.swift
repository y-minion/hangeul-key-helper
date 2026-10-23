// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "HangeulKeyHelper", platforms: [.macOS(.v13)],
    products: [.executable(name: "HangeulKeyApp", targets: ["HangeulKeyApp"]), .executable(name: "key-agent", targets: ["KeyAgent"])],
    targets: [.target(name: "KeyCore"), .executableTarget(name: "HangeulKeyApp", dependencies: ["KeyCore"]), .executableTarget(name: "KeyAgent", dependencies: ["KeyCore"]), .testTarget(name: "KeyCoreTests", dependencies: ["KeyCore"])]
)
