import AlgorithmArenaCore
import Foundation
import Observation
import SwiftUI

struct LessonProgress: Codable {
    var phase = 0
    var answers: [String: String] = [:]
    var isComplete: Bool { phase >= 4 }
    var hasStarted: Bool { phase > 0 || !answers.isEmpty }
}

@MainActor
@Observable
final class LearnProgressStore {
    private let defaults: UserDefaults
    private let storageKey = "arena.publicLessons.progress.v1"
    private var records: [String: LessonProgress]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: LessonProgress].self, from: data) {
            records = decoded.mapValues { record in
                var safe = record
                safe.phase = min(max(record.phase, 0), 4)
                return safe
            }
        } else {
            records = [:]
        }
    }

    func progress(for algorithm: AlgorithmKind) -> LessonProgress {
        records[algorithm.rawValue] ?? LessonProgress()
    }

    func answer(_ optionID: String, questionID: String, algorithm: AlgorithmKind) {
        var progress = progress(for: algorithm)
        guard progress.answers[questionID] == nil else { return }
        progress.answers[questionID] = optionID
        records[algorithm.rawValue] = progress
        save()
    }

    func advance(_ algorithm: AlgorithmKind) {
        var progress = progress(for: algorithm)
        progress.phase = min(progress.phase + 1, 4)
        records[algorithm.rawValue] = progress
        save()
    }

    func restart(_ algorithm: AlgorithmKind) {
        records[algorithm.rawValue] = LessonProgress()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

/// Feature-local styling keeps the offline lessons independent of room state.
enum LearnStyle {
    static let ink = ArenaPalette.ink
    static let mint = ArenaPalette.mint
    static let teal = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.45, green: 0.94, blue: 0.76, alpha: 1)
            : UIColor(red: 0, green: 0.43, blue: 0.37, alpha: 1)
    })
}

struct LearnCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

extension View {
    func learnCard() -> some View { modifier(LearnCard()) }
}
