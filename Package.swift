// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "snake",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Snake", targets: ["Snake"])
    ],
    targets: [
        .executableTarget(
            name: "Snake",
            dependencies: ["CSDL3"],
            resources: [
                .embedInCode("Resources/Textures/body.bmp"),
                .embedInCode("Resources/Textures/food.bmp"),
                .embedInCode("Resources/Textures/head.bmp"),
            ]),
        .systemLibrary(
            name: "CSDL3",
            pkgConfig: "sdl3",
            providers: [
                .brew(["sdl3"])
            ]),
    ]
)
