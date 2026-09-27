import XCTest
import CoreLocation

final class RouteBuilderTests: XCTestCase {

    func testTotalDistanceCalculation() {
        let p1 = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let p2 = CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4194)
        let distance = RouteBuilder.totalDistance(coordinates: [p1, p2])
        XCTAssertGreaterThan(distance, 1000)
        XCTAssertLessThan(distance, 1200)
    }

    func testDirectRouteSampling() {
        let p1 = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let p2 = CLLocationCoordinate2D(latitude: 0, longitude: 0.001) // ~111 meters
        let sampled = RouteBuilder.directRoute(waypoints: [p1, p2], sampleEvery: 10)
        XCTAssertGreaterThan(sampled.count, 5)
        XCTAssertEqual(sampled.first?.latitude ?? -1, 0, accuracy: 1e-6)
        XCTAssertEqual(sampled.last?.longitude ?? -1, 0.001, accuracy: 1e-6)
    }

    func testFormattedDistance() {
        XCTAssertEqual(RouteBuilder.formattedDistance(450), "450 m")
        XCTAssertEqual(RouteBuilder.formattedDistance(1500), "1.50 km")
    }

    func testFormattedDuration() {
        // 1000 meters at 10 m/s = 100 seconds = 1m 40s
        let duration = RouteBuilder.formattedDuration(distance: 1000, speedMPS: 10)
        XCTAssertEqual(duration, "1m 40s")
    }

    func testRouteMethodEnum() {
        XCTAssertEqual(RouteMethod.allCases.count, 2)
        XCTAssertEqual(RouteMethod.points.rawValue, "Points")
        XCTAssertEqual(RouteMethod.freehand.rawValue, "Freehand")
    }
}
