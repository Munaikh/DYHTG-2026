import AlgorithmArenaCore
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    enum Failure: Error, Equatable {
        case denied
        case unavailable
    }

    private(set) var latest: CLLocation?
    private(set) var authorization: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var authorizationRequest: CheckedContinuation<CLAuthorizationStatus, Never>?
    @ObservationIgnored private var fixRequest: CheckedContinuation<CLLocation, any Error>?
    @ObservationIgnored private var isUpdating = false

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func startUpdating() async {
        guard await authorize() else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        isUpdating = false
        manager.stopUpdatingLocation()
    }

    func currentFix(maximumAge: TimeInterval = 5) async throws -> LocationFix {
        if let latest, -latest.timestamp.timeIntervalSinceNow <= maximumAge, latest.horizontalAccuracy >= 0 {
            return LocationFix(location: latest)
        }
        guard fixRequest == nil else { throw Failure.unavailable }
        guard await authorize() else { throw Failure.denied }
        let location = try await withCheckedThrowingContinuation { continuation in
            fixRequest = continuation
            if !isUpdating { manager.requestLocation() }
            Task {
                try? await Task.sleep(for: .seconds(6))
                expireFixRequest()
            }
        }
        return LocationFix(location: location)
    }

    private func expireFixRequest() {
        guard let fixRequest else { return }
        self.fixRequest = nil
        if let latest {
            fixRequest.resume(returning: latest)
        } else {
            fixRequest.resume(throwing: Failure.unavailable)
        }
    }

    func distance(to coordinate: Coordinate) -> CLLocationDistance? {
        latest?.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    private func authorize() async -> Bool {
        if manager.authorizationStatus == .notDetermined {
            authorization = await withCheckedContinuation { continuation in
                authorizationRequest = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        return manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            guard status != .notDetermined, let authorizationRequest else { return }
            self.authorizationRequest = nil
            authorizationRequest.resume(returning: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            latest = location
            fixRequest?.resume(returning: location)
            fixRequest = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated {
            fixRequest?.resume(throwing: denied ? Failure.denied : Failure.unavailable)
            fixRequest = nil
        }
    }
}

private extension LocationFix {
    init(location: CLLocation) {
        self.init(
            coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            capturedAt: location.timestamp,
            horizontalAccuracyMetres: location.horizontalAccuracy
        )
    }
}
