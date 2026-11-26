import CoreLocation
import Foundation

/// High-precision coordinate mathematics, dynamic speed profiling, and telemetry realism engine.
/// Designed to simulate authentic real-world GPS kinematics for Apple locationd and tracking apps (Life360, Find My).
public final class RouteSimulationEngine {
    // MARK: - Telemetry Payload

    public struct TelemetryPayload: Equatable {
        public let coordinate: CLLocationCoordinate2D
        public let rawCoordinate: CLLocationCoordinate2D
        public let speedMPS: Double // Always > 0 during transit
        public let speedMPH: Double
        public let courseDegrees: Double // 0.0..<360.0
        public let altitudeMeters: Double
        public let horizontalAccuracy: Double // 4.5–7.0 meters
        public let verticalAccuracy: Double // 3.5–6.0 meters
        public let timestamp: Date
        public let stateTitle: String

        public init(
            coordinate: CLLocationCoordinate2D,
            rawCoordinate: CLLocationCoordinate2D,
            speedMPS: Double,
            speedMPH: Double,
            courseDegrees: Double,
            altitudeMeters: Double = 18.0,
            horizontalAccuracy: Double = 5.2,
            verticalAccuracy: Double = 4.1,
            timestamp: Date = Date(),
            stateTitle: String = "In Motion"
        ) {
            self.coordinate = coordinate
            self.rawCoordinate = rawCoordinate
            self.speedMPS = max(0.1, speedMPS)
            self.speedMPH = max(0.2, speedMPH)
            self.courseDegrees = courseDegrees
            self.altitudeMeters = altitudeMeters
            self.horizontalAccuracy = horizontalAccuracy
            self.verticalAccuracy = verticalAccuracy
            self.timestamp = timestamp
            self.stateTitle = stateTitle
        }
    }

    // MARK: - Speed Profiling States

    public enum MovementState: Equatable {
        case walking(cadenceCycle: Double) // 1.0–2.0 mph with natural step sway
        case driving(cruisingMPS: Double, currentMPS: Double, isTurning: Bool) // 28–45 mph with acceleration curve & turn deceleration
        case transitBus(cruisingMPS: Double, currentMPS: Double) // 20–25 mph with dwell stops
        case stationaryDwell(remaining: TimeInterval, reason: String) // Traffic lights, bus stops, waypoint dwells
    }

    // MARK: - State Properties

    private var persistentAlongTrackError: Double = 0.0
    private var persistentCrossTrackError: Double = 0.0
    private var speedRandomWalkOffsetMPH: Double = 0.0
    private var stepCadencePhase: Double = 0.0
    private var throttlePhase: Double = Double.random(in: 0...100)
    private var currentFilteredSpeedMPS: Double = 0.0
    private var lastValidHeading: Double = 0.0

    // MARK: - Configurable Parameters

    public var speedVarianceRangeMPH: Double = 3.0 // 1.0 to 5.0 mph user-selected variance
    public var enableRandomSpeedFluctuations: Bool = true
    public var enableGPSJitter: Bool = true

    public init(speedVarianceRangeMPH: Double = 3.0) {
        self.speedVarianceRangeMPH = min(5.0, max(1.0, speedVarianceRangeMPH))
    }

    public func reset(initialSpeedMPS: Double = 0.0, initialHeading: Double = 0.0) {
        persistentAlongTrackError = 0.0
        persistentCrossTrackError = 0.0
        speedRandomWalkOffsetMPH = 0.0
        stepCadencePhase = 0.0
        throttlePhase = Double.random(in: 0...100)
        currentFilteredSpeedMPS = initialSpeedMPS
        lastValidHeading = initialHeading
    }

    // MARK: - Great Circle & Haversine Geodesic Math

    public static let earthRadiusMeters: Double = 6371008.8

