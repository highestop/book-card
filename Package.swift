// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BookCard", platforms: [.macOS(.v14)], products: [.executable(name: "BookCard", targets: ["BookCard"])], targets: [.executableTarget(name: "BookCard")], swiftLanguageModes: [.v5])
