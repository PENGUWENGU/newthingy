import CoreLocation
import Foundation
import MapKit

// MARK: - Codable Coordinate

struct CodableCoordinate: Codable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double

    init(_ coord: CLLocationCoordinate2D) {
        self.latitude = coord.latitude
        self.longitude = coord.longitude
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Saved Waypoint

struct SavedWaypoint: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var name: String
    var stopDuration: TimeInterval?

    init(
        id: UUID = UUID(),
        coordinate: CLLocationCoordinate2D,
        name: String = "",
        stopDuration: TimeInterval = 0
    ) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.name = name
        self.stopDuration = stopDuration > 0 ? stopDuration : nil
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var routeWaypoint: RouteWaypoint {
        RouteWaypoint(id: id, coordinate: coordinate, name: name, stopDuration: stopDuration ?? 0)
    }
}

// MARK: - Saved Route Model

struct SavedRoute: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var methodRaw: String
    var connectionTypeRaw: String
    var waypoints: [SavedWaypoint]
    var coordinates: [CodableCoordinate]
    var distanceMeters: Double
    var isLoop: Bool

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        method: RouteCreationMethod,
        connectionType: RouteConnectionType = .road,
        waypoints: [RouteWaypoint] = [],
        coordinates: [CLLocationCoordinate2D],
        distanceMeters: Double,
        isLoop: Bool = false
    ) {
        self.id = id
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed.isEmpty ? "Saved Route" : trimmed
        self.createdAt = createdAt
        self.methodRaw = method.rawValue
        self.connectionTypeRaw = connectionType.rawValue
        self.waypoints = waypoints.map { SavedWaypoint(id: $0.id, coordinate: $0.coordinate, name: $0.name, stopDuration: $0.stopDuration) }
        self.coordinates = coordinates.map { CodableCoordinate($0) }
        self.distanceMeters = distanceMeters
        self.isLoop = isLoop
    }

    var method: RouteCreationMethod {
        RouteCreationMethod(rawValue: methodRaw) ?? .points
    }

    var connectionType: RouteConnectionType {
        RouteConnectionType(rawValue: connectionTypeRaw) ?? .road
    }

    var clWaypoints: [RouteWaypoint] {
        waypoints.map { $0.routeWaypoint }
    }

    var clCoordinates: [CLLocationCoordinate2D] {
        coordinates.map { $0.clCoordinate }
    }

    var formattedDistance: String {
        RouteBuilder.formattedDistance(distanceMeters)
    }

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    static func suggestedName(
        waypoints: [RouteWaypoint],
        method: RouteCreationMethod,
        distance: Double
    ) -> String {
        if method == .points, let first = waypoints.first, let last = waypoints.last, waypoints.count >= 2 {
            let firstName = first.name.isEmpty ? "Start" : first.name
            let lastName = last.name.isEmpty ? "End" : last.name
            if firstName != lastName {
                return "\(firstName) → \(lastName)"
            }
        }
        let distStr = RouteBuilder.formattedDistance(distance)
        let methodStr = method == .freehand ? "Drawn Path" : "Route"
        return "\(methodStr) (\(distStr))"
    }

    static func load(key: String = "locus.saved_routes") -> [SavedRoute] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedRoute].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ routes: [SavedRoute], key: String = "locus.saved_routes") {
        if let data = try? JSONEncoder().encode(routes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Map Framing Helper

extension MKCoordinateRegion {
    static func framing(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let latDelta = max(0.006, (maxLat - minLat) * 1.45)
        let lonDelta = max(0.006, (maxLon - minLon) * 1.45)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }
}
