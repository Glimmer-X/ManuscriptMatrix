// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ManuscriptKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ManuscriptDomain", targets: ["ManuscriptDomain"]),
        .library(name: "ManuscriptApplication", targets: ["ManuscriptApplication"]),
        .library(name: "ManuscriptInfrastructure", targets: ["ManuscriptInfrastructure"]),
        .library(name: "ManuscriptDesignSystem", targets: ["ManuscriptDesignSystem"]),
        .library(name: "MatrixFeature", targets: ["MatrixFeature"]),
        .executable(name: "manuscript-matrix-agent", targets: ["ManuscriptAgentBridge"])
    ],
    targets: [
        .target(name: "ManuscriptDomain"),
        .target(
            name: "ManuscriptApplication",
            dependencies: ["ManuscriptDomain"]
        ),
        .target(
            name: "ManuscriptInfrastructure",
            dependencies: ["ManuscriptDomain", "ManuscriptApplication"]
        ),
        .target(name: "ManuscriptDesignSystem"),
        .target(
            name: "MatrixFeature",
            dependencies: [
                "ManuscriptDomain",
                "ManuscriptApplication",
                "ManuscriptDesignSystem"
            ]
        ),
        .executableTarget(
            name: "ManuscriptAgentBridge",
            dependencies: [
                "ManuscriptDomain",
                "ManuscriptApplication",
                "ManuscriptInfrastructure"
            ]
        ),
        .testTarget(
            name: "ManuscriptDomainTests",
            dependencies: ["ManuscriptDomain"]
        ),
        .testTarget(
            name: "ManuscriptApplicationTests",
            dependencies: ["ManuscriptApplication", "ManuscriptInfrastructure"]
        )
    ]
)
