import AlgorithmArenaCore
import Foundation

struct CampusMapPoint: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let coordinate: Coordinate
    let address: String?
    let isAppleMapsPlace: Bool

    init(id: String, name: String, coordinate: Coordinate, address: String? = nil, isAppleMapsPlace: Bool = false) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.address = address
        self.isAppleMapsPlace = isAppleMapsPlace
    }

    // Apple Maps MKLocalSearch POIs verified live on 2026-10-17. These are place
    // coordinates, not fabricated entrances; MKDirections resolves walking access.
    // IDs are retained so saved selections and existing network topology stay valid.
    static let landmarks: [CampusMapPoint] = [
        .init(id: "01-jms", name: "James McCune Smith Learning Hub", coordinate: .init(latitude: 55.8732963, longitude: -4.2920002), address: "110 University Avenue, Glasgow G12 8QW", isAppleMapsPlace: true),
        .init(id: "02-lilybank-gardens", name: "Sir Alwyn Williams Building", coordinate: .init(latitude: 55.8739399, longitude: -4.2918551), address: "1 Lilybank Gardens Lane", isAppleMapsPlace: true),
        .init(id: "03-lilybank-house", name: "Lilybank House", coordinate: .init(latitude: 55.8740461, longitude: -4.2904141), address: "5 Lilybank Terrace", isAppleMapsPlace: true),
        .init(id: "04-hetherington", name: "Hetherington Building", coordinate: .init(latitude: 55.8742082, longitude: -4.2887832), address: "Bute Gardens", isAppleMapsPlace: true),
        .init(id: "05-rejoin", name: "42 Bute Gardens", coordinate: .init(latitude: 55.873766, longitude: -4.2899032), address: "40 Bute Gardens", isAppleMapsPlace: true),
        .init(id: "06-fraser", name: "Fraser Building", coordinate: .init(latitude: 55.873159, longitude: -4.2879188), address: "65 Hillhead Street", isAppleMapsPlace: true),
        .init(id: "07-library", name: "University Library", coordinate: .init(latitude: 55.873486, longitude: -4.288859), address: "Hillhead Street", isAppleMapsPlace: true),
        .init(id: "08-main-building", name: "Main Building - University of Glasgow", coordinate: .init(latitude: 55.8717463, longitude: -4.2883454), address: "Glasgow G12 8QQ", isAppleMapsPlace: true),
        .init(id: "09-university-gardens", name: "University Gardens, 1", coordinate: .init(latitude: 55.872638, longitude: -4.2894), address: "1 University Gardens", isAppleMapsPlace: true),
    ]

    static let start = landmarks[0]
    static let defaultDestination = landmarks[6]

    /// Gilmorehill and its immediate pedestrian approaches. No location access is requested.
    static func contains(_ coordinate: Coordinate) -> Bool {
        (55.8690...55.8770).contains(coordinate.latitude)
            && (-4.2990 ... -4.2820).contains(coordinate.longitude)
    }
}
