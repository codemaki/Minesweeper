// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacosMinesweeper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacosMinesweeper",
            path: "Sources/MacosMinesweeper"
        )
    ]
)
