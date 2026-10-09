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

    private static let earthRadiusMeters: Double = 6371008.8

    /// High-precision Haversine Great Circle distance between two coordinates in meters.
    public static func haversineDistance(from c1: CLLocationCoordinate2D, to c2: CLLocationCoordinate2D) -> CLLocationDistance {
        let lat1 = c1.latitude * .pi / 180.0
        let lat2 = c2.latitude * .pi / 180.0
        let dLat = (c2.latitude - c1.latitude) * .pi / 180.0
        let dLon = (c2.longitude - c1.longitude) * .pi / 180.0

        let a = sin(dLat / 2.0) * sin(dLat / 2.0) +
                cos(lat1) * cos(lat2) * sin(dLon / 2.0) * sin(dLon / 2.0)
        let c = 2.0 * atan2(sqrt(a), sqrt(max(0.0, 1.0 - a)))
        return earthRadiusMeters * c
    }

    /// Mathematical forward azimuth (course/heading degrees: 0° North, 90° East, 180° South, 270° West).
    public static func greatCircleBearing(from c1: CLLocationCoordinate2D, to c2: CLLocationCoordinate2D) -> Double {
        let lat1 = c1.latitude * .pi / 180.0
        let lat2 = c2.latitude * .pi / 180.0
        let dLon = (c2.longitude - c1.longitude) * .pi / 180.0

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = (radians * 180.0 / .pi).truncatingRemainder(dividingBy: 360.0)
        return degrees >= 0 ? degrees : degrees + 360.0
    }

    /// Great Circle spherical linear interpolation (Slerp) along the Earth's geodesic arc.
    public static func interpolateGreatCircle(
        from c1: CLLocationCoordinate2D,
        to c2: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        let t = min(1.0, max(0.0, fraction))
        if t <= 0.00001 { return c1 }
        if t >= 0.99999 { return c2 }

        let lat1 = c1.latitude * .pi / 180.0
        let lon1 = c1.longitude * .pi / 180.0
        let lat2 = c2.latitude * .pi / 180.0
        let lon2 = c2.longitude * .pi / 180.0

        let delta = haversineDistance(from: c1, to: c2) / earthRadiusMeters
        if delta < 1e-8 { return c1 }

        let sinDelta = sin(delta)
        let a = sin((1.0 - t) * delta) / sinDelta
        let b = sin(t * delta) / sinDelta

        let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)

        let outLat = atan2(z, sqrt(x * x + y * y))
        let outLon = atan2(y, x)

        return CLLocationCoordinate2D(
            latitude: outLat * 180.0 / .pi,
            longitude: outLon * 180.0 / .pi
        )
    }

    /// Computes the angle difference in degrees between two bearings (0...180).
    public static func turnAngleBetween(bearing1: Double, bearing2: Double) -> Double {
        let diff = abs(bearing1 - bearing2).truncatingRemainder(dividingBy: 360.0)
        return diff > 180 ? 360 - diff : diff
    }

    // MARK: - Dynamic Speed Profiler & Kinematics

    /// Updates velocity using realistic physics curves (acceleration, corner braking, and random variance).
    public func computeNextSpeed(
        baseSpeedMPS: Double,
        travelMode: TravelMode,
        turnAngleDegrees: Double,
        elapsedSeconds: Double
    ) -> Double {
        let dt = max(0.1, min(2.0, elapsedSeconds))

        // 1. Turn-adaptive speed scaling (real vehicles slow down on turns)
        var targetMPS = baseSpeedMPS
        if travelMode == .drive || travelMode == .bus {
            if turnAngleDegrees > 60 {
                // Hard 60-90° turn: slow down to ~15–18 mph (6.7–8.0 m/s)
                let turnCornerSpeedMPS = min(targetMPS, 7.5)
                targetMPS = turnCornerSpeedMPS
            } else if turnAngleDegrees > 30 {
                // Moderate turn: slow down to ~22 mph (9.8 m/s)
                let moderateTurnSpeedMPS = min(targetMPS, 9.8)
                targetMPS = moderateTurnSpeedMPS
            }
        }

        // 2. Realistic Dynamic Random Speed Fluctuation within 1–5 mph range
        if enableRandomSpeedFluctuations {
            let maxVarianceMPH = min(5.0, max(1.0, speedVarianceRangeMPH))
            // Dynamic driver throttle wave with organic Brownian perturbation
            throttlePhase += dt * 0.45
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
            let cadenceFactor = 1.0 + (sin(stepCadencePhase) * 0.04)
            currentFilteredSpeedMPS *= cadenceFactor
            // Strictly guard walking at 1–2 mph (0.45–0.90 m/s)
            currentFilteredSpeedMPS = min(0.95, max(0.42, currentFilteredSpeedMPS))
        }

        return max(0.4, currentFilteredSpeedMPS)
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
        lastValidHeading = headingDegrees
        let speedMPH = speedMPS * 2.236936

        guard enableGPSJitter else {
            return TelemetryPayload(
                coordinate: rawCoordinate,
                rawCoordinate: rawCoordinate,
                speedMPS: speedMPS,
                speedMPH: speedMPH,
                courseDegrees: headingDegrees,
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

        let headingRad = headingDegrees * .pi / 180.0
        let alongMeters = totalAlong + microAlong
        let crossMeters = totalCross + microCross

        let eastMeters = (alongMeters * sin(headingRad)) + (crossMeters * cos(headingRad))
        let northMeters = (alongMeters * cos(headingRad)) - (crossMeters * sin(headingRad))

        let dLat = (northMeters / Self.earthRadiusMeters) * (180.0 / .pi)
        let dLon = (eastMeters / (Self.earthRadiusMeters * cos(rawCoordinate.latitude * .pi / 180.0))) * (180.0 / .pi)

        let jitteredCoordinate = CLLocationCoordinate2D(
            latitude: rawCoordinate.latitude + dLat,
            longitude: rawCoordinate.longitude + dLon
        )

        // Realistic horizontal accuracy (varies smoothly between 4.2m and 6.8m)
        let horizAcc = 5.0 + Double.random(in: -0.7...1.2)
        let vertAcc = 3.8 + Double.random(in: -0.5...0.9)

        return TelemetryPayload(
            coordinate: jitteredCoordinate,
            rawCoordinate: rawCoordinate,
            speedMPS: speedMPS,
            speedMPH: speedMPH,
            courseDegrees: headingDegrees,
            horizontalAccuracy: horizAcc,
            verticalAccuracy: vertAcc,
            stateTitle: stateTitle
        )
    }
}
