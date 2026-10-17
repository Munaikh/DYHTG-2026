import SwiftUI

/// Wrap the semantic button action so touch, VoiceOver and keyboard activation agree.
struct ArenaFeedbackButtonStyle: PrimitiveButtonStyle {
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    Button(role: configuration.role) {
      guard enabled else { return }
      ArenaSoundPlayer.shared.play(.tap)
      configuration.trigger()
    } label: {
      configuration.label
    }
    .buttonStyle(ArenaPressButtonStyle())
  }
}

struct ArenaPressButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.arenaReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.82 : 1)
      .scaleEffect(configuration.isPressed && !systemReduceMotion && !reduceMotion ? 0.98 : 1)
      .animation(
        systemReduceMotion || reduceMotion ? nil : .spring(duration: 0.18),
        value: configuration.isPressed)
  }
}
