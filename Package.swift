// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Slingshot",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SlingshotCore", targets: ["SlingshotCore"])
    ],
    targets: [
        .target(name: "SlingshotCore", path: "Sources/SlingshotCore"),
        .executableTarget(name: "Slingshot", dependencies: ["SlingshotCore"], path: "Sources/Slingshot"),
        .executableTarget(name: "SlingshotTests", dependencies: ["SlingshotCore"], path: "Sources/SlingshotTests"),
    ]
)
