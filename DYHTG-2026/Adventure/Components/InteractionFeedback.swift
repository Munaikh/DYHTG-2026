import SwiftUI

/// A quiet press response for cards, links and secondary learning controls.
struct ArenaFeedbackButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.arenaReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !systemReduceMotion && !reduceMotion ? 0.98 : 1)
            .animation(systemReduceMotion || reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
