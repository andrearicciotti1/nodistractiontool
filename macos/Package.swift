// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NoDistraction",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NoDistraction",
            path: "Sources/NoDistraction"
        ),
    ]
)
