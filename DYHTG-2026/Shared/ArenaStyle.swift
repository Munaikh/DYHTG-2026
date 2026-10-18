import SwiftUI

enum ArenaPalette {
    static let ink = Color(red: 0.055, green: 0.10, blue: 0.16)
    static let mint = Color(red: 0.45, green: 0.94, blue: 0.76)
    static let teal = Color(red: 0.0, green: 0.43, blue: 0.37)
    static let amber = Color(red: 1.0, green: 0.76, blue: 0.35)
    static let canvas = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
}

/// Shared actions use system glass so focus, presses, disabled state and tint
/// follow the platform. Learning cards and diagrams remain on solid surfaces.
struct ArenaActionStyle: PrimitiveButtonStyle {
    var prominent = true

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                action(configuration)
                    .buttonStyle(.glassProminent)
                    .tint(ArenaPalette.teal)
            } else {
                action(configuration)
                    .buttonStyle(.glass)
            }
        } else {
            Button(role: configuration.role, action: configuration.trigger) {
                configuration.label
            }
            .buttonStyle(ArenaLegacyActionStyle(prominent: prominent))
        }
    }

    private func action(_ configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }
}

/// Utility actions retain their intrinsic width instead of filling a card.
struct ArenaCompactButtonStyle: PrimitiveButtonStyle {
    var prominent = false
    var shape: ButtonBorderShape = .capsule

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                action(configuration).buttonStyle(.glassProminent).tint(ArenaPalette.teal)
            } else {
                action(configuration).buttonStyle(.glass)
            }
        } else if prominent {
            action(configuration).buttonStyle(.borderedProminent).tint(ArenaPalette.teal)
        } else {
            action(configuration).buttonStyle(.bordered)
        }
    }

    private func action(_ configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .buttonBorderShape(shape)
    }
}

/// Group neighboring controls for a single glass rendering context.
struct ArenaGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

private struct ArenaControlDock: ViewModifier {
    func body(content: Content) -> some View {
        // Keep scrolling lesson text from showing through action labels and help text.
        content.background(ArenaPalette.canvas)
    }
}

private struct ArenaLegacyActionStyle: ButtonStyle {
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
    /// A solid dock separates actions and helper text from scrolling content.
    func arenaControlDock() -> some View { modifier(ArenaControlDock()) }

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
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
    }
}
