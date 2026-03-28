// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Deskfloor",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../nlp-engine"),
    ],
    targets: [
        .executableTarget(
            name: "Deskfloor",
            dependencies: [
                .product(name: "NLPEngine", package: "nlp-engine"),
            ],
            path: "Sources/Deskfloor"
        )
    ]
)
