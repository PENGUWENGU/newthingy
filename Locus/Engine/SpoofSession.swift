import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UIKit
import UserNotifications

// TravelMode, SpeedInput, and SpeedPreference live in TravelMode.swift so the GPX/route
// sampling code (RouteBuilder.swift) and the speed-validation logic can be unit tested
// without pulling in this file's UIKit/idevice-linked dependencies.

enum SpoofStatus: Equatable {
    case idle
    case connecting
    case active
    case reconnecting
    case dropped(String)

    var label: String {
        switch self {
        case .idle: return "Not Spoofing"
        case .connecting: return "Starting…"
        case .active: return "Spoofing"
        case .reconnecting: return "Reconnecting…"
        case .dropped: return "Interrupted"
        }
    }

    var isDropped: Bool {
        if case .dropped = self { return true }
        return false
    }
}

/// Statistics for a completed route to display in the post-route celebration card.
struct RouteCompletionStats: Identifiable {
    let id = UUID()
    let destinationName: String
    let totalDistanceMeters: CLLocationDistance
    let durationSeconds: TimeInterval
    let stopsVisited: Int

    var formattedDistance: String {
        RouteBuilder.formattedDistance(totalDistanceMeters)
    }

    var formattedDuration: String {
        let total = Int(durationSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

@MainActor
final class SpoofSession: ObservableObject {
    @Published var status: SpoofStatus = .idle
    @Published var pin: CLLocationCoordinate2D?
    @Published var simulated: CLLocationCoordinate2D?
    @Published var travelMode: TravelMode = .walk
    @Published var customSpeedMPS: Double?
    @Published var speedUnit: SpeedUnit = SpeedPreference.preferredUnit
    @Published var mapStyleIndex: Int = 0
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var joystickActive = false
    @Published var isFollowingRoute = false
    @Published var isRoutePaused = false
    @Published var routeProgress: Double = 0.0
    @Published var remainingRouteDistance: CLLocationDistance = 0.0
    @Published var remainingRouteDuration: TimeInterval = 0.0
    @Published var completedRouteCoordinates: [CLLocationCoordinate2D] = []
    @Published var remainingRouteCoordinates: [CLLocationCoordinate2D] = []
    @Published var activeStopName: String? = nil
    @Published var activeStopRemainingSeconds: Double? = nil
    @Published var isTrafficLightStopActive: Bool = false
    @Published var isBusStopActive: Bool = false
    @Published var routeDestinationName: String = ""
    @Published var routeFinishedFlash: Bool = false
    @Published var routeCompletionSummary: RouteCompletionStats? = nil
    @Published var activeRouteTotalDistance: CLLocationDistance = 0.0
    @Published var activeRouteWaypoints: [RouteWaypoint] = []

    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []
    @Published var savedRoutes: [SavedRoute] = []
    @Published var defaultConnectionType: RouteConnectionType = RouteConnectionPreference.defaultType
    @Published var accentTheme: AccentColorTheme = ThemePreference.accent
    @Published var pathWidth: PathWidthPreference = ThemePreference.pathWidth
    @Published var uiAppearance: UIAppearanceStyle = ThemePreference.appearance
    @Published var showWaypointLabels: Bool = ThemePreference.showWaypointLabels
    @Published var themeVersion: Int = 0

    // Live Activities & Location Realism
    @Published var liveActivitiesEnabled: Bool = (UserDefaults.standard.object(forKey: "locus.liveActivitiesEnabled") as? Bool) ?? true
    @Published var life360RealismEnabled: Bool = (UserDefaults.standard.object(forKey: "locus.life360Realism") as? Bool) ?? true
    @Published var stationaryDriftEnabled: Bool = (UserDefaults.standard.object(forKey: "locus.stationaryDrift") as? Bool) ?? true

    // Dynamic Theme Color Observables (Instant live updates)
    @Published var customPrimaryHex: String = ThemePreference.customPrimaryHex
    @Published var customSecondaryHex: String = ThemePreference.customSecondaryHex
    @Published var customTextColorHex: String = ThemePreference.customTextColorHex
    @Published var isCustomTextColorEnabled: Bool = ThemePreference.isCustomTextColorEnabled
    @Published var customMenuTintHex: String = ThemePreference.customMenuTintHex
    @Published var isMenuTintEnabled: Bool = ThemePreference.isMenuTintEnabled
    @Published var glassTintHex: String = ThemePreference.glassTintHex
    @Published var isGlassTintEnabled: Bool = ThemePreference.isGlassTintEnabled
    @Published var completionFlashHex: String = ThemePreference.completionFlashHex

    // Smart Routing & Simulation Behavior Toggles
    @Published var isBusModeActive: Bool = false
    @Published var isCarModeActive: Bool = false
    @Published var busModeSmartStops: Bool = true
    @Published var smartTrafficLights: Bool = true
    @Published var routeNotificationsEnabled: Bool = true

    var primaryAccentColor: Color {
        accentTheme == .custom ? (Color(hex: customPrimaryHex) ?? accentTheme.primaryColor) : accentTheme.primaryColor
    }

    var secondaryAccentColor: Color {
        accentTheme == .custom ? (Color(hex: customSecondaryHex) ?? accentTheme.secondaryColor) : accentTheme.secondaryColor
    }

    var effectiveTextColor: Color {
        if isCustomTextColorEnabled, let color = Color(hex: customTextColorHex) {
            return color
        }
        return .primary
    }

    var effectiveMenuTint: Color? {
        if isMenuTintEnabled, let color = Color(hex: customMenuTintHex) {
            return color
        }
        if isGlassTintEnabled, let color = Color(hex: glassTintHex) {
            return color
        }
        return nil
    }

    var effectiveGlassTint: Color? {
        if isGlassTintEnabled, let color = Color(hex: glassTintHex) {
            return color
        }
        return nil
    }

    var effectiveCompletionFlashColor: Color {
        if let color = Color(hex: completionFlashHex) {
            return color
        }
        return Color(red: 0.20, green: 0.83, blue: 0.60)
    }

    private var resendTimer: Timer?
    private var healthTimer: Timer?
    private var joystickTimer: Timer?
    private var routeTask: Task<Void, Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var joystickVector: CGVector = .zero
    private let locationKeeper = BackgroundKeepAlive()
    private var skipCurrentStopRequested = false
    private var smoothedVelocityMPS: Double = 0.0
    private var cumulativeDriftEast: Double = 0.0
    private var cumulativeDriftNorth: Double = 0.0

    private let favoritesKey = "locus.favorites"
    private let recentsKey = "locus.recents"
    private let savedRoutesKey = "locus.saved_routes"

    init() {
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
        savedRoutes = SavedRoute.load(key: savedRoutesKey)
        defaultConnectionType = RouteConnectionPreference.defaultType
        accentTheme = ThemePreference.accent
        pathWidth = ThemePreference.pathWidth
        uiAppearance = ThemePreference.appearance
        showWaypointLabels = ThemePreference.showWaypointLabels
        customSpeedMPS = SpeedPreference.storedValue
        customPrimaryHex = ThemePreference.customPrimaryHex
        customSecondaryHex = ThemePreference.customSecondaryHex
        customTextColorHex = ThemePreference.customTextColorHex
        isCustomTextColorEnabled = ThemePreference.isCustomTextColorEnabled
        customMenuTintHex = ThemePreference.customMenuTintHex
        isMenuTintEnabled = ThemePreference.isMenuTintEnabled
        glassTintHex = ThemePreference.glassTintHex
        isGlassTintEnabled = ThemePreference.isGlassTintEnabled
        completionFlashHex = ThemePreference.completionFlashHex
    }

    func setDefaultConnectionType(_ type: RouteConnectionType) {
        defaultConnectionType = type
        RouteConnectionPreference.defaultType = type
    }

    func setAccentTheme(_ theme: AccentColorTheme) {
        accentTheme = theme
        ThemePreference.accent = theme
        themeVersion += 1
        objectWillChange.send()
    }

    func setCustomPrimaryHex(_ hex: String) {
        customPrimaryHex = hex
        ThemePreference.customPrimaryHex = hex
        accentTheme = .custom
        ThemePreference.accent = .custom
        themeVersion += 1
        objectWillChange.send()
    }

    func setCustomSecondaryHex(_ hex: String) {
        customSecondaryHex = hex
        ThemePreference.customSecondaryHex = hex
        accentTheme = .custom
        ThemePreference.accent = .custom
        themeVersion += 1
        objectWillChange.send()
    }

    func updateCustomColors(
        primaryHex: String? = nil,
        secondaryHex: String? = nil,
        textColorHex: String? = nil,
        menuTintHex: String? = nil,
        glassTintHex: String? = nil,
        flashHex: String? = nil
    ) {
        if let primaryHex {
            self.customPrimaryHex = primaryHex
            ThemePreference.customPrimaryHex = primaryHex
            self.accentTheme = .custom
            ThemePreference.accent = .custom
        }
        if let secondaryHex {
            self.customSecondaryHex = secondaryHex
            ThemePreference.customSecondaryHex = secondaryHex
            self.accentTheme = .custom
            ThemePreference.accent = .custom
        }
        if let textColorHex {
            self.customTextColorHex = textColorHex
            self.isCustomTextColorEnabled = true
            ThemePreference.customTextColorHex = textColorHex
            ThemePreference.isCustomTextColorEnabled = true
        }
        if let menuTintHex {
            self.customMenuTintHex = menuTintHex
            self.isMenuTintEnabled = true
            ThemePreference.customMenuTintHex = menuTintHex
            ThemePreference.isMenuTintEnabled = true
        }
        if let glassTintHex {
            self.glassTintHex = glassTintHex
            self.isGlassTintEnabled = true
            ThemePreference.glassTintHex = glassTintHex
            ThemePreference.hasCustomGlassTint = true
        }
        if let flashHex {
            self.completionFlashHex = flashHex
            ThemePreference.completionFlashHex = flashHex
        }
        self.themeVersion += 1
        self.objectWillChange.send()
    }

    func setPathWidth(_ width: PathWidthPreference) {
        pathWidth = width
        ThemePreference.pathWidth = width
    }

    func setUIAppearance(_ style: UIAppearanceStyle) {
        uiAppearance = style
        ThemePreference.appearance = style
    }

    func setShowWaypointLabels(_ show: Bool) {
        showWaypointLabels = show
        ThemePreference.showWaypointLabels = show
    }

    var isSpoofing: Bool {
        if case .active = status { return true }
        if case .reconnecting = status { return true }
        return false
    }

    /// The single source of truth for movement speed (meters per second). Joystick
    /// ticking and route/GPX playback both read this instead of `travelMode.baseSpeed`
    /// directly, so a custom speed applies consistently everywhere motion happens.
    /// `travelMode` still independently decides the road-routing transport type
    /// (walking vs. driving directions) — that's unaffected by a custom speed.
    var currentSpeedMPS: CLLocationSpeed {
        customSpeedMPS ?? travelMode.baseSpeed
    }

    /// Switches travel mode and clears any custom speed override so the new mode's speed is used immediately.
    func selectTravelMode(_ mode: TravelMode) {
        travelMode = mode
        customSpeedMPS = nil
        SpeedPreference.setCustomSpeed(nil)
        updateRemainingRouteDuration()
        objectWillChange.send()
    }

    /// Sets the user's preferred speed unit (mph, km/h, m/s).
    func setSpeedUnit(_ unit: SpeedUnit) {
        speedUnit = unit
        SpeedPreference.preferredUnit = unit
        objectWillChange.send()
    }

    /// Recalculates estimated remaining route duration when speed is changed during route playback.
    func updateRemainingRouteDuration() {
        guard isFollowingRoute else { return }
        let travel = RouteBuilder.estimatedDuration(distance: remainingRouteDistance, speed: currentSpeedMPS)
        let dwellLeft = activeStopRemainingSeconds ?? 0
        remainingRouteDuration = travel + dwellLeft
    }

    /// Validates and applies a custom speed typed by the user in the selected speed unit.
    @discardableResult
    func setCustomSpeed(fromText text: String, unit: SpeedUnit? = nil) -> Bool {
        let u = unit ?? speedUnit
        guard let value = SpeedInput.parse(text, unit: u) else { return false }
        customSpeedMPS = value
        SpeedPreference.setCustomSpeed(value)
        updateRemainingRouteDuration()
        objectWillChange.send()
        return true
    }

    /// Clears any custom speed override, reverting to the selected travel mode's preset.
    func clearCustomSpeed() {
        customSpeedMPS = nil
        SpeedPreference.setCustomSpeed(nil)
        updateRemainingRouteDuration()
        objectWillChange.send()
    }

    func dismissCompletionSummary() {
        SoundManager.play(.tap)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            routeCompletionSummary = nil
        }
    }

    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Import an RPPairing file in Settings first."
            return
        }
        pin = coordinate
        apply(coordinate, pairing: pairing, markRecent: true)
    }