    /// Returns true if latitude and longitude are finite and within valid WGS84 bounds.
    public static func isValidCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude.isFinite
            && coordinate.longitude.isFinite
            && (-90.0...90.0).contains(coordinate.latitude)
            && (-180.0...180.0).contains(coordinate.longitude)
    }

    /// Normalizes a longitude in degrees into [-180, 180].
    public static func normalizeLongitude(_ longitude: Double) -> Double {
        guard longitude.isFinite else { return 0.0 }
        var lon = longitude.truncatingRemainder(dividingBy: 360.0)
        if lon > 180.0 { lon -= 360.0 }
        if lon < -180.0 { lon += 360.0 }
        return lon
    }

    /// Clamps latitude to [-90, 90] and wraps longitude cleanly across the antimeridian.
    public static func clampAndNormalize(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let lat = coordinate.latitude.isFinite ? min(90.0, max(-90.0, coordinate.latitude)) : 0.0
        let lon = normalizeLongitude(coordinate.longitude)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Normalizes an azimuth bearing into [0, 360).
    public static func normalizeBearing(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0.0 }
        let mod = degrees.truncatingRemainder(dividingBy: 360.0)
        let normalized = mod >= 0 ? mod : mod + 360.0
        return normalized >= 360.0 ? 0.0 : normalized
    }

    /// Offsets a coordinate by local East/North meters safely across latitudes and the antimeridian.
    public static func offsetCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        eastMeters: Double,
        northMeters: Double
    ) -> CLLocationCoordinate2D {
        guard isValidCoordinate(coordinate) else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        let safeNorth = northMeters.isFinite ? northMeters : 0.0
        let safeEast = eastMeters.isFinite ? eastMeters : 0.0

        let latRad = coordinate.latitude * .pi / 180.0
        let dLat = (safeNorth / earthRadiusMeters) * (180.0 / .pi)
        let newLat = min(90.0, max(-90.0, coordinate.latitude + dLat))

        // Prevent division by near-zero cos(lat) at geographic poles
        let safeCosLat = max(1e-4, cos(latRad))
        let dLon = (safeEast / (earthRadiusMeters * safeCosLat)) * (180.0 / .pi)
        let newLon = normalizeLongitude(coordinate.longitude + dLon)

        return CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
    }

    /// High-precision Haversine Great Circle distance between two coordinates in meters.
    public static func haversineDistance(from c1: CLLocationCoordinate2D, to c2: CLLocationCoordinate2D) -> CLLocationDistance {
        guard isValidCoordinate(c1), isValidCoordinate(c2) else { return 0.0 }
        let lat1 = c1.latitude * .pi / 180.0
        let lat2 = c2.latitude * .pi / 180.0
        let dLat = (c2.latitude - c1.latitude) * .pi / 180.0
        let dLon = (c2.longitude - c1.longitude) * .pi / 180.0

        let rawA = sin(dLat / 2.0) * sin(dLat / 2.0) +
                   cos(lat1) * cos(lat2) * sin(dLon / 2.0) * sin(dLon / 2.0)
        let a = min(1.0, max(0.0, rawA))
        let c = 2.0 * atan2(sqrt(a), sqrt(max(0.0, 1.0 - a)))
        let result = earthRadiusMeters * c
        return result.isFinite ? max(0.0, result) : 0.0
    }

    /// Mathematical forward azimuth (course/heading degrees: 0° North, 90° East, 180° South, 270° West).
    public static func greatCircleBearing(from c1: CLLocationCoordinate2D, to c2: CLLocationCoordinate2D) -> Double {
        guard isValidCoordinate(c1), isValidCoordinate(c2) else { return 0.0 }
        if abs(c1.latitude - c2.latitude) < 1e-12 && abs(c1.longitude - c2.longitude) < 1e-12 {
            return 0.0
        }
        let lat1 = c1.latitude * .pi / 180.0
        let lat2 = c2.latitude * .pi / 180.0
        let dLon = (c2.longitude - c1.longitude) * .pi / 180.0

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        if abs(x) < 1e-15 && abs(y) < 1e-15 { return 0.0 }
        let radians = atan2(y, x)
        return normalizeBearing(radians * 180.0 / .pi)
    }

    /// Great Circle spherical linear interpolation (Slerp) along the Earth's geodesic arc.
    public static func interpolateGreatCircle(
        from c1: CLLocationCoordinate2D,
        to c2: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        let valid1 = isValidCoordinate(c1)
        let valid2 = isValidCoordinate(c2)
        guard valid1 || valid2 else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        if !valid1 { return clampAndNormalize(c2) }
        if !valid2 { return clampAndNormalize(c1) }

        let safeFraction = fraction.isFinite ? fraction : 0.0
        let t = min(1.0, max(0.0, safeFraction))
        if t <= 1e-6 { return c1 }
        if t >= 1.0 - 1e-6 { return c2 }

        let lat1 = c1.latitude * .pi / 180.0
        let lon1 = c1.longitude * .pi / 180.0
        let lat2 = c2.latitude * .pi / 180.0
        let lon2 = c2.longitude * .pi / 180.0

        let delta = haversineDistance(from: c1, to: c2) / earthRadiusMeters
        if delta < 1e-9 { return c1 }

        let sinDelta = sin(delta)
        // Guard near-antipodal points where sin(delta) approaches 0
        if abs(sinDelta) < 1e-9 {
            let midLat = min(90.0, max(-90.0, c1.latitude + (c2.latitude - c1.latitude) * t))
            let midLon = normalizeLongitude(c1.longitude + normalizeLongitude(c2.longitude - c1.longitude) * t)
            return CLLocationCoordinate2D(latitude: midLat, longitude: midLon)
        }

        let a = sin((1.0 - t) * delta) / sinDelta
        let b = sin(t * delta) / sinDelta

        let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)

        let outLat = atan2(z, sqrt(x * x + y * y))
        let outLon = atan2(y, x)

        return clampAndNormalize(CLLocationCoordinate2D(
            latitude: outLat * 180.0 / .pi,
            longitude: outLon * 180.0 / .pi
        ))
    }

    /// Computes the angle difference in degrees between two bearings (0...180).
    public static func turnAngleBetween(bearing1: Double, bearing2: Double) -> Double {
        guard bearing1.isFinite, bearing2.isFinite else { return 0.0 }
        let b1 = normalizeBearing(bearing1)
        let b2 = normalizeBearing(bearing2)
        let diff = abs(b1 - b2).truncatingRemainder(dividingBy: 360.0)
        return diff > 180.0 ? 360.0 - diff : diff
    }

    // MARK: - Dynamic Speed Profiler & Kinematics

    /// Updates velocity using realistic physics curves (acceleration, corner braking, and random variance).
    public func computeNextSpeed(
        baseSpeedMPS: Double,
        travelMode: TravelMode,
        turnAngleDegrees: Double,
        elapsedSeconds: Double
    ) -> Double {
        let safeElapsed = elapsedSeconds.isFinite ? min(5.0, max(0.0, elapsedSeconds)) : 1.0
        if !currentFilteredSpeedMPS.isFinite || currentFilteredSpeedMPS < 0 {
            currentFilteredSpeedMPS = 0.0
        }
        if safeElapsed == 0 {
            return max(0.4, currentFilteredSpeedMPS)
        }

        let dt = max(0.05, safeElapsed)
        let safeTurn = turnAngleDegrees.isFinite ? abs(turnAngleDegrees) : 0.0
        let safeBase = (baseSpeedMPS.isFinite && baseSpeedMPS > 0) ? baseSpeedMPS : travelMode.baseSpeed

        // 1. Turn-adaptive speed scaling (real vehicles slow down on turns)
        var targetMPS = safeBase
        if travelMode == .drive || travelMode == .bus {
            if safeTurn > 60 {
                // Hard 60-90° turn: slow down to ~15–18 mph (6.7–8.0 m/s)
                targetMPS = min(targetMPS, 7.5)
            } else if safeTurn > 30 {
                // Moderate turn: slow down to ~22 mph (9.8 m/s)
                targetMPS = min(targetMPS, 9.8)
            }
        }

        // 2. Realistic Dynamic Random Speed Fluctuation within 1–5 mph range
        if enableRandomSpeedFluctuations {
            let maxVarianceMPH = min(5.0, max(1.0, speedVarianceRangeMPH.isFinite ? speedVarianceRangeMPH : 3.0))
            // Dynamic driver throttle wave with organic Brownian perturbation
            throttlePhase += dt * 0.45
            if throttlePhase > 1_000_000 { throttlePhase = throttlePhase.truncatingRemainder(dividingBy: 2.0 * .pi) }
            let primaryWave = sin(throttlePhase) * 0.70
            let harmonicWave = sin(throttlePhase * 2.3) * 0.22
            let microJitter = Double.random(in: -0.12...0.12)
            let dynamicOffset = (primaryWave + harmonicWave + microJitter) * maxVarianceMPH
            speedRandomWalkOffsetMPH = min(maxVarianceMPH, max(-maxVarianceMPH, dynamicOffset))

            // Scale variance realistically for walking (max 0.35 mph) vs vehicles (full 1–5 mph)
            let effectiveVarianceMPH: Double
            switch travelMode {
            case .walk, .sidewalk:
                effectiveVarianceMPH = min(0.35, max(-0.35, speedRandomWalkOffsetMPH * 0.15))
            case .run:
                effectiveVarianceMPH = min(0.9, max(-0.9, speedRandomWalkOffsetMPH * 0.30))
            case .cycle, .bus, .drive:
                effectiveVarianceMPH = speedRandomWalkOffsetMPH
            }

            let varianceMPS = effectiveVarianceMPH * 0.44704
            targetMPS = max(0.5, targetMPS + varianceMPS)
        }

        // 3. Mode-specific physiological/mechanical acceleration ramping
        let maxAcceleration: Double // m/s^2
        let maxDeceleration: Double // m/s^2
        switch travelMode {
        case .walk, .sidewalk:
            maxAcceleration = 1.2
            maxDeceleration = 1.5
            // Ensure walking stays naturally bound to 1.0–2.0 mph (0.45–0.90 m/s)
            targetMPS = min(0.90, max(0.45, targetMPS))
        case .run:
            maxAcceleration = 2.0
            maxDeceleration = 2.2
        case .cycle:
            maxAcceleration = 2.2
            maxDeceleration = 3.0
        case .bus:
            maxAcceleration = 1.8
            maxDeceleration = 3.2
        case .drive:
            maxAcceleration = 3.5 // realistic automotive throttle response
            maxDeceleration = 4.5
        }

        if currentFilteredSpeedMPS < targetMPS {
            currentFilteredSpeedMPS = min(targetMPS, currentFilteredSpeedMPS + maxAcceleration * dt)
        } else if currentFilteredSpeedMPS > targetMPS {
            currentFilteredSpeedMPS = max(targetMPS, currentFilteredSpeedMPS - maxDeceleration * dt)
        }

        // 4. Cadence micro-fluctuation for human walking/running
        if travelMode == .walk || travelMode == .sidewalk {
            stepCadencePhase += dt * 3.2 // ~110 steps/min
            if stepCadencePhase > 1_000_000 { stepCadencePhase = stepCadencePhase.truncatingRemainder(dividingBy: 2.0 * .pi) }
            let cadenceFactor = 1.0 + (sin(stepCadencePhase) * 0.04)
            currentFilteredSpeedMPS *= cadenceFactor
            // Strictly guard walking at 1–2 mph (0.45–0.90 m/s)
            currentFilteredSpeedMPS = min(0.95, max(0.42, currentFilteredSpeedMPS))
        }

        return currentFilteredSpeedMPS.isFinite ? max(0.4, currentFilteredSpeedMPS) : max(0.4, safeBase)
    }

    // MARK: - Telemetry Realism & GPS Jitter Injection

    /// Applies subtle 0.5–1.5m satellite multipath noise and Gauss-Markov drift.
    /// Preserves kinematic velocity and course vector so tracking engines (Life360) validate real motion.
    public func generateTelemetryPayload(
        rawCoordinate: CLLocationCoordinate2D,
        headingDegrees: Double,
        speedMPS: Double,
        travelMode: TravelMode,
        stateTitle: String = "In Motion"
    ) -> TelemetryPayload {
        let safeRaw = Self.clampAndNormalize(rawCoordinate)
        let safeHeading = Self.normalizeBearing(headingDegrees.isFinite ? headingDegrees : lastValidHeading)
        let safeSpeed = (speedMPS.isFinite && speedMPS > 0) ? speedMPS : 0.1
        lastValidHeading = safeHeading
        let speedMPH = safeSpeed * 2.236936

        guard enableGPSJitter, Self.isValidCoordinate(rawCoordinate) else {
            return TelemetryPayload(
                coordinate: safeRaw,
                rawCoordinate: safeRaw,
                speedMPS: safeSpeed,
                speedMPH: speedMPH,
                courseDegrees: safeHeading,
                stateTitle: stateTitle
            )
        }

        // 1st-order Gauss-Markov atmospheric/multipath correlation
        persistentCrossTrackError = (persistentCrossTrackError * 0.80) + Double.random(in: -0.12...0.12)
        persistentAlongTrackError = (persistentAlongTrackError * 0.80) + Double.random(in: -0.06...0.06)
        let totalAlong = max(-0.20, min(0.20, persistentAlongTrackError))
        let totalCross = max(-0.60, min(0.60, persistentCrossTrackError))

        // High frequency micro-jitter (predominantly lateral cross-track so forward speed is never cancelled)
        let microCross = Double.random(in: -0.30...0.30)
        let microAlong = Double.random(in: -0.10...0.10)

        let headingRad = safeHeading * .pi / 180.0
        let alongMeters = totalAlong + microAlong
        let crossMeters = totalCross + microCross

        let eastMeters = (alongMeters * sin(headingRad)) + (crossMeters * cos(headingRad))
        let northMeters = (alongMeters * cos(headingRad)) - (crossMeters * sin(headingRad))

        let jitteredCoordinate = Self.offsetCoordinate(safeRaw, eastMeters: eastMeters, northMeters: northMeters)

        // Realistic horizontal accuracy (varies smoothly between 4.2m and 6.8m)
        let horizAcc = 5.0 + Double.random(in: -0.7...1.2)
        let vertAcc = 3.8 + Double.random(in: -0.5...0.9)

        return TelemetryPayload(
            coordinate: jitteredCoordinate,
            rawCoordinate: safeRaw,
            speedMPS: safeSpeed,
            speedMPH: speedMPH,
            courseDegrees: safeHeading,
            horizontalAccuracy: horizAcc,
            verticalAccuracy: vertAcc,
            stateTitle: stateTitle
        )
    }
}

