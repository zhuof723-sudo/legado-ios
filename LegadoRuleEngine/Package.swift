// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "LegadoRuleEngine",
    platforms: [.iOS(.v13), .macOS(.v11)],
    products: [
        .library(name: "LegadoRuleEngine", targets: ["LegadoRuleEngine"])
    ],
    dependencies: [
        // CSS 选择器解析依赖 SwiftSoup（jsoup 的 Swift 移植）
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0")
    ],
    targets: [
        .target(
            name: "LegadoRuleEngine",
            dependencies: ["SwiftSoup"]
        ),
        .testTarget(
            name: "LegadoRuleEngineTests",
            dependencies: ["LegadoRuleEngine"]
        )
    ]
)
