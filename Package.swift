// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "FocusCore", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "FocusCore", targets: ["FocusCore"])], targets: [.target(name: "FocusCore", path: "Shared"), .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"], path: "CoreTests")], swiftLanguageModes: [.v5])
