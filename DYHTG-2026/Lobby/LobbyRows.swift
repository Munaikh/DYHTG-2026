import AlgorithmArenaCore
import SwiftUI

struct RoomCodeRow: View {
    let code: String

    var body: some View {
        Text(code)
            .font(.largeTitle.weight(.bold))
            .kerning(2)
            .textSelection(.enabled)
            .padding(.vertical, 4)
            .accessibilityLabel("Room code")
            .accessibilityValue(code.map(String.init).joined(separator: " "))
    }
}

struct PlayerRow: View {
    let player: PlayerProgress
    let isViewer: Bool
    let isHost: Bool
    let start: NodeID

    private var status: String {
        if !player.hasArrived(at: start) { return "Needs to check in" }
        return player.ready ? "Ready" : "Checked in"
    }

    private var roles: [String] {
        (isHost ? ["Host"] : []) + (isViewer ? ["You"] : [])
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.nickname)
                Text((roles + [status]).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if player.connection == .disconnected {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.secondary)
            } else if player.ready {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .animation(.default, value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([player.nickname] + roles).joined(separator: ", "))
        .accessibilityValue(player.connection == .disconnected ? "Disconnected" : status)
    }
}

struct ReconnectingRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Reconnecting. Your progress is saved.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
    }
}
