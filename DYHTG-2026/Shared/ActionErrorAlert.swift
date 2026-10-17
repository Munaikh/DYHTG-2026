import SwiftUI

extension View {
    func actionErrorAlert(
        _ error: Binding<ActionError?>,
        retry: @escaping () -> Void = {},
        cancel: @escaping () -> Void = {}
    ) -> some View {
        alert(
            error.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            ),
            presenting: error.wrappedValue
        ) { presented in
            if presented.canRetry {
                Button("Try Again", action: retry)
                Button("Cancel", role: .cancel, action: cancel)
            } else {
                Button("OK", role: .cancel, action: cancel)
            }
        } message: { presented in
            Text(presented.message)
        }
    }
}
