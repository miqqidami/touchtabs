// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TouchTabs",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(name: "TouchTabs", path: "Sources/TouchTabs"),
    ]
)
