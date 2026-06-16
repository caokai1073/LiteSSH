// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LiteSSH",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LiteSSH", targets: ["LiteSSH"])
    ],
    dependencies: [
        // 终端模拟控件（渲染 ANSI/VT100，支持 vim/top/颜色等）。
        // 如果这个依赖解析失败或 API 报错，去 https://github.com/migueldeicaza/SwiftTerm
        // 查看当前版本的用法，主要受影响的文件是 Sources/LiteSSH/Views/Terminal/TerminalContainerView.swift
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "LiteSSH",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/LiteSSH"
        )
    ]
)
