// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Martin",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Martin", targets: ["Martin"]),
    ],
    targets: [
        .target(name: "MartinKit"),
        .executableTarget(name: "Martin", dependencies: ["MartinKit"], path: "Martin"),
        .testTarget(name: "MartinKitTests", dependencies: ["MartinKit"]),
    ]
)
