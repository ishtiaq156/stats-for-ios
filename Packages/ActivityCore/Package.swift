// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ActivityCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ActivityCore", targets: ["ActivityCore"])],
    targets: [
        .binaryTarget(name: "Spake2FFI", path: "Vendor/Spake2FFI.xcframework"),
        .target(name: "ActivityCore", dependencies: ["Spake2FFI"]),
        .testTarget(name: "ActivityCoreTests", dependencies: ["ActivityCore"])
    ],
    swiftLanguageModes: [.v6]
)
