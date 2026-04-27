// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenLess",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "OpenLess", targets: ["OpenLessApp"]),
        .library(name: "OpenLessCore", targets: ["OpenLessCore"]),
        .library(name: "OpenLessHotkey", targets: ["OpenLessHotkey"]),
        .library(name: "OpenLessUI", targets: ["OpenLessUI"]),
        .library(name: "OpenLessRecorder", targets: ["OpenLessRecorder"]),
        .library(name: "OpenLessASR", targets: ["OpenLessASR"]),
        .library(name: "OpenLessPolish", targets: ["OpenLessPolish"]),
        .library(name: "OpenLessInsertion", targets: ["OpenLessInsertion"]),
        .library(name: "OpenLessPersistence", targets: ["OpenLessPersistence"]),
    ],
    targets: [
        .target(name: "OpenLessCore", path: "Sources/OpenLessCore"),
        .target(
            name: "OpenLessHotkey",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessHotkey"
        ),
        .target(
            name: "OpenLessUI",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessUI"
        ),
        .target(
            name: "OpenLessRecorder",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessRecorder"
        ),
        .target(
            name: "OpenLessASR",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessASR"
        ),
        .target(
            name: "OpenLessPolish",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessPolish"
        ),
        .target(
            name: "OpenLessInsertion",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessInsertion"
        ),
        .target(
            name: "OpenLessPersistence",
            dependencies: ["OpenLessCore"],
            path: "Sources/OpenLessPersistence"
        ),
        .executableTarget(
            name: "OpenLessApp",
            dependencies: [
                "OpenLessCore",
                "OpenLessHotkey",
                "OpenLessUI",
                "OpenLessRecorder",
                "OpenLessASR",
                "OpenLessPolish",
                "OpenLessInsertion",
                "OpenLessPersistence",
            ],
            path: "Sources/OpenLessApp"
        ),
        .testTarget(
            name: "OpenLessCoreTests",
            dependencies: ["OpenLessCore"],
            path: "Tests/OpenLessCoreTests"
        ),
        .testTarget(
            name: "OpenLessPolishTests",
            dependencies: ["OpenLessPolish"],
            path: "Tests/OpenLessPolishTests"
        ),
    ],
    // 暂留 Swift 5 语言模式，避免一次性吞掉 Swift 6 严格并发的全部改造。
    // 升 .v6 时需要重新审视 Recorder / VolcengineStreamingASR 等 @unchecked Sendable 类。
    swiftLanguageModes: [.v5]
)
