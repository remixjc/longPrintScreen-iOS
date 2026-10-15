// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "StitchCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "StitchCore", targets: ["StitchCore"])],
    targets: [
        .target(name: "StitchCore"),
        .target(name: "StitchImaging", dependencies: ["StitchCore"], path: "Imaging"),
        .testTarget(name: "StitchCoreTests", dependencies: ["StitchCore"], path: "Tests/CoreTests"),
        .testTarget(name: "StitchImagingTests", dependencies: ["StitchImaging", "StitchCore"], path: "Tests/ImagingTests")
    ]
)