// MARK: - Route Playback Engine (Pure Segment-Accurate Stepper & Session Coordinator)

/// A directed geodesic edge inside a continuous track segment.
public struct RouteEdge: Equatable {
    public let start: CLLocationCoordinate2D
    public let end: CLLocationCoordinate2D
    public let trackSegmentIndex: Int
    public let localStartPointIndex: Int
    public let distanceMeters: Double
    public let bearingDegrees: Double

    public static func == (lhs: RouteEdge, rhs: RouteEdge) -> Bool {
        lhs.start.latitude == rhs.start.latitude
            && lhs.start.longitude == rhs.start.longitude
            && lhs.end.latitude == rhs.end.latitude
            && lhs.end.longitude == rhs.end.longitude
            && lhs.trackSegmentIndex == rhs.trackSegmentIndex
            && lhs.localStartPointIndex == rhs.localStartPointIndex
            && lhs.distanceMeters == rhs.distanceMeters
            && lhs.bearingDegrees == rhs.bearingDegrees
    }
}

/// Cleaned, validated multi-segment route representation used by both UI/playback and unit tests.
/// Preserves disjoint `<trkseg>` boundaries so unrelated GPX segments are never connected by a fake line.
public struct RoutePlaybackPlan: Equatable {
    public let coordinateSegments: [[CLLocationCoordinate2D]]
    public let edges: [RouteEdge]
    public let suffixDistances: [Double] // suffixDistances[i] = sum of edge distances for i..<edges.count
    public let totalDistance: Double
    public let flattenedCoordinates: [CLLocationCoordinate2D]

