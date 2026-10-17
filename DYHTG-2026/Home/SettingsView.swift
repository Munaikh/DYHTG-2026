import SwiftUI

struct SettingsView: View {
    @State private var replay=false
    var body: some View {
        Form {
            Section("Welcome") {
                Button("Replay Onboarding",systemImage:"sparkles") { replay=true }
            }
            Section("Accessibility") {
                Text("Animations respect your device's Reduce Motion setting. Text follows your preferred text size.").foregroundStyle(.secondary)
            }
            Section("Location Privacy") {
                Text("Location is optional. Pathfinder requests access only when you choose to use or share your position. Friend sharing requires both players' consent and expires after ten minutes. Either player can stop it at any time.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .fullScreenCover(isPresented:$replay) { OnboardingView { replay=false } }
    }
}
