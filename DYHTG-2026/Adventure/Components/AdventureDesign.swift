import AlgorithmArenaProgression
import SwiftUI

extension Color {
  static let arenaForest = Color(red: 0.10, green: 0.29, blue: 0.21)
  static let arenaAccent = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.70, green: 0.89, blue: 0.61, alpha: 1)
        : UIColor(red: 0.10, green: 0.29, blue: 0.21, alpha: 1)
    })
  static let arenaMint = Color(red: 0.80, green: 0.92, blue: 0.65)
  static let arenaCanvas = Color(uiColor: .systemGroupedBackground)
}
struct AdventureCard<Content: View>: View {
  @ViewBuilder let content: Content
  var body: some View {
    content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
  }
}
struct AdventureButtonStyle: ButtonStyle {
  var secondary = false
  var large = false
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: large ? 60 : 50)
      .padding(.horizontal, 16)
      .foregroundStyle(secondary ? Color.primary : Color.white)
      .background(
        secondary
          ? Color(uiColor: .tertiarySystemGroupedBackground)
          : enabled ? Color.arenaForest : Color.gray, in: RoundedRectangle(cornerRadius: 15)
      )
      .opacity(configuration.isPressed ? 0.82 : enabled ? 1 : 0.45)
      .contentShape(RoundedRectangle(cornerRadius: 15))
  }
}
struct LearningXPBar: View {
  let profile: LearningProfile
  @Environment(\.dynamicTypeSize) private var textSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      if textSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 8) {
          Label("Level \(profile.level)", systemImage: "leaf.fill").font(.headline)
          Text("\(profile.xp) XP").font(.subheadline).monospacedDigit()
        }
      } else {
        HStack {
          Label("Level \(profile.level)", systemImage: "leaf.fill").font(.headline)
          Spacer(minLength: 12)
          Text("\(profile.xp) XP").font(.subheadline).monospacedDigit()
        }
      }
      ProgressView(value: LearningLevels.fraction(for: profile.xp))
        .tint(Color.arenaAccent).scaleEffect(x: 1, y: 1.5)
        .animation(
          reduceMotion || profile.preferences.reduceMotion ? nil : .easeInOut(duration: 0.5),
          value: profile.xp)
      Text(
        "\(max(0,LearningLevels.threshold(for: profile.level+1)-profile.xp)) XP to level \(profile.level+1)"
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Level \(profile.level), \(profile.xp) learning XP, \(max(0,LearningLevels.threshold(for: profile.level+1)-profile.xp)) XP to the next level"
    )
  }
}
struct AdventureHeading: View {
  let title: String
  let subtitle: String
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.largeTitle.bold())
      Text(subtitle).font(.body).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct AlgorithmBadge: View {
  let algorithm: StudyAlgorithm
  var body: some View {
    Image(systemName: algorithm.symbol).font(.title2).foregroundStyle(Color.arenaForest)
      .frame(width: 52, height: 52).background(
        Color.arenaMint.opacity(0.5), in: RoundedRectangle(cornerRadius: 15)
      )
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
