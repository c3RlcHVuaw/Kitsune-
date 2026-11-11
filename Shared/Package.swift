// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Shared",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "Shared", targets: ["Shared"])],
    targets: [
        .target(name: "Shared"),
        .testTarget(name: "SharedTests", dependencies: ["Shared"], resources: [.copy("Golden")]),
    ]
)
