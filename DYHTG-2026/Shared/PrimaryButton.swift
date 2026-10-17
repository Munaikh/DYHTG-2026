import SwiftUI

struct PrimaryButton: View {
    let title: String
    var busyTitle: String?
    var isBusy = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            guard !isBusy else { return }
            action()
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                }
                Text(isBusy ? busyTitle ?? title : title)
            }
            .foregroundStyle(isEnabled ? Color.white : Color(.tertiaryLabel))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.primaryFill)
    }
}
