import SwiftUI

enum ArenaPalette {
    static let ink = Color(red: 0.055, green: 0.10, blue: 0.16)
    static let mint = Color(red: 0.45, green: 0.94, blue: 0.76)
    static let teal = Color(red: 0.0, green: 0.43, blue: 0.37)
    static let amber = Color(red: 1.0, green: 0.76, blue: 0.35)
    static let canvas = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
}

struct ArenaActionStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(prominent ? ArenaPalette.ink : Color.primary)
            .background(prominent ? ArenaPalette.mint : ArenaPalette.surface, in: .rect(cornerRadius: 18))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

extension View {
    func arenaCard() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ArenaPalette.surface, in: .rect(cornerRadius: 24))
    }
}

struct ArenaEyebrow: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.6)
            .foregroundStyle(color)
    }
}