    public var isPlayable: Bool { !edges.isEmpty }
    public var startCoordinate: CLLocationCoordinate2D? {
        edges.first?.start ?? coordinateSegments.first?.first
    }
    public var endCoordinate: CLLocationCoordinate2D? {
        edges.last?.end ?? coordinateSegments.last?.last
    }

    public init(coordinates: [CLLocationCoordinate2D]) {
        self.init(coordinateSegments: [coordinates])
    }

    public init(coordinateSegments rawSegments: [[CLLocationCoordinate2D]]) {
        var cleanedSegments: [[CLLocationCoordinate2D]] = []
        var builtEdges: [RouteEdge] = []

        for rawSegment in rawSegments {
            let validPoints = rawSegment.filter { RouteSimulationEngine.isValidCoordinate($0) }
            guard !validPoints.isEmpty else { continue }

            var deduped: [CLLocationCoordinate2D] = [validPoints[0]]
            for pt in validPoints.dropFirst() {
                if let prev = deduped.last {
                    let dist = RouteSimulationEngine.haversineDistance(from: prev, to: pt)
                    if dist >= 1e-3 {
                        deduped.append(pt)
                    }
                }
            }

            let trackSegIdx = cleanedSegments.count
            cleanedSegments.append(deduped)

            guard deduped.count >= 2 else { continue }
            for i in 0..<(deduped.count - 1) {
                let p0 = deduped[i]
                let p1 = deduped[i + 1]
                let dist = RouteSimulationEngine.haversineDistance(from: p0, to: p1)
                guard dist >= 1e-3 else { continue }
                let bearing = RouteSimulationEngine.greatCircleBearing(from: p0, to: p1)
                builtEdges.append(RouteEdge(
                    start: p0,
                    end: p1,
                    trackSegmentIndex: trackSegIdx,
                    localStartPointIndex: i,
                    distanceMeters: dist,
                    bearingDegrees: bearing
                ))
            }
        }

        // Compute suffix sums indexed by edge index (size edges.count + 1)
        var suffixes = [Double](repeating: 0.0, count: builtEdges.count + 1)
        for i in stride(from: builtEdges.count - 1, through: 0, by: -1) {
            suffixes[i] = suffixes[i + 1] + builtEdges[i].distanceMeters
        }

        self.coordinateSegments = cleanedSegments
        self.edges = builtEdges
        self.suffixDistances = suffixes
        self.totalDistance = suffixes.first ?? 0.0
        self.flattenedCoordinates = cleanedSegments.flatMap { $0 }
    }

