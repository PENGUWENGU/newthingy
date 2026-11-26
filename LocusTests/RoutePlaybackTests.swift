import CoreLocation
import XCTest

final class RoutePlaybackTests: XCTestCase {

    // MARK: - 1. Segment Boundary Interpolation (No Stale Old-Segment Jump)

    func testInterpolationAtSegmentBoundaryUsesNewSegmentAndHeading() {
        // Two ~111m legs forming a 90-degree corner: North, then East
        let p0 = CLLocationCoordinate2D(latitude: 37.0000, longitude: -122.0000)
        let p1 = CLLocationCoordinate2D(latitude: 37.0010, longitude: -122.0000) // ~111.2m North
        let p2 = CLLocationCoordinate2D(latitude: 37.0010, longitude: -121.9987) // ~115.6m East

        let plan = RoutePlaybackPlan(coordinateSegments: [[p0, p1, p2]])
        XCTAssertEqual(plan.edges.count, 2)

        var state = RoutePlaybackState(plan: plan)
        let edge0Length = plan.edges[0].distanceMeters

        // Advance right up to 10m before p1 on segment 0
        let firstStep = state.advance(byMeters: edge0Length - 10.0)
        XCTAssertEqual(firstStep.activeEdgeIndex, 0)
        XCTAssertFalse(firstStep.reachedEnd)
        XCTAssertEqual(firstStep.headingDegrees, 0.0, accuracy: 1.5)
        XCTAssertEqual(firstStep.upcomingTurnAngleDegrees, 90.0, accuracy: 2.0)

        // Next 30m crosses p1 cleanly by 20m into segment 1 (East)
        // Previously this bug caused backward interpolation toward p0 or mixed endpoints.
        let boundaryStep = state.advance(byMeters: 30.0)
        XCTAssertEqual(boundaryStep.activeEdgeIndex, 1)
        XCTAssertEqual(boundaryStep.distanceInActiveEdge, 20.0, accuracy: 0.5)
        XCTAssertEqual(boundaryStep.headingDegrees, 90.0, accuracy: 1.5)
        // Coordinate must lie east of p1 on segment 1, NOT south of p1 on segment 0
        XCTAssertEqual(boundaryStep.coordinate.latitude, p1.latitude, accuracy: 0.00002)
        XCTAssertGreaterThan(boundaryStep.coordinate.longitude, p1.longitude)
        XCTAssertLessThan(boundaryStep.coordinate.longitude, p2.longitude)
        XCTAssertEqual(
            RouteSimulationEngine.haversineDistance(from: p1, to: boundaryStep.coordinate),
            20.0,
            accuracy: 0.5
        )
    }

    // MARK: - 2. Multiple Segment Transitions in One Update

    func testMultipleSegmentTransitionsInSingleLargeStep() {
        // Four short 15m segments heading North
        let origin = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let p1 = RouteSimulationEngine.offsetCoordinate(origin, eastMeters: 0, northMeters: 15)
        let p2 = RouteSimulationEngine.offsetCoordinate(p1, eastMeters: 0, northMeters: 15)
        let p3 = RouteSimulationEngine.offsetCoordinate(p2, eastMeters: 15, northMeters: 0) // Turns East
        let p4 = RouteSimulationEngine.offsetCoordinate(p3, eastMeters: 25, northMeters: 0)

        let plan = RoutePlaybackPlan(coordinates: [origin, p1, p2, p3, p4])
        XCTAssertEqual(plan.edges.count, 4)

        var state = RoutePlaybackState(plan: plan)
        // Jump 40m in one update: 15m + 15m + 10m -> lands 10m into edge 2 (p2 -> p3, East)
        let step = state.advance(byMeters: 40.0)
        XCTAssertEqual(step.activeEdgeIndex, 2)
        XCTAssertEqual(step.distanceInActiveEdge, 10.0, accuracy: 0.5)
        XCTAssertEqual(step.headingDegrees, 90.0, accuracy: 1.5)
        XCTAssertFalse(step.reachedEnd)

        let expectedRemainder = (plan.edges[2].distanceMeters - 10.0) + plan.edges[3].distanceMeters
        XCTAssertEqual(step.remainingDistanceMeters, expectedRemainder, accuracy: 0.5)
        XCTAssertEqual(
            RouteSimulationEngine.haversineDistance(from: p2, to: step.coordinate),
            10.0,
            accuracy: 0.5
        )
    }

    // MARK: - 3. Sharp Turns & Speed Deceleration

