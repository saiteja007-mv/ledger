// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Ledger",
    // The only device runs iOS 27.0; 26.0 is the floor for Liquid Glass and the iOS 26 tab bar APIs.
    platforms: [.iOS("26.0")],
    products: [
        // xtool's planner only accepts automatic library products: never add `type:`.
        .library(name: "Ledger", targets: ["Ledger"]),
        // The widget extension: its own bundle, so its own library product (and one App ID).
        .library(name: "LedgerWidgets", targets: ["LedgerWidgets"]),
    ],
    targets: [
        // Resources/Fonts holds the kit's Poppins; KitFont.register() loads it from Bundle.module at launch.
        .target(name: "Ledger", resources: [.process("Resources")]),
        // Self-contained: its own thin API client and models, no dependency on the app target.
        .target(name: "LedgerWidgets"),
    ]
)
