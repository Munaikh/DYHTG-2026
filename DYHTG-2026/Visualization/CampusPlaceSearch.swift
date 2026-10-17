import AlgorithmArenaCore
import Foundation
import MapKit
import Observation

@MainActor @Observable
final class CampusPlaceSearch {
    private(set) var results: [CampusMapPoint] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let provider: (String) async throws -> [CampusMapPoint]
    @ObservationIgnored private let cancelProvider: () -> Void

    init() {
        let search = CampusApplePlaceSearch()
        provider = { try await search.places(matching: $0) }
        cancelProvider = { search.cancel() }
    }

    init(provider: @escaping (String) async throws -> [CampusMapPoint], cancel: @escaping () -> Void = {}) {
        self.provider = provider
        cancelProvider = cancel
    }

    func cancel() {
        generation = UUID()
        cancelProvider()
        isSearching = false
        results = []
        errorMessage = nil
    }

    /// Debouncing begins in the loading state so old results never remain tappable.
    /// Generation checks
    /// prevent an older response or cancellation from replacing the latest query.
    func search(_ query: String, debounce: Duration = .zero) async {
        cancel()
        let token = generation
        results = []
        errorMessage = nil
        let query = Self.normalizedQuery(query)
        guard query.count >= 2 else { return }
        isSearching = true
        defer { if generation == token { isSearching = false } }
        do {
            if debounce > .zero { try await Task.sleep(for: debounce) }
            guard generation == token, !Task.isCancelled else { return }
            let matches = try await provider(query)
            guard generation == token, !Task.isCancelled else { return }
            results = Self.canonicalResults(matches)
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            errorMessage = (error as? URLError)?.code == .timedOut
                ? "Apple Maps is taking too long. Try the search again."
                : "Apple Maps search is unavailable. Check your connection and try again."
        }
    }

    static func normalizedQuery(_ query: String) -> String {
        let cleaned = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        switch cleaned.lowercased() {
        case "jms", "jms hub", "jms learning hub", "james mccune smith":
            return "James McCune Smith Learning Hub"
        default:
            return cleaned
        }
    }

    /// Pure matching rules shared by production results and deterministic tests.
    /// Live coordinates are retained even when a known place acquires its stable ID.
    static func canonicalResults(_ candidates: [CampusMapPoint]) -> [CampusMapPoint] {
        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            guard CampusMapPoint.contains(candidate.coordinate) else { return nil }
            let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let normalizedName = nameKey(name)
            let known = CampusMapPoint.landmarks.compactMap { landmark -> (CampusMapPoint, Double)? in
                guard let distance = try? CourseGeometry.distance(from: candidate.coordinate, to: landmark.coordinate),
                      distance <= 60 else { return nil }
                let names = [landmark.name] + aliases[landmark.id, default: []]
                guard names.contains(where: { nameKey($0) == normalizedName }) else { return nil }
                return (landmark, distance)
            }.min { first, second in
                first.1 == second.1 ? first.0.id < second.0.id : first.1 < second.1
            }?.0
            let id = known?.id ?? stableID(name: name, coordinate: candidate.coordinate)
            guard seen.insert(id).inserted else { return nil }
            return CampusMapPoint(id: id, name: known?.name ?? name, coordinate: candidate.coordinate,
                address: candidate.address ?? known?.address, isAppleMapsPlace: candidate.isAppleMapsPlace)
        }
    }

    private static let aliases: [String: [String]] = [
        "01-jms": ["JMS Learning Hub", "JMS", "James McCune Smith"],
        "02-lilybank-gardens": ["Sir Alwyn Williams", "Sir Alwyn Williams Building - University of Glasgow"],
        "03-lilybank-house": ["Lilybank House - University of Glasgow"],
        "04-hetherington": ["Hetherington"],
        "05-rejoin": ["40 Bute Gardens"],
        "06-fraser": ["Fraser Building - University of Glasgow"],
        "07-library": ["University of Glasgow", "University of Glasgow Library", "Glasgow University Library"],
        "08-main-building": ["Main Building", "University of Glasgow Main Building"],
        "09-university-gardens": ["1 University Gardens", "University Gardens 1"],
    ]

    private static func nameKey(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_GB"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func stableID(name: String, coordinate: Coordinate) -> String {
        // Quantization avoids unstable floating-point formatting and UUIDs. The
        // returned coordinate itself remains untouched for MapKit directions.
        let latitude = Int((coordinate.latitude * 1_000_000).rounded())
        let longitude = Int((coordinate.longitude * 1_000_000).rounded())
        let slug = nameKey(name).replacingOccurrences(of: " ", with: "-")
        return "apple-place-\(slug)-\(latitude)-\(longitude)"
    }
}

@MainActor
private final class CampusApplePlaceSearch {
    private var current: MKLocalSearch?
    private var requestID = UUID()

    func cancel() { current?.cancel(); current = nil }

    func places(matching query: String) async throws -> [CampusMapPoint] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 55.873, longitude: -4.2905),
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.017))
        let search = MKLocalSearch(request: request)
        let token = UUID()
        requestID = token
        current = search
        var timedOut = false
        let watchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            guard self?.requestID == token else { return }
            timedOut = true
            self?.cancel()
        }
        defer {
            watchdog.cancel()
            if current === search { current = nil }
        }
        let response: MKLocalSearch.Response
        do {
            response = try await withTaskCancellationHandler {
                try await search.start()
            } onCancel: {
                Task { @MainActor [weak self] in
                    if self?.requestID == token { self?.cancel() }
                }
            }
        } catch {
            if timedOut { throw URLError(.timedOut) }
            throw error
        }
        try Task.checkCancellation()
        // Do not require pointOfInterestCategory: Apple returns valid campus
        // departments and buildings with a nil category.
        return response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            let coordinate: CLLocationCoordinate2D
            let address: String?
            #if compiler(>=6.2)
            if #available(iOS 26.0, macOS 26.0, *) {
                coordinate = item.location.coordinate
                address = item.address?.fullAddress
            } else {
                coordinate = item.placemark.coordinate
                address = item.placemark.title
            }
            #else
            coordinate = item.placemark.coordinate
            address = item.placemark.title
            #endif
            return CampusMapPoint(id: "unmatched", name: name,
                coordinate: .init(latitude: coordinate.latitude, longitude: coordinate.longitude),
                address: address, isAppleMapsPlace: true)
        }
    }
}
