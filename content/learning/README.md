# Learning bank

Versioned authored content for issue #5. See [the API, answers, privacy boundary
and verification](../../docs/LEARNING.md).

`v1/prompts/` contains client-safe questions, served individually after unlock.
`v1/server/` contains **private keys and full replays** for server import and
development verification. Never distribute that directory, or the
`AlgorithmArenaLearning` product, in a production client or public storage.

Regenerate both with `swift run --package-path Packages/AlgorithmArenaCore
export-learning-content "$PWD/content/learning/v1"`. Tests reject export drift.
