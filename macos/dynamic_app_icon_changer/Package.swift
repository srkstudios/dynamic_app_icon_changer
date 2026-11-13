// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dynamic_app_icon_changer",
    platforms: [
        .macOS(.v10_14)
    ],
    products: [
        .library(name: "dynamic-app-icon-changer", targets: ["dynamic_app_icon_changer"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "dynamic_app_icon_changer",
            dependencies: [],
            path: "../Classes"
        )
    ]
)