    public static func == (lhs: RoutePlaybackPlan, rhs: RoutePlaybackPlan) -> Bool {
        lhs.edges == rhs.edges && lhs.totalDistance == rhs.totalDistance
    }
}

/// Output of advancing `RoutePlaybackState` for one simulation tick.
public struct RouteStepResult {
    public let coordinate: CLLocationCoordinate2D
    public let headingDegrees: Double
    public let upcomingTurnAngleDegrees: Double
    public let activeEdgeIndex: Int
    public let trackSegmentIndex: Int
    public let distanceInActiveEdge: Double
    public let remainingDistanceMeters: Double
    public let progress: Double
    public let reachedEnd: Bool
    public let jumpedSegmentDiscontinuity: Bool
    public let completedSegments: [[CLLocationCoordinate2D]]
    public let remainingSegments: [[CLLocationCoordinate2D]]

    public var completedCoordinates: [CLLocationCoordinate2D] {
        completedSegments.flatMap { $0 }
    }

    public var remainingCoordinates: [CLLocationCoordinate2D] {
        remainingSegments.flatMap { $0 }
    }
}

/// Pure, deterministic route progression state machine.
/// Fixes segment-transition staleness by evaluating `p0`, `p1`, heading, turn angle,
/// and Great Circle fraction strictly AFTER advancing across zero, one, or multiple edges.
public struct RoutePlaybackState {
    public let plan: RoutePlaybackPlan
    public private(set) var currentEdgeIndex: Int = 0
    public private(set) var distanceInCurrentEdge: Double = 0.0
    public private(set) var isFinished: Bool = false

