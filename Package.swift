// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentNotchPlus",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentNotchPlus",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources"
        ),
    ]
)
