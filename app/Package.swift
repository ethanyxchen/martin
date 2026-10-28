// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Martin",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Martin", targets: ["Martin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(name: "MartinKit"),
        .executableTarget(
            name: "Martin",
            dependencies: ["MartinKit", .product(name: "Sparkle", package: "Sparkle")],
            path: "Martin",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "MartinKitTests", dependencies: ["MartinKit"]),
        .testTarget(name: "MartinTests", dependencies: ["Martin"]),
    ]
)
