import AlgorithmArenaFixtures
import Foundation

guard CommandLine.arguments.count == 2 else {
  throw ExportError.usage
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let documents = try FixtureCatalog.documents()
for path in documents.keys.sorted() {
  let url = root.appendingPathComponent(path)
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try documents[path]!.write(to: url, options: .atomic)
}
print("Exported \(documents.count) synthetic contract fixtures to \(root.path)")

enum ExportError: Error {
  case usage  // Usage: swift run export-contract-fixtures <output-directory>
}
