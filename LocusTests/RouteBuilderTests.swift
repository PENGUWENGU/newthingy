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

    // MARK: - Validation, Deduplication & Multi-Segment Safety

    func testInvalidSpacingAndNonFiniteInputsDoNotCrash() {
        let p1 = CLLocationCoordinate2D(latitude: 37.3300, longitude: -122.0300)
        let p2 = CLLocationCoordinate2D(latitude: 37.3400, longitude: -122.0300)

        XCTAssertEqual(RouteBuilder.sample(coordinates: [p1, p2], every: 0).count, 2)
        XCTAssertEqual(RouteBuilder.sample(coordinates: [p1, p2], every: -50).count, 2)
        XCTAssertEqual(RouteBuilder.sample(coordinates: [p1, p2], every: .nan).count, 2)
        XCTAssertEqual(RouteBuilder.sample(coordinates: [p1, p2], every: .infinity).count, 2)

        // Tiny spacing across continent must safely cap steps without Int overflow
        let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        let tokyo = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let capped = RouteBuilder.sample(coordinates: [london, tokyo], every: 1e-12)
        XCTAssertGreaterThan(capped.count, 2)
        XCTAssertLessThanOrEqual(capped.count, 50_005)

        // Non-finite coordinates must be filtered safely
        let bad = CLLocationCoordinate2D(latitude: .nan, longitude: .infinity)
        XCTAssertEqual(RouteBuilder.totalDistance(of: [p1, bad, p2]), RouteBuilder.totalDistance(of: [p1, p2]), accuracy: 1e-6)
        XCTAssertEqual(RouteBuilder.formattedDistance(.nan), "0 m")
        XCTAssertEqual(RouteBuilder.estimatedDuration(distance: .infinity, speed: 5.0), 0)
        XCTAssertEqual(RouteBuilder.formattedDuration(.nan), "0s")
        XCTAssertEqual(RouteBuilder.formattedETA(.infinity), "< 1m")
    }

    func testSamplingEliminatesDuplicates() {
        let p1 = CLLocationCoordinate2D(latitude: 37.3300, longitude: -122.0300)
        let p2 = CLLocationCoordinate2D(latitude: 37.3305, longitude: -122.0300)
        let sampled = RouteBuilder.sample(coordinates: [p1, p1, p1, p2, p2], every: 20)
        XCTAssertGreaterThanOrEqual(sampled.count, 2)
        for (a, b) in zip(sampled, sampled.dropFirst()) {
            XCTAssertGreaterThan(RouteSimulationEngine.haversineDistance(from: a, to: b), 1e-4)
        }
    }

    func testMultiSegmentSamplingDoesNotConnectDisjointSegments() {
        let segA = [
            CLLocationCoordinate2D(latitude: 37.000, longitude: -122.000),
            CLLocationCoordinate2D(latitude: 37.001, longitude: -122.000)
        ]
        let segB = [
            CLLocationCoordinate2D(latitude: 38.000, longitude: -121.000),
            CLLocationCoordinate2D(latitude: 38.001, longitude: -121.000)
        ]
        let track = GPXTrack(
            name: "Split",
            segments: [
                segA.map { GPXTrackPoint(coordinate: $0) },
                segB.map { GPXTrackPoint(coordinate: $0) }
            ]
        )
        let sampledTrack = RouteBuilder.sample(track: track, every: 10)
        XCTAssertEqual(sampledTrack.name, "Split")
        XCTAssertEqual(sampledTrack.segments.count, 2)

        // Segment-aware total distance must only reflect the two ~111m legs, not the 140km jump!
        let segmentedDistance = RouteBuilder.totalDistance(of: sampledTrack)
        XCTAssertEqual(segmentedDistance, 222.4, accuracy: 5.0)
    }

    func testSidewalkOffsetPerpendicularAtHighLatitude() {
        let p0 = CLLocationCoordinate2D(latitude: 65.0000, longitude: 10.0000)
        let p1 = RouteSimulationEngine.offsetCoordinate(p0, eastMeters: 0, northMeters: 50)
        // Includes duplicate middle vertex to verify lookahead heading recovery
        let shifted = RouteBuilder.applySidewalkOffset(coordinates: [p0, p0, p1], offsetMeters: 3.2)
        XCTAssertEqual(shifted.count, 3)
        // Going due North, right-hand sidewalk must shift due East by 3.2m even at 65°N
        XCTAssertEqual(RouteSimulationEngine.haversineDistance(from: p0, to: shifted[0]), 3.2, accuracy: 0.25)
        XCTAssertGreaterThan(shifted[0].longitude, p0.longitude)
        XCTAssertEqual(shifted[0].latitude, p0.latitude, accuracy: 1e-6)
    }
}
