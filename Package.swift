// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "BookCard",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "BookCardCore", targets: ["BookCardCore"]),
        .executable(name: "BookCard", targets: ["BookCardMac"])
    ],
    targets: [
        .target(name: "BookCardCore"),
        .executableTarget(name: "BookCardMac", dependencies: ["BookCardCore"], path: "Apps/macOS"),
        .testTarget(name: "BookCardCoreTests", dependencies: ["BookCardCore"], path: "Tests/BookCardTests")
    ],
    swiftLanguageModes: [.v5]
)
