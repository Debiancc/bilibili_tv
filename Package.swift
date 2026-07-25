// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "bilibili_tv",
    platforms: [
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "bilibili_tv",
            targets: ["bilibili_tv"]
        )
    ],
    dependencies: [
        // 🌟 Pulse & PulseUI 网络日志与抓包调试库
        .package(url: "https://github.com/kean/Pulse.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "bilibili_tv",
            dependencies: [
                .product(name: "Pulse", package: "Pulse"),
                .product(name: "PulseUI", package: "Pulse")
            ],
            path: "bilibili_tv"
        )
    ]
)
