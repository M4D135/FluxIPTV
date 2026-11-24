// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FluxIPTV",
    platforms: [.macOS(.v14), .tvOS(.v17)],
    products: [
        .library(name: "FluxIPTVCore", targets: ["FluxIPTVCore"])
    ],
    targets: [
        .target(name: "FluxIPTVCore", path: "Sources/FluxIPTVCore"),
        .testTarget(name: "FluxIPTVCoreTests", dependencies: ["FluxIPTVCore"], path: "Tests/FluxIPTVCoreTests")
    ]
)
