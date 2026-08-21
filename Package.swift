// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "whitelimo",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "whitelimo", targets: ["whitelimo"]),
        .library(name: "RemoKit", targets: ["RemoKit"]),
        .library(name: "MenuKit", targets: ["MenuKit"]),
    ],
    targets: [
        // A small client for the Nature Remo Cloud API.
        .target(name: "RemoKit"),
        // Turns appliances into the menu tree, and runs what the user picks.
        .target(name: "MenuKit", dependencies: ["RemoKit"]),
        // Persisted state: the access token and the cached menu.
        .target(name: "WhiteLimoCore", dependencies: ["RemoKit", "MenuKit"]),
        // The menu bar application itself. Everything AppKit lives here.
        .executableTarget(name: "whitelimo", dependencies: ["RemoKit", "MenuKit", "WhiteLimoCore"]),

        .testTarget(name: "RemoKitTests", dependencies: ["RemoKit"]),
        .testTarget(name: "MenuKitTests", dependencies: ["MenuKit", "RemoKit"]),
        .testTarget(name: "WhiteLimoCoreTests", dependencies: ["WhiteLimoCore", "MenuKit"]),
    ]
)
