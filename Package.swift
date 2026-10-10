// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RealTimeScorecard2",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "LiveScorecard2", targets: ["ScorecardApp"]),
               .executable(name: "ScorecardProbe", targets: ["ScorecardProbe"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "ScorecardCore", dependencies: ["CSQLite"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "ScorecardApp", dependencies: ["ScorecardCore"],
                          resources: [.copy("Resources/default-configuration.json")],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "ScorecardProbe", dependencies: ["ScorecardCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ScorecardCoreTests", dependencies: ["ScorecardCore"], path: "tests/ScorecardCoreTests",
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
