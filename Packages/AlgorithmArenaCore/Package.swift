// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AlgorithmArenaCore",
  platforms: [.iOS(.v17), .macOS(.v13)],
  products: [
    .library(name: "AlgorithmArenaCore", targets: ["AlgorithmArenaCore"]),
    .library(name: "AlgorithmArenaFixtures", targets: ["AlgorithmArenaFixtures"]),
    .executable(name: "export-contract-fixtures", targets: ["ExportContractFixtures"]),
  ],
  targets: [
    .target(name: "AlgorithmArenaCore"),
    .target(name: "AlgorithmArenaFixtures", dependencies: ["AlgorithmArenaCore"]),
    .executableTarget(name: "ExportContractFixtures", dependencies: ["AlgorithmArenaFixtures"]),
    .testTarget(
      name: "AlgorithmArenaCoreTests",
      dependencies: ["AlgorithmArenaCore", "AlgorithmArenaFixtures"]),
  ]
)
