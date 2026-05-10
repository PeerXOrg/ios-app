// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PeerXCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "PeerXCore", targets: ["PeerXCore"]),
    ],
    dependencies: [
        // CMS.sign API is gated behind @_spi(CMS) — pin to upToNextMinor so a
        // patch bump can't drag in API breakage.
        .package(url: "https://github.com/apple/swift-certificates", .upToNextMinor(from: "1.18.0")),
        .package(url: "https://github.com/apple/swift-crypto",       from: "3.8.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation",   from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "PeerXCore",
            dependencies: [
                .product(name: "X509",          package: "swift-certificates"),
                .product(name: "Crypto",        package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            exclude: [
                "Resources/certs/.gitkeep",
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
