// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ActivityCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ActivityCore", targets: ["ActivityCore"])],
    targets: [.target(name: "ActivityCore")]
)