    func testSharpTurnsTriggerTurnAngleAndSpeedDeceleration() {
        let p0 = CLLocationCoordinate2D(latitude: 37.5000, longitude: -122.0000)
        let p1 = RouteSimulationEngine.offsetCoordinate(p0, eastMeters: 0, northMeters: 100)
        // Hairpin ~150 degree turn back South-East
        let p2 = RouteSimulationEngine.offsetCoordinate(p1, eastMeters: 50, northMeters: -86.6)

        let plan = RoutePlaybackPlan(coordinates: [p0, p1, p2])
        let state = RoutePlaybackState(plan: plan)

        XCTAssertGreaterThan(state.upcomingTurnAngleDegrees, 140.0)

        let engine = RouteSimulationEngine(speedVarianceRangeMPH: 1.0)
        engine.enableRandomSpeedFluctuations = false
        // Ramp up to driving speed
        for _ in 0..<6 {
            _ = engine.computeNextSpeed(baseSpeedMPS: 16.0, travelMode: .drive, turnAngleDegrees: 0, elapsedSeconds: 1.0)
        }
        let cornerSpeed = engine.computeNextSpeed(
            baseSpeedMPS: 16.0,
            travelMode: .drive,
            turnAngleDegrees: state.upcomingTurnAngleDegrees,
            elapsedSeconds: 2.0
        )
        XCTAssertLessThan(cornerSpeed, 12.0)
    }

    // MARK: - 4. Very Short & Zero-Distance Routes

    func testVeryShortSubStepRouteCompletesCleanly() {
        let p0 = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
        let p1 = RouteSimulationEngine.offsetCoordinate(p0, eastMeters: 1.5, northMeters: 0)

        let plan = RoutePlaybackPlan(coordinates: [p0, p1])
        XCTAssertTrue(plan.isPlayable)
        var state = RoutePlaybackState(plan: plan)

        let step = state.advance(byMeters: 10.0)
        XCTAssertTrue(step.reachedEnd)
        XCTAssertTrue(state.isFinished)
        XCTAssertEqual(step.progress, 1.0, accuracy: 1e-6)
        XCTAssertEqual(step.remainingDistanceMeters, 0.0, accuracy: 1e-6)
        XCTAssertEqual(step.coordinate.latitude, p1.latitude, accuracy: 1e-7)
        XCTAssertEqual(step.coordinate.longitude, p1.longitude, accuracy: 1e-7)
    }

    func testDegenerateIdenticalPointsRouteNeverProducesNaN() {
        let p = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
        let plan = RoutePlaybackPlan(coordinates: [p, p, p])
        XCTAssertFalse(plan.isPlayable)
        XCTAssertEqual(plan.totalDistance, 0.0)

        var state = RoutePlaybackState(plan: plan)
        XCTAssertTrue(state.isFinished)
        let step = state.advance(byMeters: 10.0)
        XCTAssertTrue(step.reachedEnd)
        XCTAssertTrue(step.coordinate.latitude.isFinite)
        XCTAssertTrue(step.coordinate.longitude.isFinite)
        XCTAssertEqual(step.progress, 1.0)
    }

    // MARK: - 5. Long Routes

    func testLongRouteMonotonicProgressAndSmoothDistanceConservation() {
        let start = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let mid = CLLocationCoordinate2D(latitude: 40.9128, longitude: -73.8500)
        let end = CLLocationCoordinate2D(latitude: 41.1500, longitude: -73.7000)
        let sampled = RouteBuilder.multiPointStraightRoute(waypoints: [start, mid, end], every: 50.0)

        let plan = RoutePlaybackPlan(coordinates: sampled)
        XCTAssertGreaterThan(plan.totalDistance, 50_000.0)

        var state = RoutePlaybackState(plan: plan)
        var lastProgress = -1.0
        var lastRemaining = Double.infinity
        var ticks = 0

        while !state.isFinished && ticks < 10_000 {
            let step = state.advance(byMeters: 25.0)
            XCTAssertGreaterThanOrEqual(step.progress, lastProgress - 1e-12)
            XCTAssertLessThanOrEqual(step.remainingDistanceMeters, lastRemaining + 1e-9)
            XCTAssertTrue(RouteSimulationEngine.isValidCoordinate(step.coordinate))
            lastProgress = step.progress
            lastRemaining = step.remainingDistanceMeters
            ticks += 1
        }

        XCTAssertTrue(state.isFinished)
        XCTAssertEqual(lastProgress, 1.0, accuracy: 1e-6)
        XCTAssertEqual(lastRemaining, 0.0, accuracy: 1e-6)
    }

    // MARK: - 6. Multi-Segment GPX Disjoint Segments