    public init(plan: RoutePlaybackPlan) {
        self.plan = plan
        self.isFinished = !plan.isPlayable
    }

    public mutating func resetForLoop() {
        currentEdgeIndex = 0
        distanceInCurrentEdge = 0.0
        isFinished = !plan.isPlayable
    }

    /// Heading (degrees) for the currently active edge.
    public var currentHeadingDegrees: Double {
        guard !plan.edges.isEmpty else { return 0.0 }
        let idx = min(currentEdgeIndex, plan.edges.count - 1)
        return plan.edges[idx].bearingDegrees
    }

    /// Upcoming corner turn angle (degrees) at the end of the currently active edge,
    /// returning 0 when approaching the final destination or a GPX track-segment break.
    public var upcomingTurnAngleDegrees: Double {
        guard currentEdgeIndex + 1 < plan.edges.count else { return 0.0 }
        let cur = plan.edges[currentEdgeIndex]
        let next = plan.edges[currentEdgeIndex + 1]
        guard cur.trackSegmentIndex == next.trackSegmentIndex else { return 0.0 }
        return RouteSimulationEngine.turnAngleBetween(bearing1: cur.bearingDegrees, bearing2: next.bearingDegrees)
    }

    /// Exact coordinate for the current state.
    public var currentCoordinate: CLLocationCoordinate2D {
        guard !plan.edges.isEmpty else {
            return plan.startCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        let edge = plan.edges[min(currentEdgeIndex, plan.edges.count - 1)]
        if isFinished && currentEdgeIndex == plan.edges.count - 1 {
            return edge.end
        }
        let t = edge.distanceMeters > 1e-6 ? min(1.0, max(0.0, distanceInCurrentEdge / edge.distanceMeters)) : 1.0
        return RouteSimulationEngine.interpolateGreatCircle(from: edge.start, to: edge.end, fraction: t)
    }

    /// Advances playback along the route by `stepMeters`, crossing as many edges as needed
    /// and interpolating along the active post-transition edge.
    public mutating func advance(byMeters stepMeters: Double) -> RouteStepResult {
        guard !plan.edges.isEmpty else {
            let fallback = plan.endCoordinate ?? plan.startCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            isFinished = true
            return RouteStepResult(
                coordinate: fallback,
                headingDegrees: 0.0,
                upcomingTurnAngleDegrees: 0.0,
                activeEdgeIndex: 0,
                trackSegmentIndex: 0,
                distanceInActiveEdge: 0.0,
                remainingDistanceMeters: 0.0,
                progress: 1.0,
                reachedEnd: true,
                jumpedSegmentDiscontinuity: false,
                completedSegments: plan.coordinateSegments,
                remainingSegments: []
            )
        }

        let startTrackSegment = plan.edges[min(currentEdgeIndex, plan.edges.count - 1)].trackSegmentIndex
        var remainingStep = (stepMeters.isFinite && stepMeters > 0.0) ? stepMeters : 0.0
        var reachedEnd = isFinished

        if !reachedEnd {
            while remainingStep > 0.0 {
                let edge = plan.edges[currentEdgeIndex]
                let remainingInEdge = max(0.0, edge.distanceMeters - distanceInCurrentEdge)

                if remainingStep < remainingInEdge {
                    distanceInCurrentEdge += remainingStep
                    remainingStep = 0.0
                } else {
                    remainingStep -= remainingInEdge
                    if currentEdgeIndex < plan.edges.count - 1 {
                        currentEdgeIndex += 1
                        distanceInCurrentEdge = 0.0
                    } else {
                        currentEdgeIndex = plan.edges.count - 1
                        distanceInCurrentEdge = edge.distanceMeters
                        remainingStep = 0.0
                        reachedEnd = true
                        break
                    }
                }
            }
        }

        isFinished = reachedEnd
        let activeEdge = plan.edges[currentEdgeIndex]
        let t = (reachedEnd && currentEdgeIndex == plan.edges.count - 1)
            ? 1.0
            : (activeEdge.distanceMeters > 1e-6 ? min(1.0, max(0.0, distanceInCurrentEdge / activeEdge.distanceMeters)) : 1.0)

        let coord: CLLocationCoordinate2D
        if t >= 1.0 {
            coord = activeEdge.end
        } else if t <= 0.0 {
            coord = activeEdge.start
        } else {
            coord = RouteSimulationEngine.interpolateGreatCircle(from: activeEdge.start, to: activeEdge.end, fraction: t)
        }

        let remainingInEdge = max(0.0, activeEdge.distanceMeters - distanceInCurrentEdge)
        let trailingSuffix = (currentEdgeIndex + 1 < plan.suffixDistances.count) ? plan.suffixDistances[currentEdgeIndex + 1] : 0.0
        let remainingDistance = reachedEnd ? 0.0 : max(0.0, remainingInEdge + trailingSuffix)
        let progress = plan.totalDistance > 0.0
            ? min(1.0, max(0.0, 1.0 - (remainingDistance / plan.totalDistance)))
            : 1.0

        let turnAngle = upcomingTurnAngleDegrees
        let jumpedSegment = activeEdge.trackSegmentIndex != startTrackSegment

        let (completedSegs, remainingSegs) = buildSegmentSlices(
            activeEdge: activeEdge,
            interpolatedCoord: coord,
            reachedEnd: reachedEnd
        )

        return RouteStepResult(
            coordinate: coord,
            headingDegrees: activeEdge.bearingDegrees,
            upcomingTurnAngleDegrees: turnAngle,
            activeEdgeIndex: currentEdgeIndex,
            trackSegmentIndex: activeEdge.trackSegmentIndex,
            distanceInActiveEdge: distanceInCurrentEdge,
            remainingDistanceMeters: remainingDistance,
            progress: progress,
            reachedEnd: reachedEnd,
            jumpedSegmentDiscontinuity: jumpedSegment,
            completedSegments: completedSegs,
            remainingSegments: remainingSegs
        )
    }

    private func buildSegmentSlices(
        activeEdge: RouteEdge,
        interpolatedCoord: CLLocationCoordinate2D,
        reachedEnd: Bool
    ) -> (completed: [[CLLocationCoordinate2D]], remaining: [[CLLocationCoordinate2D]]) {
        var completed: [[CLLocationCoordinate2D]] = []
        var remaining: [[CLLocationCoordinate2D]] = []

        for (segIdx, segment) in plan.coordinateSegments.enumerated() {
            guard !segment.isEmpty else { continue }
            if segIdx < activeEdge.trackSegmentIndex {
                completed.append(segment)
            } else if segIdx > activeEdge.trackSegmentIndex {
                if !reachedEnd {
                    remaining.append(segment)
                } else {
                    completed.append(segment)
                }
            } else {
                if reachedEnd && segIdx == plan.coordinateSegments.count - 1 {
                    completed.append(segment)
                } else {
                    let prefixEnd = min(activeEdge.localStartPointIndex, segment.count - 1)
                    var compSeg = Array(segment[0...prefixEnd])
                    if let last = compSeg.last,
                       RouteSimulationEngine.haversineDistance(from: last, to: interpolatedCoord) >= 1e-3 {
                        compSeg.append(interpolatedCoord)
                    }
                    completed.append(compSeg)

                    let suffixStart = activeEdge.localStartPointIndex + 1
                    if suffixStart < segment.count {
                        var remSeg = [interpolatedCoord]
                        remSeg.append(contentsOf: segment[suffixStart...])
                        remaining.append(remSeg)
                    } else {
                        remaining.append([interpolatedCoord])
                    }
                }
            }
        }
        return (completed, remaining)
    }
}

/// Thread-safe session token and single-cleanup lifecycle coordinator for active route tasks.
/// Prevents cancelled or superseded tasks from mutating newer route state or firing completion celebrations.
public final class RoutePlaybackSessionController: @unchecked Sendable {
    private let lock = NSLock()
    private var activeSessionID: UUID?
    private var uncleanedSessions: Set<UUID> = []
    private var completedSessions: Set<UUID> = []

