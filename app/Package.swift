// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MartinKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MartinKit", targets: ["MartinKit"]),
    ],
    targets: [
        .target(name: "MartinKit"),
        .testTarget(name: "MartinKitTests", dependencies: ["MartinKit"]),
    ]
)
