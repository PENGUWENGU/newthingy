import CoreLocation
import XCTest

final class RouteSimulationEngineTests: XCTestCase {
    func testHaversineDistanceAccuracy() {
        // San Francisco to Los Angeles (~559 km)
        let sf = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let la = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        let dist = RouteSimulationEngine.haversineDistance(from: sf, to: la)
        XCTAssertGreaterThan(dist, 550_000)
        XCTAssertLessThan(dist, 570_000)
    }

    func testGreatCircleBearing() {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let north = CLLocationCoordinate2D(latitude: 10, longitude: 0)
        let east = CLLocationCoordinate2D(latitude: 0, longitude: 10)

        let bearingNorth = RouteSimulationEngine.greatCircleBearing(from: origin, to: north)
        XCTAssertEqual(bearingNorth, 0.0, accuracy: 0.1)

        let bearingEast = RouteSimulationEngine.greatCircleBearing(from: origin, to: east)
        XCTAssertEqual(bearingEast, 90.0, accuracy: 0.1)
    }

    func testGreatCircleInterpolation() {
        let p0 = CLLocationCoordinate2D(latitude: 10, longitude: 20)
        let p1 = CLLocationCoordinate2D(latitude: 20, longitude: 30)

        let mid = RouteSimulationEngine.interpolateGreatCircle(from: p0, to: p1, fraction: 0.5)
        XCTAssertGreaterThan(mid.latitude, 14.5)
        XCTAssertLessThan(mid.latitude, 15.5)
        XCTAssertGreaterThan(mid.longitude, 24.5)
        XCTAssertLessThan(mid.longitude, 25.5)
    }

    func testWalkingSpeedStateStaysWithinOneToTwoMph() {
        let engine = RouteSimulationEngine(speedVarianceRangeMPH: 3.0)
        let walkMPS = TravelMode.walk.baseSpeed // 0.72 m/s (~1.6 mph)

        for _ in 0..<30 {
            let speed = engine.computeNextSpeed(baseSpeedMPS: walkMPS, travelMode: .walk, turnAngleDegrees: 0, elapsedSeconds: 1.0)
            let mph = speed * 2.236936
            // Must stay realistically within walking bounds (0.9 to 2.2 mph)
            XCTAssertGreaterThanOrEqual(mph, 0.9)
            XCTAssertLessThanOrEqual(mph, 2.2)
        }
    }

    func testDrivingSpeedSlowsDownOnSharpTurns() {
        let engine = RouteSimulationEngine(speedVarianceRangeMPH: 2.0)
        let driveMPS = TravelMode.drive.baseSpeed // 15.65 m/s (~35 mph)

        // Accelerate straight
        _ = engine.computeNextSpeed(baseSpeedMPS: driveMPS, travelMode: .drive, turnAngleDegrees: 0, elapsedSeconds: 5.0)

        // Approach sharp 90-degree corner
        let cornerSpeed = engine.computeNextSpeed(baseSpeedMPS: driveMPS, travelMode: .drive, turnAngleDegrees: 90, elapsedSeconds: 1.0)
        let cornerMPH = cornerSpeed * 2.236936

        // Should decelerate into turn
        XCTAssertLessThan(cornerMPH, 25.0)
    }

    func testTelemetryPayloadAlwaysHasPositiveSpeedAndHeading() {
        let engine = RouteSimulationEngine(speedVarianceRangeMPH: 3.0)
        let origin = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

        let payload = engine.generateTelemetryPayload(
            rawCoordinate: origin,
            headingDegrees: 135.0,
            speedMPS: 14.2,
            travelMode: .drive
        )

        XCTAssertGreaterThan(payload.speedMPS, 0.0)
        XCTAssertGreaterThan(payload.speedMPH, 0.0)
        XCTAssertEqual(payload.courseDegrees, 135.0)

        // Verify GPS jitter displacement is subtle (0.2–1.8m)
        let jitterDistance = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: payload.coordinate.latitude, longitude: payload.coordinate.longitude))
        XCTAssertGreaterThan(jitterDistance, 0.1)
        XCTAssertLessThan(jitterDistance, 2.0)
    }

    func testSpeedVarianceRangeClampedToOneToFiveMph() {
        let engineUnder = RouteSimulationEngine(speedVarianceRangeMPH: 0.2)
        XCTAssertEqual(engineUnder.speedVarianceRangeMPH, 1.0)

        let engineOver = RouteSimulationEngine(speedVarianceRangeMPH: 9.0)
        XCTAssertEqual(engineOver.speedVarianceRangeMPH, 5.0)
    }
}
