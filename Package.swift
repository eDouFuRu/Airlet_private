// swift-tools-version: 5.9
import PackageDescription

// The former NotchIslandCore target (components/Island/Core) belonged to the retired
// sweet-potato timer and is gone; the pure-logic core now lives in NotchInteractionCore.
let package = Package(
    name: "NotchIslandPackages",
    platforms: [.macOS(.v14)],
    products: [.library(name: "NotchInteractionCore", targets: ["NotchInteractionCore"])],
    targets: [
        .target(name: "NotchInteractionCore", path: "boringNotch/Interaction/Core"),
        .testTarget(name: "NotchInteractionTests", dependencies: ["NotchInteractionCore"], path: "Tests/NotchInteractionTests")
    ],
    swiftLanguageVersions: [.v5]
)
