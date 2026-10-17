import AlgorithmArenaCore
import CoreLocation

@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    enum Failure: Error, Equatable {
        case denied
        case unavailable
    }

    private let manager = CLLocationManager()
    private var authorization: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var request: CheckedContinuation<CLLocation, any Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func currentFix() async throws -> LocationFix {
        guard request == nil else { throw Failure.unavailable }
        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                authorization = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw Failure.denied
        }
        let location = try await withCheckedThrowingContinuation { continuation in
            request = continuation
            manager.requestLocation()
        }
        return LocationFix(
            coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            capturedAt: location.timestamp,
            horizontalAccuracyMetres: location.horizontalAccuracy
        )
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard status != .notDetermined, let authorization else { return }
            self.authorization = nil
            authorization.resume(returning: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            request?.resume(returning: location)
            request = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated {
            request?.resume(throwing: denied ? Failure.denied : Failure.unavailable)
            request = nil
        }
    }
}
