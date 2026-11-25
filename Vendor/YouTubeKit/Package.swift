// swift-tools-version: 5.9
import PackageDescription

// Local, audited subset. No remote package, proxy or account dependency.
let package = Package(
    name: "YouTubeKit",
    platforms: [.macOS(.v14), .tvOS(.v17), .iOS(.v17)],
    products: [.library(name: "YouTubeKit", type: .static, targets: ["YouTubeKit"])],
    targets: [
        .target(name: "YouTubeKit", resources: [.process("Resources")]),
        .testTarget(name: "YouTubeKitTests", dependencies: ["YouTubeKit"])
    ]
)
