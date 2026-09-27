import CoreLocation
import XCTest

final class RouteBuilderTests: XCTestCase {

    // MARK: - Method Enums & Models

    func testRouteCreationMethodsExist() {
        XCTAssertEqual(RouteCreationMethod.points.rawValue, "Points")
        XCTAssertEqual(RouteCreationMethod.freehand.rawValue, "Freehand")
        XCTAssertEqual(RouteCreationMethod.allCases.count, 2)
    }

    func testWaypointEqualityAndHashing() {
        let id = UUID()
        let c1 = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
        let c2 = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
        let wp1 = RouteWaypoint(id: id, coordinate: c1, name: "Start")
        let wp2 = RouteWaypoint(id: id, coordinate: c2, name: "Start")

        XCTAssertEqual(wp1, wp2)
        XCTAssertEqual(wp1.hashValue, wp2.hashValue)
    }

    // MARK: - Points Routing (Straight Lines)

    func testPointsStraightRouteInterpolation() {
        let p1 = CLLocationCoordinate2D(latitude: 37.3300, longitude: -122.0300)
        let p2 = CLLocationCoordinate2D(latitude: 37.3400, longitude: -122.0300)
        let waypoints = [p1, p2]

        let route = RouteBuilder.multiPointStraightRoute(waypoints: waypoints, every: 20)
        XCTAssertGreaterThan(route.count, 2)
        XCTAssertEqual(route.first?.latitude, p1.latitude)
        XCTAssertEqual(route.last?.latitude, p2.latitude)
    }

    func testPointsStraightRouteSinglePointReturnsSelf() {
        let p1 = CLLocationCoordinate2D(latitude: 37.3300, longitude: -122.0300)
        let route = RouteBuilder.multiPointStraightRoute(waypoints: [p1])
        XCTAssertEqual(route.count, 1)
    }

    // MARK: - Freehand Path Processing

    func testFreehandDeduplicationAndSampling() {
        let p1 = CLLocationCoordinate2D(latitude: 37.330000, longitude: -122.030000)
        // Extremely close duplicate point (< 0.1m)
        let pDuplicate = CLLocationCoordinate2D(latitude: 37.3300001, longitude: -122.0300001)
        let p2 = CLLocationCoordinate2D(latitude: 37.331000, longitude: -122.030000)
        let p3 = CLLocationCoordinate2D(latitude: 37.332000, longitude: -122.030000)

        let raw = [p1, pDuplicate, p2, p3]
        let processed = RouteBuilder.processFreehandPath(coordinates: raw, sampleMeters: 10, smooth: true)

        XCTAssertGreaterThanOrEqual(processed.count, 2)
        XCTAssertEqual(processed.first?.latitude, p1.latitude)
    }

    func testFreehandHandlesShortArrays() {
        let p1 = CLLocationCoordinate2D(latitude: 37.330000, longitude: -122.030000)
        let processed = RouteBuilder.processFreehandPath(coordinates: [p1])
        XCTAssertEqual(processed.count, 1)
    }

    // MARK: - Distance & Duration Calculations

    func testTotalDistanceCalculation() {
        let p1 = CLLocationCoordinate2D(latitude: 37.3300, longitude: -122.0300)
        let p2 = CLLocationCoordinate2D(latitude: 37.3400, longitude: -122.0300)
        let distance = RouteBuilder.totalDistance(of: [p1, p2])

        // ~1.11 km for 0.01 deg latitude
        XCTAssertGreaterThan(distance, 1000)
        XCTAssertLessThan(distance, 1200)
    }

    func testFormattedDistance() {
        XCTAssertEqual(RouteBuilder.formattedDistance(350), "350 m")
        XCTAssertEqual(RouteBuilder.formattedDistance(1500), "1.50 km")
    }

    func testEstimatedDurationAndFormatting() {
        let duration = RouteBuilder.estimatedDuration(distance: 300, speed: 5.0) // 60 seconds
        XCTAssertEqual(duration, 60)
        XCTAssertEqual(RouteBuilder.formattedDuration(60), "1m 0s")
        XCTAssertEqual(RouteBuilder.formattedDuration(45), "45s")
        XCTAssertEqual(RouteBuilder.formattedDuration(3665), "1h 1m")
    }

    func testFormattedETA() {
        let etaShort = RouteBuilder.formattedETA(0.5)
        XCTAssertEqual(etaShort, "< 1m")

        let etaMinutes = RouteBuilder.formattedETA(120)
        XCTAssertTrue(etaMinutes.contains("2m 0s"))
        XCTAssertTrue(etaMinutes.contains("("))
        XCTAssertTrue(etaMinutes.contains(")"))
    }

    func testRouteConnectionPreferencePersistence() {
        let original = RouteConnectionPreference.defaultType
        defer {
            RouteConnectionPreference.defaultType = original
        }

        RouteConnectionPreference.defaultType = .straight
        XCTAssertEqual(RouteConnectionPreference.defaultType, .straight)

        RouteConnectionPreference.defaultType = .road
        XCTAssertEqual(RouteConnectionPreference.defaultType, .road)
    }
}
