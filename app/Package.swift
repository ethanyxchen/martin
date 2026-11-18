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
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.59.3"),
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.7"),
    ],
    targets: [
        .target(name: "MartinKit"),
        .executableTarget(
            name: "Martin",
            dependencies: [
                "MartinKit",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "PostHog", package: "posthog-ios"),
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            path: "Martin",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .target(name: "MartinKitFakes", dependencies: ["MartinKit"], path: "Tests/Fakes"),
        .testTarget(name: "MartinKitTests", dependencies: ["MartinKit", "MartinKitFakes"]),
        .testTarget(name: "MartinTests", dependencies: ["Martin", "MartinKitFakes"]),
    ]
)