    public init() {}

    /// Starts a new route session and invalidates any previously active session.
    /// Returns `(newID, supersededSessionIDToCleanup)` so callers can clean up old state at most once.
    @discardableResult
    public func beginNewSession() -> (sessionID: UUID, previousNeedingCleanup: UUID?) {
        lock.lock()
        defer { lock.unlock() }
        let prevToCleanup: UUID?
        if let prev = activeSessionID, uncleanedSessions.remove(prev) != nil {
            prevToCleanup = prev
        } else {
            prevToCleanup = nil
        }
        let nextID = UUID()
        activeSessionID = nextID
        uncleanedSessions.insert(nextID)
        // Bound tracked history to avoid unbounded growth across hundreds of start/stops
        if completedSessions.count > 256 {
            completedSessions.removeAll()
        }
        if uncleanedSessions.count > 256 {
            uncleanedSessions = [nextID]
        }
        return (nextID, prevToCleanup)
    }

    /// Returns true strictly if `sessionID` is still the current active session and not cancelled.
    public func isActive(_ sessionID: UUID, taskCancelled: Bool = Task.isCancelled) -> Bool {
        guard !taskCancelled else { return false }
        lock.lock()
        defer { lock.unlock() }
        return activeSessionID == sessionID
    }

    /// Stops the active session synchronously, claiming cleanup ownership so background tasks cannot double-clean.
    @discardableResult
    public func stopActiveSession() -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard let current = activeSessionID else { return nil }
        activeSessionID = nil
        return uncleanedSessions.remove(current)
    }

    /// Attempts to claim normal route completion for `sessionID`.
    /// Returns true ONLY if `sessionID` is still active, was not cancelled, and has not already been cleaned or completed.
    public func claimCompletion(for sessionID: UUID, taskCancelled: Bool = Task.isCancelled) -> Bool {
        guard !taskCancelled else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard activeSessionID == sessionID,
              !completedSessions.contains(sessionID),
              uncleanedSessions.contains(sessionID) else {
            return false
        }
        completedSessions.insert(sessionID)
        uncleanedSessions.remove(sessionID)
        activeSessionID = nil
        return true
    }

    /// Claims cleanup ownership for `sessionID`, returning true at most once per session.
    public func claimCleanup(for sessionID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if activeSessionID == sessionID {
            activeSessionID = nil
        }
        return uncleanedSessions.remove(sessionID) != nil
    }

    public var currentSessionID: UUID? {
        lock.lock()
        defer { lock.unlock() }
        return activeSessionID
    }
}

