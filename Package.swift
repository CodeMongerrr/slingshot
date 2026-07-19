// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Slingshot",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SlingshotCore", targets: ["SlingshotCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(name: "SlingshotCore", path: "Sources/SlingshotCore"),
        .executableTarget(
            name: "Slingshot",
            dependencies: [
                "SlingshotCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Slingshot"
        ),
        .executableTarget(name: "SlingshotTests", dependencies: ["SlingshotCore"], path: "Sources/SlingshotTests"),
    ]
)
