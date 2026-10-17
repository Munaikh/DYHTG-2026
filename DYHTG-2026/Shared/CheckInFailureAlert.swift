import SwiftUI

extension View {
    func checkInFailureAlert(_ failure: Binding<LocationProvider.Failure?>, retry: @escaping () -> Void) -> some View {
        alert(
            "Can't Check In",
            isPresented: Binding(
                get: { failure.wrappedValue != nil },
                set: { if !$0 { failure.wrappedValue = nil } }
            ),
            presenting: failure.wrappedValue
        ) { presented in
            if presented == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                Button("Try Again", action: retry)
            }
            Button("Cancel", role: .cancel) {}
        } message: { presented in
            switch presented {
            case .denied:
                Text("Location access is off for Arena. Allow it in Settings, or ask an organiser to check you in.")
            case .unavailable:
                Text("Your location isn't available yet. Move into the open and try again.")
            }
        }
    }
}