    func stop(pairing: PairingStore) {
        stopRoute()
        stopJoystick()
        stopResend()
        stopHealth()
        isBusy = true
        let result = LocationEngine.clear()
        isBusy = false
        switch result {
        case .success:
            simulated = nil
            status = .idle
            endBackground()
            // Keep location updates running so the map puck / locate button
            // can return to the real GPS fix (not the leftover pin).
            locationKeeper.start()
        case .failure(let error):
            lastError = error.localizedDescription
            status = .dropped(error.localizedDescription)
            postDropNotification(error.localizedDescription)
        }
    }

    func stopRoute() {
        routeTask?.cancel()
        routeTask = nil
        isFollowingRoute = false
        isRoutePaused = false
        routeProgress = 0.0
        remainingRouteDistance = 0.0
        remainingRouteDuration = 0.0
        completedRouteCoordinates = []
        remainingRouteCoordinates = []
        activeStopName = nil
        activeStopRemainingSeconds = nil
        skipCurrentStopRequested = false
        if liveActivitiesEnabled {
            LiveActivityManager.shared.endActivity(destinationName: routeDestinationName)
        }
    }

    func pauseRoute() {
        guard isFollowingRoute && !isRoutePaused else { return }
        isRoutePaused = true
        if liveActivitiesEnabled {
            LiveActivityManager.shared.updateActivity(
                progress: routeProgress,
                remainingDistanceMeters: remainingRouteDistance,
                remainingDurationSeconds: remainingRouteDuration,
                destinationName: routeDestinationName,
                travelMode: travelMode,
                speedFormatted: speedUnit.format(currentSpeedMPS),
                activeStopName: activeStopName,
                isPaused: true
            )
        }
    }

