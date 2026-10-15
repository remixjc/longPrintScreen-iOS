// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "StitchCore",
    products: [.library(name: "StitchCore", targets: ["StitchCore"])],
    targets: [
        .target(name: "StitchCore"),
        .testTarget(name: "StitchCoreTests", dependencies: ["StitchCore"], path: "Tests/CoreTests")
    ]
)
