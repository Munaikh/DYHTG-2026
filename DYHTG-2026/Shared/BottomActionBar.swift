import SwiftUI

private struct BottomActionBar<Actions: View>: ViewModifier {
    @ViewBuilder var actions: Actions

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.safeAreaBar(edge: .bottom) {
                stack
            }
        } else {
            content.safeAreaInset(edge: .bottom) {
                stack
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
            }
        }
    }

    private var stack: some View {
        VStack(spacing: 12) {
            actions
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }
}

extension View {
    func bottomActions<Actions: View>(@ViewBuilder _ actions: () -> Actions) -> some View {
        modifier(BottomActionBar(actions: actions))
    }
}
