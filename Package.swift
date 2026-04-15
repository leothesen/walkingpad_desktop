// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "walkingpad-client",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "walkingpad_client", targets: ["walkingpad_client"])
    ],
    dependencies: [
        .package(url: "https://github.com/envoy/Embassy.git", from: "4.1.6"),
        .package(url: "https://github.com/sroebert/mqtt-nio.git", from: "2.8.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.1")
    ],
    targets: [
        .target(
            name: "walkingpad_client",
            dependencies: [
                "Embassy",
                .product(name: "MQTTNIO", package: "mqtt-nio"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "walkingpad-client",
            exclude: [
                "Info.plist", 
                "walkingpad_client.entitlements", 
                "walkingpad_clientApp.swift", 
                "Assets.xcassets", 
                "Preview Content", 
                "views",
                "viewmodels/StatsOverlayViewModel.swift",
                "services/StatsOverlayController.swift",
                "services/GlobalHotkeyService.swift"
            ]
        ),
        .testTarget(
            name: "WalkingPadTests",
            dependencies: ["walkingpad_client"],
            path: "walkingpad-clientTests"
        )
    ]
)
