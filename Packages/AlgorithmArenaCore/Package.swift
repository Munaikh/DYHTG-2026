// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AlgorithmArenaCore",
  platforms: [.iOS(.v17), .macOS(.v13)],
  products: [
    .library(name: "AlgorithmArenaProgression", targets: ["AlgorithmArenaProgression"]),
    .library(name: "AlgorithmArenaCore", targets: ["AlgorithmArenaCore"]),
    .library(name: "AlgorithmArenaFixtures", targets: ["AlgorithmArenaFixtures"]),
    // Authoring/server tooling only: never link this answer bank into the app.
    .library(name: "AlgorithmArenaLearning", targets: ["AlgorithmArenaLearning"]),
    .executable(name: "export-contract-fixtures", targets: ["ExportContractFixtures"]),
    .executable(name: "export-learning-content", targets: ["ExportLearningContent"]),
  ],
  targets: [
    .target(name: "AlgorithmArenaProgression", dependencies: ["AlgorithmArenaCore"]),
    .testTarget(name: "AlgorithmArenaProgressionTests", dependencies: ["AlgorithmArenaProgression", "AlgorithmArenaCore", "AlgorithmArenaFixtures"]),
    .target(name: "AlgorithmArenaCore"),
    .target(name: "AlgorithmArenaFixtures", dependencies: ["AlgorithmArenaCore"]),
    .target(name: "AlgorithmArenaLearning", dependencies: ["AlgorithmArenaCore"]),
    .executableTarget(name: "ExportContractFixtures", dependencies: ["AlgorithmArenaFixtures"]),
    .executableTarget(name: "ExportLearningContent", dependencies: ["AlgorithmArenaLearning"]),
    .testTarget(
      name: "AlgorithmArenaCoreTests",
      dependencies: ["AlgorithmArenaCore", "AlgorithmArenaFixtures"]),
    .testTarget(
      name: "AlgorithmArenaLearningTests",
      dependencies: ["AlgorithmArenaCore", "AlgorithmArenaLearning"]),
  ]
)