    func resumeRoute() {
        guard isFollowingRoute && isRoutePaused else { return }
        isRoutePaused = false
        if liveActivitiesEnabled {
            LiveActivityManager.shared.updateActivity(
                progress: routeProgress,
                remainingDistanceMeters: remainingRouteDistance,
                remainingDurationSeconds: remainingRouteDuration,
                destinationName: routeDestinationName,
                travelMode: travelMode,
                speedFormatted: speedUnit.format(currentSpeedMPS),
                activeStopName: activeStopName,
                isPaused: false
            )
        }
    }

    func togglePauseRoute() {
        if isRoutePaused {
            resumeRoute()
        } else {
            pauseRoute()
        }
    }

    func skipCurrentStop() {
        skipCurrentStopRequested = true
    }

    func skipStop() {
        skipCurrentStop()
    }

    /// Best-known real device coordinate (not the teleport pin).
    var realCoordinate: CLLocationCoordinate2D? {
        locationKeeper.lastKnownCoordinate
    }

    /// Start lightweight GPS updates for the map puck / locate button.
    func startLocationUpdates() {
        locationKeeper.start()
    }

    func startJoystick(pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Import an RPPairing file in Settings first."
            return
        }
        stopRoute()
        let start = simulated ?? pin ?? locationKeeper.lastKnownCoordinate
        guard let start else {
            lastError = "Drop a pin or teleport somewhere before using the joystick."
            return
        }
        if simulated == nil {
            apply(start, pairing: pairing, markRecent: false)
        }
        joystickActive = true
        joystickTimer?.invalidate()
        joystickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickJoystick(pairing: pairing)
            }
        }
    }

    func updateJoystick(vector: CGVector) {
        joystickVector = vector
    }

    func stopJoystick() {
        joystickActive = false
        joystickVector = .zero
        joystickTimer?.invalidate()
        joystickTimer = nil
    }

    func followRoute(
        _ coordinates: [CLLocationCoordinate2D],
        waypoints: [RouteWaypoint] = [],
        destinationName: String = "",
        pairing: PairingStore,
        loop: Bool = false
    ) {
        guard pairing.hasPairingFile, coordinates.count >= 2 else { return }
        routeTask?.cancel()
        stopJoystick()
        isFollowingRoute = true
        isRoutePaused = false
        routeProgress = 0.0
        activeStopName = nil
        activeStopRemainingSeconds = nil
        isTrafficLightStopActive = false
        isBusStopActive = false
        skipCurrentStopRequested = false
        routeDestinationName = destinationName.isEmpty ? (waypoints.last?.name ?? "Destination") : destinationName
        activeRouteWaypoints = waypoints

        let totalRouteDistance = RouteBuilder.totalDistance(of: coordinates)
        activeRouteTotalDistance = totalRouteDistance
        remainingRouteDistance = totalRouteDistance
        let travelDuration = RouteBuilder.estimatedDuration(distance: totalRouteDistance, speed: currentSpeedMPS)
        let totalStopsDuration = waypoints.reduce(0) { $0 + $1.stopDuration }
        remainingRouteDuration = travelDuration + totalStopsDuration

        // Request notification permission for route completion alert if needed
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        // Precompute cumulative suffix distances to quickly compute accurate remaining distance
        var suffixDistances = [CLLocationDistance](repeating: 0, count: coordinates.count)
        for i in (0..<(coordinates.count - 1)).reversed() {
            let seg = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
                .distance(from: CLLocation(latitude: coordinates[i + 1].latitude, longitude: coordinates[i + 1].longitude))
            suffixDistances[i] = suffixDistances[i + 1] + seg
        }

        let definedStops = waypoints.filter { $0.stopDuration > 0 }
        let routeStartTime = Date()

        if liveActivitiesEnabled {
            LiveActivityManager.shared.startActivity(
                destinationName: routeDestinationName,
                travelMode: travelMode,
                speedFormatted: speedUnit.format(currentSpeedMPS),
                initialRemainingSeconds: remainingRouteDuration,
                routeDistanceMeters: totalRouteDistance
            )
        }

        routeTask = Task { [weak self] in
            guard let self else { return }
            var shouldContinue = true
            var distanceSinceLastLight: Double = 0
            var distanceSinceLastBusStop: Double = 0
            var cumulativeDistanceTraveled: Double = 0

            while shouldContinue && !Task.isCancelled {
                var pendingStops = definedStops
                var previous = coordinates[0]
                await MainActor.run {
                    self.apply(previous, pairing: pairing, markRecent: true)
                    self.routeProgress = 0.0
                    self.remainingRouteDistance = totalRouteDistance
                    self.remainingRouteDuration = travelDuration + totalStopsDuration
                    self.completedRouteCoordinates = [previous]
                    self.remainingRouteCoordinates = coordinates
                }

                // Check starting point stop - snap exactly to coordinate
                if let stopIdx = pendingStops.firstIndex(where: {
                    CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                        .distance(from: CLLocation(latitude: previous.latitude, longitude: previous.longitude)) < 15
                }) {
                    let stop = pendingStops.remove(at: stopIdx)
                    await self.performStop(stop, pairing: pairing)
                }

                let totalSegments = max(1, coordinates.count - 1)
                for (idx, next) in coordinates.dropFirst().enumerated() {
                    if Task.isCancelled { break }

                    // Pause gate before segment starts
                    while self.isRoutePaused && !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                    if Task.isCancelled { break }

                    let segDist = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                        .distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude))
                    var distanceInSegment: CLLocationDistance = 0.0

                    while distanceInSegment < segDist && !Task.isCancelled {
                        // Pause gate during traversal
                        while self.isRoutePaused && !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                        }
                        if Task.isCancelled { break }

                        // 1. Kinematic Acceleration / Deceleration Ramping
                        let targetSpeedMPS = self.currentSpeedMPS
                        let accelRate: Double = (self.travelMode == .drive || self.travelMode == .bus) ? 2.8 : 1.2
                        let dt: TimeInterval = 0.25
                        let maxSpeedDelta = accelRate * dt

                        if self.smoothedVelocityMPS < targetSpeedMPS {
                            self.smoothedVelocityMPS = min(targetSpeedMPS, self.smoothedVelocityMPS + maxSpeedDelta)
                        } else if self.smoothedVelocityMPS > targetSpeedMPS {
                            self.smoothedVelocityMPS = max(targetSpeedMPS, self.smoothedVelocityMPS - maxSpeedDelta)
                        }

                        // 2. Dynamic Velocity Vectors & Cadence Variation
                        let speedJitter: Double
                        if self.travelMode == .walk || self.travelMode == .sidewalk {
                            // Authentic human stride cadence variance (±6%)
                            let stepCadence = sin(cumulativeDistanceTraveled * 3.1) * 0.06
                            speedJitter = 1.0 + stepCadence + Double.random(in: -0.025...0.025)
                        } else if self.travelMode == .run {
                            speedJitter = 1.0 + sin(cumulativeDistanceTraveled * 2.6) * 0.04 + Double.random(in: -0.02...0.02)
                        } else {
                            // Engine cruising variations
                            speedJitter = 1.0 + Double.random(in: -0.03...0.03)
                        }
                        let liveSpeed = max(0.4, self.smoothedVelocityMPS * speedJitter)
                        let stepDist = max(0.08, liveSpeed * dt)
                        distanceInSegment = min(segDist, distanceInSegment + stepDist)
                        distanceSinceLastLight += stepDist
                        distanceSinceLastBusStop += stepDist
                        cumulativeDistanceTraveled += stepDist

                        let t = segDist > 0 ? (distanceInSegment / segDist) : 1.0
                        var coord = CLLocationCoordinate2D(
                            latitude: previous.latitude + (next.latitude - previous.latitude) * t,
                            longitude: previous.longitude + (next.longitude - previous.longitude) * t
                        )

                        let segmentHeading = Self.bearing(from: previous, to: next)

                        // For walking and sidewalk modes, apply subtle realistic lateral step sway (~0.18m)
                        if (self.travelMode == .walk || self.travelMode == .sidewalk) && segDist > 2 {
                            let swayMeters = sin(cumulativeDistanceTraveled * 2.4) * 0.18
                            let earthRadius = 6378137.0
                            let headingRad = segmentHeading * .pi / 180.0
                            let latOffset = (swayMeters * cos(headingRad + .pi / 2)) / earthRadius * (180.0 / .pi)
                            let lonOffset = (swayMeters * sin(headingRad + .pi / 2)) / (earthRadius * cos(coord.latitude * .pi / 180.0)) * (180.0 / .pi)
                            coord.latitude += latOffset
                            coord.longitude += lonOffset
                        }

                        // 3. Realistic GPS Signal Noise (Multipath & HDOP Jitter) for Life360 Motion Detection
                        let finalCoord = self.life360RealismEnabled
                            ? Self.applyGPSNoise(to: coord, headingDegrees: segmentHeading, speedMPS: liveSpeed)
                            : coord

                        let remainingInSegment = max(0, segDist - distanceInSegment)
                        let remainingDistance = remainingInSegment + suffixDistances[idx + 1]
                        let remainingTravel = RouteBuilder.estimatedDuration(distance: remainingDistance, speed: self.currentSpeedMPS)
                        let remainingStops = pendingStops.reduce(0) { $0 + $1.stopDuration }

                        // Slices for animated polyline progress
                        let completedSlice = Array(coordinates[0...idx]) + [coord]
                        let remainingSlice = [coord] + Array(coordinates[(idx + 1)...])

                        await MainActor.run {
                            self.apply(finalCoord, pairing: pairing, markRecent: false)
                            self.routeProgress = min(1.0, max(0.0, 1.0 - (remainingDistance / max(1.0, totalRouteDistance))))
                            self.remainingRouteDistance = remainingDistance
                            self.remainingRouteDuration = remainingTravel + remainingStops
                            self.completedRouteCoordinates = completedSlice
                            self.remainingRouteCoordinates = remainingSlice
                            if self.liveActivitiesEnabled {
                                LiveActivityManager.shared.updateActivity(
                                    progress: self.routeProgress,
                                    remainingDistanceMeters: remainingDistance,
                                    remainingDurationSeconds: self.remainingRouteDuration,
                                    destinationName: self.routeDestinationName,
                                    travelMode: self.travelMode,
                                    speedFormatted: self.speedUnit.format(liveSpeed),
                                    activeStopName: self.activeStopName,
                                    isPaused: self.isRoutePaused
                                )
                            }
                        }

                        // Smart Traffic Lights: ONLY stop if we are near an actual street intersection / turn junction!
                        if (self.travelMode == .drive || self.isCarModeActive || self.smartTrafficLights) && distanceSinceLastLight > 400 {
                            if idx > 0 && idx < coordinates.count - 1 && Self.isIntersection(before: coordinates[idx - 1], at: coordinates[idx], after: coordinates[idx + 1]) {
                                distanceSinceLastLight = 0
                                if Double.random(in: 0...1) < 0.35 {
                                    await self.performTrafficLightStop(pairing: pairing)
                                }
                            }
                        }

                        // Smart Bus Stops: only stop at detected public transit stops or junctions
                        if (self.travelMode == .bus || self.isBusModeActive) && self.busModeSmartStops && distanceSinceLastBusStop > 350 {
                            if idx > 0 && idx < coordinates.count - 1 && Self.isIntersection(before: coordinates[idx - 1], at: coordinates[idx], after: coordinates[idx + 1]) {
                                distanceSinceLastBusStop = 0
                                if Double.random(in: 0...1) < 0.45 {
                                    await self.performBusStop(pairing: pairing)
                                }
                            }
                        }

                        try? await Task.sleep(nanoseconds: UInt64(dt * 1_000_000_000))
                    }

                    await MainActor.run {
                        self.routeProgress = Double(idx + 1) / Double(totalSegments)
                    }

                    // Check if 'next' coordinate matches a pending stop: SNAP TO EXACT COORDINATE
                    if let stopIdx = pendingStops.firstIndex(where: {
                        CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                            .distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude)) < 15
                    }) {
                        let stop = pendingStops.remove(at: stopIdx)
                        await MainActor.run {
                            self.apply(stop.coordinate, pairing: pairing, markRecent: false)
                        }
                        await self.performStop(stop, pairing: pairing)
                        previous = stop.coordinate
                    } else {
                        previous = next
                    }
                }
                if !loop || Task.isCancelled {
                    shouldContinue = false
                }
            }
            await MainActor.run {
                self.isFollowingRoute = false
                self.isRoutePaused = false
                self.routeProgress = 1.0
                self.remainingRouteDistance = 0.0
                self.remainingRouteDuration = 0.0
                self.activeStopName = nil
                self.activeStopRemainingSeconds = nil
                self.isTrafficLightStopActive = false
                self.isBusStopActive = false

                if self.liveActivitiesEnabled {
                    LiveActivityManager.shared.endActivity(destinationName: self.routeDestinationName)
                }

                let totalDuration = Date().timeIntervalSince(routeStartTime)
                self.routeCompletionSummary = RouteCompletionStats(
                    destinationName: self.routeDestinationName.isEmpty ? "Destination" : self.routeDestinationName,
                    totalDistanceMeters: totalRouteDistance,
                    durationSeconds: max(1, totalDuration),
                    stopsVisited: definedStops.count
                )

                // Completion triggers: rumble haptics, notification, sound, and screen flash!
                self.triggerCompletionRumble()
                self.notifyRouteFinished(destination: self.routeDestinationName)
                withAnimation(.easeIn(duration: 0.15)) {
                    self.routeFinishedFlash = true
                }
                SoundManager.play(.success)

                // Auto-fade flash after 1.2 seconds so screen NEVER stays green!
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    withAnimation(.easeOut(duration: 0.45)) {
                        self?.routeFinishedFlash = false
                    }
                }
            }
        }
    }

    /// Calculates initial bearing in degrees from p1 to p2
    static func bearing(from p1: CLLocationCoordinate2D, to p2: CLLocationCoordinate2D) -> Double {
        let lat1 = p1.latitude * .pi / 180
        let lon1 = p1.longitude * .pi / 180
        let lat2 = p2.latitude * .pi / 180
        let lon2 = p2.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let rad = atan2(y, x)
        return (rad * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Checks if a waypoint junction forms a street turn/intersection (heading change > 28°)
    static func isIntersection(before: CLLocationCoordinate2D, at: CLLocationCoordinate2D, after: CLLocationCoordinate2D) -> Bool {
        let b1 = bearing(from: before, to: at)
        let b2 = bearing(from: at, to: after)
        var diff = abs(b1 - b2)
        if diff > 180 { diff = 360 - diff }
        return diff > 28.0
    }

    /// Dynamically updates the active route when waypoints or path is modified during execution or pause
    func updateActiveRoute(
        newCoordinates: [CLLocationCoordinate2D],
        newWaypoints: [RouteWaypoint] = [],
        pairing: PairingStore,
        loop: Bool = false
    ) {
        guard isFollowingRoute, let currentPos = simulated ?? newCoordinates.first else { return }
        var spliced: [CLLocationCoordinate2D] = [currentPos]
        if let first = newCoordinates.first,
           CLLocation(latitude: currentPos.latitude, longitude: currentPos.longitude)
            .distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude)) > 4 {
            spliced.append(contentsOf: newCoordinates)
        } else {
            spliced.append(contentsOf: newCoordinates.dropFirst())
        }
        guard spliced.count >= 2 else { return }
        let wasPaused = isRoutePaused
        followRoute(
            spliced,
            waypoints: newWaypoints,
            destinationName: routeDestinationName,
            pairing: pairing,
            loop: loop
        )
        if wasPaused {
            isRoutePaused = true
        }
    }

    private func performStop(_ stop: RouteWaypoint, pairing: PairingStore) async {
        guard stop.stopDuration > 0 else { return }
        let stopName = stop.name.isEmpty ? "Scheduled Stop" : stop.name
        let duration = stop.stopDuration
        await MainActor.run {
            self.activeStopName = stopName
            self.activeStopRemainingSeconds = duration
            self.apply(stop.coordinate, pairing: pairing, markRecent: false)
            SoundManager.play(.dwell)
        }

        var elapsed: Double = 0
        while elapsed < duration && !Task.isCancelled {
            while self.isRoutePaused && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if self.skipCurrentStopRequested {
                self.skipCurrentStopRequested = false
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            elapsed += 0.25
            let remaining = max(0, duration - elapsed)
            await MainActor.run {
                self.activeStopRemainingSeconds = remaining
                // Firmly hold coordinate locked at exact stop location
                self.apply(stop.coordinate, pairing: pairing, markRecent: false)
            }
        }

        await MainActor.run {
            self.activeStopName = nil
            self.activeStopRemainingSeconds = nil
        }
    }

    private func performTrafficLightStop(pairing: PairingStore) async {
        let duration: Double = Double.random(in: 15...25)
        await MainActor.run {
            self.isTrafficLightStopActive = true
            self.activeStopName = "Traffic Light"
            self.activeStopRemainingSeconds = duration
            SoundManager.play(.dwell)
        }

        var elapsed: Double = 0
        while elapsed < duration && !Task.isCancelled {
            while self.isRoutePaused && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if self.skipCurrentStopRequested {
                self.skipCurrentStopRequested = false
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            elapsed += 0.25
            let remaining = max(0, duration - elapsed)
            await MainActor.run {
                self.activeStopRemainingSeconds = remaining
            }
        }

        await MainActor.run {
            self.isTrafficLightStopActive = false
            self.activeStopName = nil
            self.activeStopRemainingSeconds = nil
        }
    }

    private func performBusStop(pairing: PairingStore) async {
        let duration: Double = Double.random(in: 14...20)
        await MainActor.run {
            self.isBusStopActive = true
            self.activeStopName = "Bus Passenger Stop"
            self.activeStopRemainingSeconds = duration
            SoundManager.play(.dwell)
        }

        var elapsed: Double = 0
        while elapsed < duration && !Task.isCancelled {
            while self.isRoutePaused && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if self.skipCurrentStopRequested {
                self.skipCurrentStopRequested = false
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            elapsed += 0.25
            let remaining = max(0, duration - elapsed)
            await MainActor.run {
                self.activeStopRemainingSeconds = remaining
            }
        }

        await MainActor.run {
            self.isBusStopActive = false
            self.activeStopName = nil
            self.activeStopRemainingSeconds = nil
        }
    }

    func notifyRouteFinished(destination: String) {
        guard routeNotificationsEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Route Completed"
            content.body = destination.isEmpty ? "Your simulated route has reached the final destination." : "Arrived at \(destination)."
            content.sound = .default
            content.userInfo = ["url": "locus://route_completed", "destination": destination]
            let request = UNNotificationRequest(identifier: "locus.route.finish.\(UUID().uuidString)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    func triggerCompletionRumble() {
        let notify = UINotificationFeedbackGenerator()
        notify.notificationOccurred(.success)
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
            try? await Task.sleep(nanoseconds: 100_000_000)
            impact.impactOccurred()
        }
    }

    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        // Don't let a generic star overwrite a named favorite for the same spot.
        if let existing = favorites.first(where: { $0.id == place.id }),
           Self.isGenericFavoriteName(place.name),
           !Self.isGenericFavoriteName(existing.name) {
            return
        }
        favorites.removeAll { $0.id == place.id }
        favorites.insert(place, at: 0)
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func renameFavorite(_ place: SavedPlace, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[index].name = trimmed
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeFavorite(_ place: SavedPlace) {
        favorites.removeAll { $0.id == place.id }
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeRecent(_ place: SavedPlace) {
        recents.removeAll { $0.id == place.id }
        SavedPlace.save(recents, key: recentsKey)
    }

    // MARK: - Saved Routes Management

    func saveRoute(_ route: SavedRoute) {
        if let index = savedRoutes.firstIndex(where: { $0.id == route.id }) {
            savedRoutes[index] = route
        } else {
            savedRoutes.insert(route, at: 0)
        }
        SavedRoute.save(savedRoutes, key: savedRoutesKey)
    }

    func deleteRoute(id: UUID) {
        savedRoutes.removeAll { $0.id == id }
        SavedRoute.save(savedRoutes, key: savedRoutesKey)
    }

    func deleteRoute(at offsets: IndexSet) {
        savedRoutes.remove(atOffsets: offsets)
        SavedRoute.save(savedRoutes, key: savedRoutesKey)
    }

    func renameRoute(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = savedRoutes.firstIndex(where: { $0.id == id }) else { return }
        savedRoutes[index].name = trimmed
        SavedRoute.save(savedRoutes, key: savedRoutesKey)
    }

    /// Best display name for starring the current pin (search title, matching recent, etc.).
    func suggestedFavoriteName(for coordinate: CLLocationCoordinate2D, fallback: String? = nil) -> String {
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let favorite = favorites.first(where: { $0.id == SavedPlace(name: "", latitude: coordinate.latitude, longitude: coordinate.longitude).id }),
           !Self.isGenericFavoriteName(favorite.name) {
            return favorite.name
        }
        if let recent = recents.first(where: {
            abs($0.latitude - coordinate.latitude) < 0.00015 && abs($0.longitude - coordinate.longitude) < 0.00015
        }), !Self.isGenericFavoriteName(recent.name) {
            return recent.name
        }
        return Self.coordinateLabel(coordinate)
    }

    /// Injects realistic GPS measurement noise (multipath + atmospheric dilution of precision)
    /// with cross-track and along-track jitter along the current velocity vector.
    static func applyGPSNoise(
        to coordinate: CLLocationCoordinate2D,
        headingDegrees: Double,
        speedMPS: Double
    ) -> CLLocationCoordinate2D {
        // Orthogonal Gaussian-like noise (Box-Muller transform)
        let u1 = max(1e-6, Double.random(in: 0...1))
        let u2 = Double.random(in: 0...1)
        let z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
        let z1 = sqrt(-2.0 * log(u1)) * sin(2.0 * .pi * u2)

        // Lateral cross-track noise (~0.35m) and along-track noise (~0.20m)
        let crossTrackNoise = z0 * 0.35
        let alongTrackNoise = z1 * 0.20

        let headingRad = headingDegrees * .pi / 180.0
        let eastMeters = alongTrackNoise * sin(headingRad) + crossTrackNoise * cos(headingRad)
        let northMeters = alongTrackNoise * cos(headingRad) - crossTrackNoise * sin(headingRad)

        let earthRadius = 6378137.0
        let dLat = (northMeters / earthRadius) * (180.0 / .pi)
        let dLon = (eastMeters / (earthRadius * cos(coordinate.latitude * .pi / 180.0))) * (180.0 / .pi)

        return CLLocationCoordinate2D(latitude: coordinate.latitude + dLat, longitude: coordinate.longitude + dLon)
    }

    private static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private static func isGenericFavoriteName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Favorite" { return true }
        // Coordinate-looking labels from older teleports.
        let parts = trimmed.split(separator: ",")
        if parts.count == 2,
           Double(parts[0].trimmingCharacters(in: .whitespaces)) != nil,
           Double(parts[1].trimmingCharacters(in: .whitespaces)) != nil {
            return true
        }
        return false
    }

    private func apply(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore, markRecent: Bool) {
        if status == .idle || status.isDropped {
            status = .connecting
        }
        isBusy = true
        let result = LocationEngine.set(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            pairingPath: pairing.pairingPath,
            deviceIP: TunnelConfig.targetIP
        )
        isBusy = false
        switch result {
        case .success:
            simulated = coordinate
            pin = coordinate
            status = .active
            lastError = nil
            beginBackground()
            locationKeeper.start()
            startResend(pairing: pairing)
            startHealth(pairing: pairing)
            if markRecent {
                pushRecent(coordinate)
            }
        case .failure(let error):
            lastError = error.localizedDescription
            if simulated != nil {
                status = .dropped(error.localizedDescription)
                postDropNotification(error.localizedDescription)
            } else {
                status = .idle
            }
        }
    }

    private func tickJoystick(pairing: PairingStore) {
        guard joystickActive, let current = simulated else { return }
        let magnitude = hypot(joystickVector.dx, joystickVector.dy)
        guard magnitude > 0.08 else {
            smoothedVelocityMPS = max(0.0, smoothedVelocityMPS - 0.5)
            return
        }
        let nx = joystickVector.dx / magnitude
        let ny = -joystickVector.dy / magnitude

        // Kinematic joystick acceleration smoothing
        let targetSpeed = currentSpeedMPS * min(1.0, magnitude)
        smoothedVelocityMPS = smoothedVelocityMPS * 0.70 + targetSpeed * 0.30
        let liveSpeed = max(0.35, smoothedVelocityMPS * Double.random(in: 0.96...1.04))
        let dt = 0.25
        let meters = liveSpeed * dt

        let headingDeg = (atan2(nx, ny) * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)
        let nextRaw = offset(coordinate: current, eastMeters: nx * meters, northMeters: ny * meters)
        let nextNoisy = life360RealismEnabled
            ? Self.applyGPSNoise(to: nextRaw, headingDegrees: headingDeg, speedMPS: liveSpeed)
            : nextRaw

        apply(nextNoisy, pairing: pairing, markRecent: false)
    }

    private func startResend(pairing: PairingStore) {
        resendTimer?.invalidate()
        // 2.0s high-frequency keepalive with 2D Brownian random walk to prevent Life360 0mph timeouts
        resendTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated else { return }
                var targetCoord = sim
                if self.stationaryDriftEnabled && !self.isFollowingRoute && !self.joystickActive {
                    // 2D Brownian drift with restorative spring pulling back toward base anchor
                    let driftStepEast = Double.random(in: -0.25...0.25) - (self.cumulativeDriftEast * 0.22)
                    let driftStepNorth = Double.random(in: -0.25...0.25) - (self.cumulativeDriftNorth * 0.22)
                    self.cumulativeDriftEast = min(1.2, max(-1.2, self.cumulativeDriftEast + driftStepEast))
                    self.cumulativeDriftNorth = min(1.2, max(-1.2, self.cumulativeDriftNorth + driftStepNorth))
                    targetCoord = self.offset(coordinate: sim, eastMeters: self.cumulativeDriftEast, northMeters: self.cumulativeDriftNorth)
                }
                _ = LocationEngine.set(
                    latitude: targetCoord.latitude,
                    longitude: targetCoord.longitude,
                    pairingPath: pairing.pairingPath,
                    deviceIP: TunnelConfig.targetIP
                )
            }
        }
    }

    private func stopResend() {
        resendTimer?.invalidate()
        resendTimer = nil
    }

    private func startHealth(pairing: PairingStore) {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated else { return }
                if case .dropped = self.status {
                    self.status = .reconnecting
                    self.apply(sim, pairing: pairing, markRecent: false)
                } else if !LocationEngine.isSessionActive, self.isSpoofing {
                    self.status = .reconnecting
                    self.apply(sim, pairing: pairing, markRecent: false)
                }
            }
        }
    }

    private func stopHealth() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func pushRecent(_ coordinate: CLLocationCoordinate2D) {
        pushNamedRecent(
            name: Self.coordinateLabel(coordinate),
            coordinate: coordinate
        )
    }

    func pushNamedRecent(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        recents.removeAll {
            abs($0.latitude - place.latitude) < 0.00015 && abs($0.longitude - place.longitude) < 0.00015
        }
        recents.insert(place, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        SavedPlace.save(recents, key: recentsKey)
    }

    private func beginBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackground()
        }
    }

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func postDropNotification(_ message: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Locus spoof dropped"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func offset(coordinate: CLLocationCoordinate2D, eastMeters: Double, northMeters: Double) -> CLLocationCoordinate2D {
        let earth = 6378137.0
        let dLat = northMeters / earth * (180 / .pi)
        let dLon = eastMeters / (earth * cos(coordinate.latitude * .pi / 180)) * (180 / .pi)
        return CLLocationCoordinate2D(latitude: coordinate.latitude + dLat, longitude: coordinate.longitude + dLon)
    }
}