    func testMultiSegmentPlaybackDoesNotBridgeDisjointSegments() {
        // Segment 0: 100m North in SF
        let seg0Start = CLLocationCoordinate2D(latitude: 37.7700, longitude: -122.4200)
        let seg0End = RouteSimulationEngine.offsetCoordinate(seg0Start, eastMeters: 0, northMeters: 100)

        // Segment 1: 10 km away, 100m East (completely disjoint <trkseg>)
        let seg1Start = CLLocationCoordinate2D(latitude: 37.8600, longitude: -122.3000)
        let seg1End = RouteSimulationEngine.offsetCoordinate(seg1Start, eastMeters: 100, northMeters: 0)

        let plan = RoutePlaybackPlan(coordinateSegments: [[seg0Start, seg0End], [seg1Start, seg1End]])
        XCTAssertEqual(plan.coordinateSegments.count, 2)
        XCTAssertEqual(plan.edges.count, 2)
        // Total distance must be ~200m, NOT ~13 km across the disjoint gap!
        XCTAssertEqual(plan.totalDistance, 200.0, accuracy: 2.0)

        var state = RoutePlaybackState(plan: plan)
        // Approaching the end of seg0 must NOT report a fake turn angle across the discontinuity
        let preGap = state.advance(byMeters: 50.0)
        XCTAssertEqual(preGap.trackSegmentIndex, 0)
        XCTAssertEqual(preGap.upcomingTurnAngleDegrees, 0.0)
        XCTAssertEqual(preGap.completedSegments.count, 1)
        XCTAssertEqual(preGap.remainingSegments.count, 2)

        // Stepping across the end of seg0 moves immediately to seg1 without interpolating inside the gap
        let acrossGap = state.advance(byMeters: 70.0) // 50 + 20 into seg1
        XCTAssertEqual(acrossGap.trackSegmentIndex, 1)
        XCTAssertTrue(acrossGap.jumpedSegmentDiscontinuity)
        XCTAssertEqual(
            RouteSimulationEngine.haversineDistance(from: seg1Start, to: acrossGap.coordinate),
            20.0,
            accuracy: 1.0
        )
        XCTAssertEqual(acrossGap.completedSegments.count, 2)
        XCTAssertEqual(acrossGap.remainingSegments.count, 1)
    }

    // MARK: - 7. Cancellation, Preemption & Single Cleanup Guarantees

    func testCancellationNeverClaimsNormalCompletion() {
        let controller = RoutePlaybackSessionController()
        let (sessionID, prev) = controller.beginNewSession()
        XCTAssertNil(prev)
        XCTAssertTrue(controller.isActive(sessionID, taskCancelled: false))

        // Task cancellation prevents normal completion even before stopActiveSession
        XCTAssertFalse(controller.claimCompletion(for: sessionID, taskCancelled: true))

        // Stopping claims cleanup once and prevents completion afterwards
        let stoppedCleanup = controller.stopActiveSession()
        XCTAssertEqual(stoppedCleanup, sessionID)
        XCTAssertFalse(controller.isActive(sessionID, taskCancelled: false))
        XCTAssertFalse(controller.claimCompletion(for: sessionID, taskCancelled: false))
        // Second cleanup claim returns false (cleanup happens at most once)
        XCTAssertFalse(controller.claimCleanup(for: sessionID))
    }

    func testStartingNewRouteWhilePreviousIsStoppingIsolatesSessions() {
        let controller = RoutePlaybackSessionController()
        let (oldSession, _) = controller.beginNewSession()

        // New route starts before old task exits or runs cleanup
        let (newSession, prevNeedingCleanup) = controller.beginNewSession()
        XCTAssertEqual(prevNeedingCleanup, oldSession)
        XCTAssertEqual(controller.currentSessionID, newSession)

        // Old task checks must all be rejected
        XCTAssertFalse(controller.isActive(oldSession, taskCancelled: false))
        XCTAssertFalse(controller.claimCompletion(for: oldSession, taskCancelled: false))
        // Because beginNewSession already handed cleanup ownership of oldSession to the starter,
        // oldSession's deferred claimCleanup returns false and leaves newSession untouched!
        XCTAssertFalse(controller.claimCleanup(for: oldSession))
        XCTAssertTrue(controller.isActive(newSession, taskCancelled: false))

        // New session completes normally and can claim completion exactly once
        XCTAssertTrue(controller.claimCompletion(for: newSession, taskCancelled: false))
        XCTAssertFalse(controller.claimCompletion(for: newSession, taskCancelled: false))
        XCTAssertFalse(controller.claimCleanup(for: newSession))
    }

    func testRepeatedRapidStartStopCycles() {
        let controller = RoutePlaybackSessionController()
        var previousIDs: [UUID] = []

        for idx in 0..<200 {
            let (sid, _) = controller.beginNewSession()
            XCTAssertEqual(controller.currentSessionID, sid)
            previousIDs.append(sid)

            if idx % 3 == 0 {
                let claimed = controller.stopActiveSession()
                XCTAssertEqual(claimed, sid)
                XCTAssertNil(controller.stopActiveSession())
                XCTAssertFalse(controller.claimCleanup(for: sid))
                XCTAssertFalse(controller.claimCompletion(for: sid, taskCancelled: false))
            } else if idx % 3 == 1 {
                XCTAssertTrue(controller.claimCompletion(for: sid, taskCancelled: false))
                XCTAssertFalse(controller.claimCompletion(for: sid, taskCancelled: false))
                XCTAssertFalse(controller.claimCleanup(for: sid))
            } else {
                // Leave active to be superseded cleanly by next cycle
                XCTAssertTrue(controller.isActive(sid, taskCancelled: false))
            }
        }

        // Clean final state
        if let active = controller.currentSessionID {
            XCTAssertEqual(controller.stopActiveSession(), active)
        }
        for oldID in previousIDs {
            XCTAssertFalse(controller.isActive(oldID, taskCancelled: false))
            XCTAssertFalse(controller.claimCompletion(for: oldID, taskCancelled: false))
        }
    }
}
