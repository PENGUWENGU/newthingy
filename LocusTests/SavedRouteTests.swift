import CoreLocation
import MapKit
import XCTest

final class SavedRouteTests: XCTestCase {

    func testSavedRouteInitializationAndCodable() throws {
        let p1 = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let p2 = CLLocationCoordinate2D(latitude: 37.7833, longitude: -122.4167)
        let wp1 = RouteWaypoint(coordinate: p1, name: "Market St")
        let wp2 = RouteWaypoint(coordinate: p2, name: "Union Square")

        let route = SavedRoute(
            name: "Downtown Walk",
            method: .points,
            connectionType: .road,
            waypoints: [wp1, wp2],
            coordinates: [p1, p2],
            distanceMeters: 1250,
            isLoop: true
        )

        XCTAssertEqual(route.name, "Downtown Walk")
        XCTAssertEqual(route.method, .points)
        XCTAssertEqual(route.connectionType, .road)
        XCTAssertEqual(route.waypoints.count, 2)
        XCTAssertEqual(route.coordinates.count, 2)
        XCTAssertTrue(route.isLoop)

        // Encode to JSON
        let data = try JSONEncoder().encode(route)
        XCTAssertFalse(data.isEmpty)

        // Decode from JSON
        let decoded = try JSONDecoder().decode(SavedRoute.self, from: data)
        XCTAssertEqual(decoded.id, route.id)
        XCTAssertEqual(decoded.name, route.name)
        XCTAssertEqual(decoded.method, route.method)
        XCTAssertEqual(decoded.connectionType, route.connectionType)
        XCTAssertEqual(decoded.isLoop, route.isLoop)
        XCTAssertEqual(decoded.distanceMeters, route.distanceMeters)

        // Check converted CLLocationCoordinate2D coordinates
        let clCoords = decoded.clCoordinates
        XCTAssertEqual(clCoords.count, 2)
        XCTAssertEqual(clCoords[0].latitude, p1.latitude, accuracy: 0.0001)
        XCTAssertEqual(clCoords[1].longitude, p2.longitude, accuracy: 0.0001)

        // Check converted RouteWaypoint array
        let clWps = decoded.clWaypoints
        XCTAssertEqual(clWps.count, 2)
        XCTAssertEqual(clWps[0].name, "Market St")
        XCTAssertEqual(clWps[1].name, "Union Square")
    }

    func testSuggestedNameGeneration() {
        let p1 = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let p2 = CLLocationCoordinate2D(latitude: 37.7833, longitude: -122.4167)
        let wp1 = RouteWaypoint(coordinate: p1, name: "Start Pier")
        let wp2 = RouteWaypoint(coordinate: p2, name: "Ferry Building")

        let suggestedPoints = SavedRoute.suggestedName(
            waypoints: [wp1, wp2],
            method: .points,
            distance: 2500
        )
        XCTAssertEqual(suggestedPoints, "Start Pier → Ferry Building")

        let suggestedFreehand = SavedRoute.suggestedName(
            waypoints: [],
            method: .freehand,
            distance: 850
        )
        XCTAssertEqual(suggestedFreehand, "Drawn Path (850 m)")
    }

    func testCoordinateRegionFraming() {
        let p1 = CLLocationCoordinate2D(latitude: 37.3300, longitude: -122.0300)
        let p2 = CLLocationCoordinate2D(latitude: 37.3400, longitude: -122.0200)

        let region = MKCoordinateRegion.framing([p1, p2])
        XCTAssertNotNil(region)

        let center = region!.center
        XCTAssertEqual(center.latitude, 37.3350, accuracy: 0.0001)
        XCTAssertEqual(center.longitude, -122.0250, accuracy: 0.0001)
        XCTAssertGreaterThan(region!.span.latitudeDelta, 0.01)
        XCTAssertGreaterThan(region!.span.longitudeDelta, 0.01)
    }

    func testSavedRouteStoragePersistence() {
        let key = "locus.test.saved_routes.\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removeObject(forKey: key)
        }

        let p1 = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let route = SavedRoute(
            name: "Test Route",
            method: .freehand,
            coordinates: [p1],
            distanceMeters: 500
        )

        SavedRoute.save([route], key: key)
        let loaded = SavedRoute.load(key: key)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, route.id)
        XCTAssertEqual(loaded.first?.name, "Test Route")
    }
}
