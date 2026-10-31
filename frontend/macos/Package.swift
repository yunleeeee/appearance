// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FilePetShell",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FilePetShell",
            path: "Sources/FilePetShell",
            resources: [.copy("Resources/Characters"), .copy("Resources/Flowers"), .copy("Resources/Garden")]
        ),
        .testTarget(
            name: "FilePetShellTests",
            dependencies: ["FilePetShell"],
            path: "Tests/FilePetShellTests"
        )
    ]
)
