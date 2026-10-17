import AlgorithmArenaProgression
import SwiftUI

// Learning uses the same palette and components as Play and Visualize.
extension Color {
    static let arenaForest = ArenaPalette.teal
    static let arenaAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.45, green: 0.94, blue: 0.76, alpha: 1)
            : UIColor(red: 0, green: 0.43, blue: 0.37, alpha: 1)
    })
    static let arenaMint = ArenaPalette.mint
    static let arenaCanvas = ArenaPalette.canvas
}

struct AdventureCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { content.arenaCard() }
}

struct AdventureButtonStyle: ButtonStyle {
    var secondary = false
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        ArenaActionStyle(prominent: !secondary).makeBody(configuration: configuration)
            .frame(minHeight: large ? 60 : 52)
    }
}

struct LearningXPBar: View {
    let profile: LearningProfile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Level \(profile.level)", systemImage: "bolt.fill")
                    .font(.headline)
                Spacer(minLength: 12)
                Text("\(profile.xp) XP").font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            ProgressView(value: LearningLevels.fraction(for: profile.xp))
                .tint(Color.arenaAccent)
                .animation(reduceMotion || profile.preferences.reduceMotion ? nil : .easeOut(duration: 0.4), value: profile.xp)
            Text("\(max(0, LearningLevels.threshold(for: profile.level + 1) - profile.xp)) XP to level \(profile.level + 1)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(profile.level), \(profile.xp) learning XP")
    }
}

struct AdventureHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AlgorithmBadge: View {
    let algorithm: StudyAlgorithm
    var body: some View {
        Image(systemName: algorithm.symbol)
            .font(.title2.weight(.semibold)).foregroundStyle(ArenaPalette.ink)
            .frame(width: 52, height: 52)
            .background(ArenaPalette.mint, in: .rect(cornerRadius: 16))
            .accessibilityHidden(true)
    }
}

private struct ArenaReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var arenaReduceMotion: Bool {
        get { self[ArenaReduceMotionKey.self] }
        set { self[ArenaReduceMotionKey.self] = newValue }
    }
}
