// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DiagCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "DiagCore", targets: ["DiagCore"])],
    targets: [
        .target(name: "DiagCore"),
        .testTarget(name: "DiagCoreTests", dependencies: ["DiagCore"]),
    ]
)
