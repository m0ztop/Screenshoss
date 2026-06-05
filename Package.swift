// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Shoss",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Shoss",
            path: "Sources/ShossApp",
            linkerSettings: [
                .linkedFramework("QuickLookUI"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .testTarget(
            name: "ShossTests",
            dependencies: ["Shoss"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
