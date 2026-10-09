// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PaperBar",
    platforms: [.macOS(.v13)],   // MenuBarExtra 는 macOS 13 Ventura 이상
    targets: [
        .executableTarget(
            name: "PaperBar",
            path: "Sources/PaperBar"
        )
    ]
)
