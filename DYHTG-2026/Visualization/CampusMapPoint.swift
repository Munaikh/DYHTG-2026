import AlgorithmArenaCore
import Foundation

struct CampusMapPoint: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let coordinate: Coordinate

    static let landmarks: [CampusMapPoint] = [
        .init(id: "01-jms", name: "JMS Learning Hub", coordinate: .init(latitude: 55.87312, longitude: -4.29370)),
        .init(id: "02-lilybank-gardens", name: "Lilybank Gardens", coordinate: .init(latitude: 55.87425, longitude: -4.29275)),
        .init(id: "03-lilybank-house", name: "Lilybank House", coordinate: .init(latitude: 55.87468, longitude: -4.29145)),
        .init(id: "04-hetherington", name: "Hetherington", coordinate: .init(latitude: 55.87415, longitude: -4.29045)),
        .init(id: "05-rejoin", name: "Bute Gardens", coordinate: .init(latitude: 55.87375, longitude: -4.29020)),
        .init(id: "06-fraser", name: "Fraser Building", coordinate: .init(latitude: 55.87312, longitude: -4.28955)),
        .init(id: "07-library", name: "University Library", coordinate: .init(latitude: 55.87360, longitude: -4.28875)),
        .init(id: "08-main-building", name: "Main Building", coordinate: .init(latitude: 55.87188, longitude: -4.28877)),
        .init(id: "09-university-gardens", name: "University Gardens", coordinate: .init(latitude: 55.87200, longitude: -4.29220)),
    ]

    static let start = landmarks[0]
    static let defaultDestination = landmarks[6]

    /// Gilmorehill and its immediate pedestrian approaches. No location access is requested.
    static func contains(_ coordinate: Coordinate) -> Bool {
        (55.8690...55.8770).contains(coordinate.latitude)
            && (-4.2990 ... -4.2820).contains(coordinate.longitude)
    }
}
