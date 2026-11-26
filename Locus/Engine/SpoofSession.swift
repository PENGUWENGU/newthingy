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
    @Published var liveSpeedMPS: Double = 0.0
    @Published var routeProgress: Double = 0.0
    @Published var remainingRouteDistance: CLLocationDistance = 0.0
    @Published var remainingRouteDuration: TimeInterval = 0.0
    @Published var completedRouteCoordinates: [CLLocationCoordinate2D] = []
    @Published var remainingRouteCoordinates: [CLLocationCoordinate2D] = []
    @Published var completedRouteSegments: [[CLLocationCoordinate2D]] = []
    @Published var remainingRouteSegments: [[CLLocationCoordinate2D]] = []
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
    @Published var life360SpeedBoost: Bool = (UserDefaults.standard.object(forKey: "locus.life360SpeedBoost") as? Bool) ?? true
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
    @Published var busModeSmartStops: Bool = false
    @Published var smartTrafficLights: Bool = false
    @Published var routeNotificationsEnabled: Bool = true
    @Published var travelerName: String = UserDefaults.standard.string(forKey: "locus.travelerName") ?? ""
    @Published var speedVarianceMPH: Double = SpeedPreference.storedVariance
    @Published var speedRandomnessEnabled: Bool = SpeedPreference.storedRandomnessEnabled
    @Published var liveCourseDegrees: Double = 0.0
    @Published var adhereToSpeedLimits: Bool = false
    @Published var currentSpeedLimitInfo: RoadSpeedInfo? = nil

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
    private let audioKeeper = SilentAudioKeepAlive()
    private let simulationEngine = RouteSimulationEngine()
    private let routeSessionController = RoutePlaybackSessionController()
    private let sessionResources = NonisolatedSessionResources()
    private var skipCurrentStopRequested = false
    private var smoothedVelocityMPS: Double = 0.0
    private var cumulativeDriftEast: Double = 0.0
    private var cumulativeDriftNorth: Double = 0.0
    private var persistentCrossTrackError: Double = 0.0
    private var persistentAlongTrackError: Double = 0.0
    private var lastJoystickWallTime: Double = 0.0

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

    func applyThemeConfiguration(
        accentTheme: AccentColorTheme,
        primaryHex: String,
        secondaryHex: String,
        textColorHex: String,
        isCustomTextColorEnabled: Bool,
        menuTintHex: String,
        isMenuTintEnabled: Bool,
        glassTintHex: String,
        isGlassTintEnabled: Bool,
        completionFlashHex: String,
        pathWidth: PathWidthPreference,
        uiAppearance: UIAppearanceStyle,
        showWaypointLabels: Bool
    ) {
        self.customPrimaryHex = primaryHex
        ThemePreference.customPrimaryHex = primaryHex

        self.customSecondaryHex = secondaryHex
        ThemePreference.customSecondaryHex = secondaryHex

        self.accentTheme = accentTheme
        ThemePreference.accent = accentTheme

        self.customTextColorHex = textColorHex
        ThemePreference.customTextColorHex = textColorHex
        self.isCustomTextColorEnabled = isCustomTextColorEnabled
        ThemePreference.isCustomTextColorEnabled = isCustomTextColorEnabled

        self.customMenuTintHex = menuTintHex
        ThemePreference.customMenuTintHex = menuTintHex
        self.isMenuTintEnabled = isMenuTintEnabled
        ThemePreference.isMenuTintEnabled = isMenuTintEnabled

        self.glassTintHex = glassTintHex
        ThemePreference.glassTintHex = glassTintHex
        self.isGlassTintEnabled = isGlassTintEnabled
        ThemePreference.hasCustomGlassTint = isGlassTintEnabled

        self.completionFlashHex = completionFlashHex
        ThemePreference.completionFlashHex = completionFlashHex

        self.pathWidth = pathWidth
        ThemePreference.pathWidth = pathWidth

        self.uiAppearance = uiAppearance
        ThemePreference.appearance = uiAppearance

        self.showWaypointLabels = showWaypointLabels
        ThemePreference.showWaypointLabels = showWaypointLabels

        self.themeVersion += 1
        self.objectWillChange.send()
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

    /// Sets the active travel mode (compatibility alias for selectTravelMode).
    func setTravelMode(_ mode: TravelMode) {
        selectTravelMode(mode)
    }

    /// Sets a custom speed override in meters per second directly (nil clears custom speed override).
    func setCustomSpeed(_ mps: Double?) {
        customSpeedMPS = mps
        SpeedPreference.setCustomSpeed(mps)
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

    /// Sets speed variance fluctuation range (1.0 to 5.0 mph).
    func setSpeedVariance(_ value: Double) {
        let clamped = min(5.0, max(1.0, value))
        speedVarianceMPH = clamped
        SpeedPreference.storedVariance = clamped
        simulationEngine.speedVarianceRangeMPH = clamped
        objectWillChange.send()
    }

    /// Toggles dynamic random speed fluctuations.
    func setSpeedRandomnessEnabled(_ value: Bool) {
        speedRandomnessEnabled = value
        SpeedPreference.storedRandomnessEnabled = value
        simulationEngine.enableRandomSpeedFluctuations = value
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
        guard RouteSimulationEngine.isValidCoordinate(coordinate) else {
            lastError = "Invalid coordinate."
            return
        }
        if isFollowingRoute {
            stopRoute(restoreStationaryActivity: false)
        }
        pin = coordinate
        apply(coordinate, pairing: pairing, markRecent: true)
    }

    /// Resumes an interrupted spoofing session or route following a crash or unexpected termination.
    func resumeFromCrash(snapshot: SpoofSessionSnapshot, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Import an RPPairing file in Settings first."
            return
        }

        if let mode = TravelMode(rawValue: snapshot.travelModeRaw) {
            travelMode = mode
        }
        if snapshot.currentSpeedMPS.isFinite && snapshot.currentSpeedMPS > 0 {
            setCustomSpeed(snapshot.currentSpeedMPS)
        }

        let resumeCoord = snapshot.lastCoordinate.clCoordinate
        guard RouteSimulationEngine.isValidCoordinate(resumeCoord) else {
            lastError = "Saved recovery coordinate was invalid."
            return
        }

        if snapshot.sessionType == .route {
            let waypoints: [RouteWaypoint] = (snapshot.routeWaypoints ?? []).map(\.routeWaypoint)
            if let rawSegments = snapshot.routeCoordinateSegments?.map({ $0.map(\.clCoordinate) }),
               !rawSegments.isEmpty {
                var trimmedSegments = rawSegments.map { $0.filter { RouteSimulationEngine.isValidCoordinate($0) } }.filter { !$0.isEmpty }
                if !trimmedSegments.isEmpty {
                    // Preserve multi-segment structure while resuming near the last coordinate
                    let targetIdx = min(max(0, snapshot.currentSegmentIndex ?? 0), max(0, trimmedSegments.flatMap { $0 }.count - 1))
                    var flatOffset = 0
                    var resumeSegIdx = 0
                    var resumeLocalIdx = 0
                    for (sIdx, seg) in trimmedSegments.enumerated() {
                        if targetIdx < flatOffset + seg.count {
                            resumeSegIdx = sIdx
                            resumeLocalIdx = targetIdx - flatOffset
                            break
                        }
                        flatOffset += seg.count
                    }
                    var adjustedSegments: [[CLLocationCoordinate2D]] = []
                    if resumeSegIdx < trimmedSegments.count {
                        var firstSeg = [resumeCoord]
                        let curSeg = trimmedSegments[resumeSegIdx]
                        if resumeLocalIdx + 1 < curSeg.count {
                            firstSeg.append(contentsOf: curSeg[(resumeLocalIdx + 1)...])
                        } else if let segLast = curSeg.last,
                                  RouteSimulationEngine.haversineDistance(from: resumeCoord, to: segLast) > 1.0 {
                            firstSeg.append(segLast)
                        }
                        if firstSeg.count >= 2 {
                            adjustedSegments.append(firstSeg)
                        }
                        if resumeSegIdx + 1 < trimmedSegments.count {
                            adjustedSegments.append(contentsOf: trimmedSegments[(resumeSegIdx + 1)...])
                        }
                    }
                    if !adjustedSegments.isEmpty {
                        followRoute(
                            segments: adjustedSegments,
                            waypoints: waypoints,
                            destinationName: snapshot.routeName ?? "Resumed Route",
                            pairing: pairing,
                            loop: snapshot.isLoop ?? false
                        )
                        return
                    }
                }
            }

            if let coords = snapshot.routeCoordinates?.map({ $0.clCoordinate }).filter({ RouteSimulationEngine.isValidCoordinate($0) }),
               coords.count >= 2 {
                let segIdx = min(coords.count - 1, max(0, snapshot.currentSegmentIndex ?? 0))

                var remainingCoords: [CLLocationCoordinate2D] = [resumeCoord]
                if segIdx + 1 < coords.count {
                    remainingCoords.append(contentsOf: coords[(segIdx + 1)...])
                } else if let last = coords.last,
                          RouteSimulationEngine.haversineDistance(from: last, to: resumeCoord) > 1.0 {
                    remainingCoords.append(last)
                } else {
                    remainingCoords.append(coords[segIdx])
                }

                followRoute(
                    remainingCoords,
                    waypoints: waypoints,
                    destinationName: snapshot.routeName ?? "Resumed Route",
                    pairing: pairing,
                    loop: snapshot.isLoop ?? false
                )
                return
            }
        }

        teleport(to: resumeCoord, pairing: pairing)
    }

    func stop(pairing: PairingStore) {
        stopRoute(restoreStationaryActivity: false)
        stopJoystick()
        stopResend()
        stopHealth()
        LiveActivityManager.shared.endAllActivities()
        CrashRecoveryManager.shared.clearSession()
        isBusy = true
        let result = LocationEngine.clear()
        isBusy = false
        switch result {
        case .success:
            simulated = nil
            status = .idle
            audioKeeper.stop()
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

    func stopRoute(restoreStationaryActivity: Bool = true) {
        let prevDestination = routeDestinationName
        _ = routeSessionController.stopActiveSession()
        routeTask?.cancel()
        routeTask = nil
        sessionResources.setRouteTask(nil)
        CrashRecoveryManager.shared.clearSession()

        cleanupRouteUIState()

        if restoreStationaryActivity, isSpoofing, !joystickActive {
            // Will resume stationary resend if we stay spoofing after stopping a route
        }
        if liveActivitiesEnabled {
            LiveActivityManager.shared.endActivity(destinationName: prevDestination)
            if restoreStationaryActivity, isSpoofing, let sim = simulated {
                LiveActivityManager.shared.startSpoofActivity(
                    locationName: Self.coordinateLabel(sim),
                    coordinate: sim,
                    speedFormatted: "Stationary",
                    isJoystick: false
                )
            }
        }
    }

    private func cleanupRouteUIState() {
        isFollowingRoute = false
        isRoutePaused = false
        liveSpeedMPS = 0.0
        routeProgress = 0.0
        remainingRouteDistance = 0.0
        remainingRouteDuration = 0.0
        completedRouteCoordinates = []
        remainingRouteCoordinates = []
        completedRouteSegments = []
        remainingRouteSegments = []
        activeStopName = nil
        activeStopRemainingSeconds = nil
        isTrafficLightStopActive = false
        isBusStopActive = false
        skipCurrentStopRequested = false
    }

    func pauseRoute() {
        guard isFollowingRoute && !isRoutePaused else { return }
        isRoutePaused = true
        liveSpeedMPS = 0.0
        if liveActivitiesEnabled {
            LiveActivityManager.shared.updateActivity(
                progress: routeProgress,
                remainingDistanceMeters: remainingRouteDistance,
                remainingDurationSeconds: remainingRouteDuration,
                destinationName: routeDestinationName,
                travelMode: travelMode,
                speedFormatted: speedUnit.format(0),
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
        stopRoute(restoreStationaryActivity: false)
        let start = simulated ?? pin ?? locationKeeper.lastKnownCoordinate
        guard let start, RouteSimulationEngine.isValidCoordinate(start) else {
            lastError = "Drop a pin or teleport somewhere before using the joystick."
            return
        }
        if simulated == nil {
            apply(start, pairing: pairing, markRecent: false)
        }
        stopResend()
        audioKeeper.start()
        locationKeeper.start()
        beginBackground()
        joystickActive = true
        lastJoystickWallTime = CACurrentMediaTime()
        joystickTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickJoystick(pairing: pairing)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        joystickTimer = timer
        sessionResources.setJoystickTimer(timer)
    }

    func updateJoystick(vector: CGVector) {
        joystickVector = vector
    }

    func stopJoystick(pairing: PairingStore? = nil) {
        joystickActive = false
        joystickVector = .zero
        liveSpeedMPS = 0.0
        joystickTimer?.invalidate()
        joystickTimer = nil
        if let pairing, !isFollowingRoute {
            startResend(pairing: pairing)
        }
        if liveActivitiesEnabled && !isFollowingRoute, let sim = simulated {
            LiveActivityManager.shared.updateSpoofActivity(
                locationName: Self.coordinateLabel(sim),
                coordinate: sim,
                speedFormatted: "Stationary",
                isJoystick: false
            )
        }
    }

    /// Generates and drives an authentic continuous driving circuit (~2.5 km loop, exceeding Life360's
    /// 0.5-mile drive detection threshold) with dynamic 1–5 mph throttle variance, corner slowdowns,
    /// and continuous 1.0s GPS injection for Life360.
    func startDriveSimulation(around center: CLLocationCoordinate2D? = nil, pairing: PairingStore) {
        guard pairing.hasPairingFile else { return }
        let origin = center ?? simulated ?? pin ?? locationKeeper.lastKnownCoordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        setTravelMode(.drive)
        if customSpeedMPS == nil {
            setCustomSpeed(TravelMode.drive.baseSpeed)
        }

        // Generate smooth 12-point road circuit (~2.4 km perimeter)
        let radiusMeters: Double = 380.0
        var loopCoords: [CLLocationCoordinate2D] = []
        let pointCount = 12
        for i in 0..<pointCount {
            let angle = (Double(i) / Double(pointCount)) * (2.0 * .pi)
            let r = radiusMeters * (1.0 + 0.16 * sin(angle * 2.0))
            let east = r * cos(angle)
            let north = r * sin(angle)
            loopCoords.append(offset(coordinate: origin, eastMeters: east, northMeters: north))
        }
        loopCoords.append(loopCoords[0])

        let sampled = RouteBuilder.sample(coordinates: loopCoords, every: 12.0)
        guard let firstPoint = sampled.first else { return }
        let midPoint = sampled[sampled.count / 2]
        let waypoints = [
            RouteWaypoint(coordinate: firstPoint, title: "Start Loop"),
            RouteWaypoint(coordinate: midPoint, title: "Midpoint"),
            RouteWaypoint(coordinate: firstPoint, title: "End Loop")
        ]

        followRoute(
            sampled,
            waypoints: waypoints,
            destinationName: "Life360 Driving Simulation",
            pairing: pairing,
            loop: true
        )
    }

    func followRoute(
        _ coordinates: [CLLocationCoordinate2D],
        waypoints: [RouteWaypoint] = [],
        destinationName: String = "",
        pairing: PairingStore,
        loop: Bool = false,
        startPaused: Bool = false
    ) {
        followRoute(
            segments: [coordinates],
            waypoints: waypoints,
            destinationName: destinationName,
            pairing: pairing,
            loop: loop,
            startPaused: startPaused
        )
    }

    func followRoute(
        segments: [[CLLocationCoordinate2D]],
        waypoints: [RouteWaypoint] = [],
        destinationName: String = "",
        pairing: PairingStore,
        loop: Bool = false,
        startPaused: Bool = false
    ) {
        guard pairing.hasPairingFile else { return }
        let plan = RoutePlaybackPlan(coordinateSegments: segments)
        guard let startCoord = plan.startCoordinate, plan.flattenedCoordinates.count >= 2 || plan.isPlayable else {
            return
        }

        // Cancel any previously active route task & claim its single cleanup before spinning up the new session
        routeTask?.cancel()
        routeTask = nil
        sessionResources.setRouteTask(nil)

        let (sessionID, previousNeedingCleanup) = routeSessionController.beginNewSession()
        if previousNeedingCleanup != nil {
            cleanupRouteUIState()
        }

        stopJoystick()
        stopResend()
        audioKeeper.start()
        locationKeeper.start()
        beginBackground()

        isFollowingRoute = true
        isRoutePaused = startPaused
        routeProgress = 0.0
        activeStopName = nil
        activeStopRemainingSeconds = nil
        isTrafficLightStopActive = false
        isBusStopActive = false
        skipCurrentStopRequested = false
        routeDestinationName = destinationName.isEmpty ? (waypoints.last?.name ?? "Destination") : destinationName
        activeRouteWaypoints = waypoints

        let totalRouteDistance = plan.totalDistance
        let initialHeading = plan.edges.first?.bearingDegrees ?? 0.0
        let initialSpeed = startPaused ? 0.0 : currentSpeedMPS
        smoothedVelocityMPS = currentSpeedMPS
        liveSpeedMPS = initialSpeed
        liveCourseDegrees = initialHeading
        simulationEngine.reset(initialSpeedMPS: currentSpeedMPS, initialHeading: initialHeading)
        simulationEngine.speedVarianceRangeMPH = speedVarianceMPH
        simulationEngine.enableRandomSpeedFluctuations = speedRandomnessEnabled
        simulationEngine.enableGPSJitter = life360RealismEnabled

        activeRouteTotalDistance = totalRouteDistance
        remainingRouteDistance = totalRouteDistance
        let travelDuration = RouteBuilder.estimatedDuration(distance: totalRouteDistance, speed: currentSpeedMPS)
        let totalStopsDuration = waypoints.reduce(0) { $0 + max(0.0, $1.stopDuration) }
        remainingRouteDuration = travelDuration + totalStopsDuration

        // Request notification permission for route completion alert if needed
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        let definedStops = waypoints.filter { $0.stopDuration > 0 && RouteSimulationEngine.isValidCoordinate($0.coordinate) }
        let routeStartTime = Date()
        let capturedDestination = routeDestinationName
        let capturedSegments = plan.coordinateSegments
        let capturedFlatCoords = plan.flattenedCoordinates

        if liveActivitiesEnabled {
            LiveActivityManager.shared.startActivity(
                routeId: sessionID.uuidString,
                destinationName: capturedDestination,
                travelMode: travelMode,
                speedFormatted: speedUnit.format(initialSpeed),
                initialRemainingSeconds: remainingRouteDuration,
                routeDistanceMeters: totalRouteDistance,
                isPaused: startPaused
            )
        }

        let task = Task { [weak self] in
            guard let self else { return }
            var completedNaturally = false
            var playbackState = RoutePlaybackState(plan: plan)
            var distanceSinceLastLight: Double = 0.0
            var distanceSinceLastBusStop: Double = 0.0
            let stepInterval: Double = 1.0

            outerLoop: while self.routeSessionController.isActive(sessionID) {
                playbackState.resetForLoop()
                var pendingStops = definedStops
                var lastEpochWallTime = CACurrentMediaTime()
                var nextTickDeadline = lastEpochWallTime + stepInterval

                await MainActor.run {
                    guard self.routeSessionController.isActive(sessionID) else { return }
                    self.apply(startCoord, pairing: pairing, markRecent: true)
                    self.stopResend()
                    self.routeProgress = plan.isPlayable ? 0.0 : 1.0
                    self.remainingRouteDistance = totalRouteDistance
                    self.remainingRouteDuration = travelDuration + totalStopsDuration
                    self.completedRouteSegments = [[startCoord]]
                    self.remainingRouteSegments = capturedSegments
                    self.completedRouteCoordinates = [startCoord]
                    self.remainingRouteCoordinates = capturedFlatCoords
                }

                if !self.routeSessionController.isActive(sessionID) { break outerLoop }

                // Degenerate zero-distance route (all points identical): mark reached cleanly
                if !plan.isPlayable {
                    completedNaturally = true
                    break outerLoop
                }

                // Check starting point dwell stop
                if let stopIdx = pendingStops.firstIndex(where: {
                    RouteSimulationEngine.haversineDistance(from: $0.coordinate, to: startCoord) < 15.0
                }) {
                    let stop = pendingStops.remove(at: stopIdx)
                    await self.performStop(stop, sessionID: sessionID, pairing: pairing)
                    lastEpochWallTime = CACurrentMediaTime()
                    nextTickDeadline = lastEpochWallTime + stepInterval
                }

                while !playbackState.isFinished && self.routeSessionController.isActive(sessionID) {
                    // Pause gate during traversal
                    var wasPausedTick = false
                    while self.isRoutePaused && self.routeSessionController.isActive(sessionID) {
                        wasPausedTick = true
                        try? await Task.sleep(nanoseconds: 150_000_000)
                    }
                    guard self.routeSessionController.isActive(sessionID) else { break outerLoop }

                    if wasPausedTick {
                        lastEpochWallTime = CACurrentMediaTime()
                        nextTickDeadline = lastEpochWallTime + stepInterval
                    }

                    let epochStart = CACurrentMediaTime()
                    let rawElapsed = max(0.0, epochStart - lastEpochWallTime)
                    // Protect against huge teleports after iOS background suspension without inflating short intervals
                    let actualElapsed = min(4.0, rawElapsed)
                    lastEpochWallTime = epochStart

                    // Read turn angle & mode speed for the CURRENT active segment BEFORE stepping
                    let preTurnAngle = playbackState.upcomingTurnAngleDegrees

                    let targetBaseSpeed: Double
                    let currentMode = await MainActor.run { self.travelMode }
                    let currentCarActive = await MainActor.run { self.isCarModeActive }
                    let currentAdhereLimit = await MainActor.run { self.adhereToSpeedLimits }
                    let currentUserSpeedMPS = await MainActor.run { self.currentSpeedMPS }
                    let currentTrafficLights = await MainActor.run { self.smartTrafficLights }
                    let currentBusMode = await MainActor.run { self.isBusModeActive }
                    let currentBusStops = await MainActor.run { self.busModeSmartStops }

                    if currentAdhereLimit,
                       let postedLimit = RoadSpeedLimitService.shared.latestSpeedLimit?.speedLimitMPS,
                       (currentMode == .drive || currentMode == .cycle || currentCarActive) {
                        targetBaseSpeed = postedLimit
                    } else {
                        targetBaseSpeed = currentUserSpeedMPS
                    }

                    let liveSpeed = self.simulationEngine.computeNextSpeed(
                        baseSpeedMPS: targetBaseSpeed,
                        travelMode: currentMode,
                        turnAngleDegrees: preTurnAngle,
                        elapsedSeconds: max(0.05, actualElapsed)
                    )

                    let stepDistance = actualElapsed > 0.0 ? (liveSpeed * actualElapsed) : liveSpeed * stepInterval
                    distanceSinceLastLight += stepDistance
                    distanceSinceLastBusStop += stepDistance

                    // Advance along polyline (across 0, 1, or N edges) and compute post-transition interpolation & heading!
                    let step = playbackState.advance(byMeters: stepDistance)

                    let telemetry = self.simulationEngine.generateTelemetryPayload(
                        rawCoordinate: step.coordinate,
                        headingDegrees: step.headingDegrees,
                        speedMPS: liveSpeed,
                        travelMode: currentMode
                    )
                    let finalCoord = telemetry.coordinate

                    let remainingTravel = RouteBuilder.estimatedDuration(distance: step.remainingDistanceMeters, speed: targetBaseSpeed)
                    let remainingStops = pendingStops.reduce(0.0) { $0 + max(0.0, $1.stopDuration) }

                    // Periodically fetch road speed limits for HUD & vehicle mode
                    if currentMode == .drive || currentMode == .cycle || currentCarActive {
                        RoadSpeedLimitService.shared.fetchSpeedLimit(at: finalCoord)
                    }

                    guard self.routeSessionController.isActive(sessionID) else { break outerLoop }

                    // Continuous heartbeat checkpoint for crash recovery
                    CrashRecoveryManager.shared.updateHeartbeat(
                        snapshot: SpoofSessionSnapshot(
                            sessionType: .route,
                            coordinate: finalCoord,
                            locationName: capturedDestination,
                            travelMode: currentMode,
                            currentSpeedMPS: liveSpeed,
                            routeName: capturedDestination,
                            routeCoordinates: capturedFlatCoords,
                            routeCoordinateSegments: capturedSegments,
                            routeWaypoints: waypoints,
                            currentSegmentIndex: step.activeEdgeIndex,
                            routeProgress: step.progress,
                            isLoop: loop,
                            remainingDistanceMeters: step.remainingDistanceMeters
                        )
                    )

                    // Final guard right before hardware location injection so superseded tasks never leak stale GPS
                    guard self.routeSessionController.isActive(sessionID) else { break outerLoop }
                    _ = LocationEngine.set(
                        latitude: finalCoord.latitude,
                        longitude: finalCoord.longitude,
                        pairingPath: pairing.pairingPath,
                        deviceIP: TunnelConfig.targetIP
                    )

                    let completedFlat = step.completedCoordinates
                    let remainingFlat = step.remainingCoordinates

                    await MainActor.run {
                        guard self.routeSessionController.isActive(sessionID) else { return }
                        self.simulated = finalCoord
                        self.pin = finalCoord
                        self.liveSpeedMPS = telemetry.speedMPS
                        self.liveCourseDegrees = telemetry.courseDegrees
                        self.currentSpeedLimitInfo = RoadSpeedLimitService.shared.currentRoadSpeed
                        self.routeProgress = step.progress
                        self.remainingRouteDistance = step.remainingDistanceMeters
                        self.remainingRouteDuration = remainingTravel + remainingStops
                        self.completedRouteSegments = step.completedSegments
                        self.remainingRouteSegments = step.remainingSegments
                        self.completedRouteCoordinates = completedFlat
                        self.remainingRouteCoordinates = remainingFlat
                        if self.liveActivitiesEnabled {
                            LiveActivityManager.shared.updateActivity(
                                progress: step.progress,
                                remainingDistanceMeters: step.remainingDistanceMeters,
                                remainingDurationSeconds: self.remainingRouteDuration,
                                destinationName: self.routeDestinationName,
                                travelMode: self.travelMode,
                                speedFormatted: self.speedUnit.format(telemetry.speedMPS),
                                activeStopName: self.activeStopName,
                                isPaused: self.isRoutePaused
                            )
                        }
                    }

                    guard self.routeSessionController.isActive(sessionID) else { break outerLoop }

                    // Check if coordinate matches a pending dwell stop
                    if let stopIdx = pendingStops.firstIndex(where: {
                        RouteSimulationEngine.haversineDistance(from: $0.coordinate, to: step.coordinate) < 15.0
                    }) {
                        let stop = pendingStops.remove(at: stopIdx)
                        await MainActor.run {
                            guard self.routeSessionController.isActive(sessionID) else { return }
                            self.applySimulatedMovement(stop.coordinate, pairing: pairing)
                        }
                        await self.performStop(stop, sessionID: sessionID, pairing: pairing)
                        guard self.routeSessionController.isActive(sessionID) else { break outerLoop }
                        lastEpochWallTime = CACurrentMediaTime()
                        nextTickDeadline = lastEpochWallTime + stepInterval
                    }

                    // Smart Traffic Lights: ONLY stop if enabled by user and at a real corner (not GPX segment break)
                    if (currentMode == .drive || currentCarActive) && currentTrafficLights && distanceSinceLastLight > 500.0 {
                        if step.upcomingTurnAngleDegrees > 28.0 {
                            distanceSinceLastLight = 0.0
                            if Double.random(in: 0...1) < 0.30 {
                                await self.performTrafficLightStop(sessionID: sessionID, pairing: pairing)
                                guard self.routeSessionController.isActive(sessionID) else { break outerLoop }
                                lastEpochWallTime = CACurrentMediaTime()
                                nextTickDeadline = lastEpochWallTime + stepInterval
                            }
                        }
                    }

                    // Smart Bus Stops: ONLY stop if enabled by user
                    if (currentMode == .bus || currentBusMode) && currentBusStops && distanceSinceLastBusStop > 450.0 {
                        if step.upcomingTurnAngleDegrees > 28.0 {
                            distanceSinceLastBusStop = 0.0
                            if Double.random(in: 0...1) < 0.35 {
                                await self.performBusStop(sessionID: sessionID, pairing: pairing)
                                guard self.routeSessionController.isActive(sessionID) else { break outerLoop }
                                lastEpochWallTime = CACurrentMediaTime()
                                nextTickDeadline = lastEpochWallTime + stepInterval
                            }
                        }
                    }

                    if step.reachedEnd {
                        break
                    }

                    // Monotonic deadline sleep prevents accumulated timing drift across ticks
                    nextTickDeadline += stepInterval
                    let now = CACurrentMediaTime()
                    if nextTickDeadline < now - 2.0 {
                        nextTickDeadline = now + stepInterval
                    }
                    let sleepDuration = nextTickDeadline - now
                    if sleepDuration > 0.005 {
                        try? await Task.sleep(nanoseconds: UInt64(sleepDuration * 1_000_000_000))
                    } else {
                        await Task.yield()
                    }
                }

                if !self.routeSessionController.isActive(sessionID) {
                    break outerLoop
                }
                if !loop {
                    completedNaturally = true
                    break outerLoop
                }
            }

            if completedNaturally && self.routeSessionController.claimCompletion(for: sessionID) {
                await MainActor.run {
                    self.completeRouteNaturally(
                        plan: plan,
                        destinationName: capturedDestination,
                        routeStartTime: routeStartTime,
                        stopsVisited: definedStops.count,
                        pairing: pairing
                    )
                }
            } else if self.routeSessionController.claimCleanup(for: sessionID) {
                await MainActor.run {
                    CrashRecoveryManager.shared.clearSession()
                    self.cleanupRouteUIState()
                    if self.liveActivitiesEnabled {
                        LiveActivityManager.shared.endActivity(destinationName: capturedDestination)
                    }
                }
            }
        }
        routeTask = task
        sessionResources.setRouteTask(task)
    }

    private func completeRouteNaturally(
        plan: RoutePlaybackPlan,
        destinationName: String,
        routeStartTime: Date,
        stopsVisited: Int,
        pairing: PairingStore
    ) {
        CrashRecoveryManager.shared.clearSession()
        cleanupRouteUIState()
        routeProgress = 1.0
        completedRouteSegments = plan.coordinateSegments
        completedRouteCoordinates = plan.flattenedCoordinates
        remainingRouteSegments = []
        remainingRouteCoordinates = []
        startResend(pairing: pairing)

        let totalDuration = Date().timeIntervalSince(routeStartTime)
        if liveActivitiesEnabled {
            LiveActivityManager.shared.endActivity(destinationName: destinationName)
            if let endCoord = plan.endCoordinate {
                LiveActivityManager.shared.startSpoofActivity(
                    locationName: destinationName.isEmpty ? Self.coordinateLabel(endCoord) : destinationName,
                    coordinate: endCoord,
                    speedFormatted: "Stationary",
                    isJoystick: false
                )
            }
        }

        routeCompletionSummary = RouteCompletionStats(
            destinationName: destinationName.isEmpty ? "Destination" : destinationName,
            totalDistanceMeters: plan.totalDistance,
            durationSeconds: max(1, totalDuration),
            stopsVisited: stopsVisited
        )

        triggerCompletionRumble()
        notifyRouteFinished(
            destination: destinationName,
            distanceMeters: plan.totalDistance,
            durationSeconds: max(1, totalDuration)
        )
        withAnimation(.easeIn(duration: 0.15)) {
            routeFinishedFlash = true
        }
        SoundManager.play(.success)

        // Auto-fade flash after 1.2 seconds so screen NEVER stays green!
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            withAnimation(.easeOut(duration: 0.45)) {
                self?.routeFinishedFlash = false
            }
        }
    }

    /// Calculates initial bearing in degrees from p1 to p2
    static func bearing(from p1: CLLocationCoordinate2D, to p2: CLLocationCoordinate2D) -> Double {
        RouteSimulationEngine.greatCircleBearing(from: p1, to: p2)
    }

    /// Checks if a waypoint junction forms a street turn/intersection (heading change > 28°)
    static func isIntersection(before: CLLocationCoordinate2D, at: CLLocationCoordinate2D, after: CLLocationCoordinate2D) -> Bool {
        let b1 = RouteSimulationEngine.greatCircleBearing(from: before, to: at)
        let b2 = RouteSimulationEngine.greatCircleBearing(from: at, to: after)
        return RouteSimulationEngine.turnAngleBetween(bearing1: b1, bearing2: b2) > 28.0
    }

    /// Dynamically updates the active route when waypoints or path is modified during execution or pause
    func updateActiveRoute(
        newCoordinates: [CLLocationCoordinate2D],
        newWaypoints: [RouteWaypoint] = [],
        coordinateSegments: [[CLLocationCoordinate2D]]? = nil,
        pairing: PairingStore,
        loop: Bool = false
    ) {
        guard isFollowingRoute else { return }
        let wasPaused = isRoutePaused

        if let segs = coordinateSegments, !segs.isEmpty {
            let validSegs = segs.map { $0.filter { RouteSimulationEngine.isValidCoordinate($0) } }.filter { !$0.isEmpty }
            guard !validSegs.isEmpty else { return }
            followRoute(
                segments: validSegs,
                waypoints: newWaypoints,
                destinationName: routeDestinationName,
                pairing: pairing,
                loop: loop,
                startPaused: wasPaused
            )
            return
        }

        let validNew = newCoordinates.filter { RouteSimulationEngine.isValidCoordinate($0) }
        guard let currentPos = simulated ?? validNew.first, RouteSimulationEngine.isValidCoordinate(currentPos) else { return }
        var spliced: [CLLocationCoordinate2D] = [currentPos]
        if let first = validNew.first,
           RouteSimulationEngine.haversineDistance(from: currentPos, to: first) > 4.0 {
            spliced.append(contentsOf: validNew)
        } else {
            spliced.append(contentsOf: validNew.dropFirst())
        }
        guard spliced.count >= 2 else { return }
        followRoute(
            spliced,
            waypoints: newWaypoints,
            destinationName: routeDestinationName,
            pairing: pairing,
            loop: loop,
            startPaused: wasPaused
        )
    }

    private func performStop(_ stop: RouteWaypoint, sessionID: UUID, pairing: PairingStore) async {
        guard stop.stopDuration > 0, routeSessionController.isActive(sessionID) else { return }
        let stopName = stop.name.isEmpty ? "Scheduled Stop" : stop.name
        let duration = stop.stopDuration
        await MainActor.run {
            guard self.routeSessionController.isActive(sessionID) else { return }
            self.skipCurrentStopRequested = false
            self.activeStopName = stopName
            self.activeStopRemainingSeconds = duration
            self.applySimulatedMovement(stop.coordinate, pairing: pairing)
            SoundManager.play(.dwell)
        }

        await runDwellLoop(duration: duration, sessionID: sessionID) { [weak self] in
            guard let self, self.routeSessionController.isActive(sessionID) else { return }
            self.applySimulatedMovement(stop.coordinate, pairing: pairing)
        }

        await MainActor.run {
            guard self.routeSessionController.isActive(sessionID) else { return }
            self.activeStopName = nil
            self.activeStopRemainingSeconds = nil
            self.skipCurrentStopRequested = false
        }
    }

    private func performTrafficLightStop(sessionID: UUID, pairing: PairingStore) async {
        guard routeSessionController.isActive(sessionID) else { return }
        let duration: Double = Double.random(in: 12...20)
        await MainActor.run {
            guard self.routeSessionController.isActive(sessionID) else { return }
            self.skipCurrentStopRequested = false
            self.isTrafficLightStopActive = true
            self.activeStopName = "Traffic Light"
            self.activeStopRemainingSeconds = duration
            SoundManager.play(.dwell)
        }

        await runDwellLoop(duration: duration, sessionID: sessionID) { [weak self] in
            guard let self, self.routeSessionController.isActive(sessionID), let sim = self.simulated else { return }
            self.applySimulatedMovement(sim, pairing: pairing)
        }

        await MainActor.run {
            guard self.routeSessionController.isActive(sessionID) else { return }
            self.isTrafficLightStopActive = false
            self.activeStopName = nil
            self.activeStopRemainingSeconds = nil
            self.skipCurrentStopRequested = false
        }
    }

    private func performBusStop(sessionID: UUID, pairing: PairingStore) async {
        guard routeSessionController.isActive(sessionID) else { return }
        let duration: Double = Double.random(in: 10...16)
        await MainActor.run {
            guard self.routeSessionController.isActive(sessionID) else { return }
            self.skipCurrentStopRequested = false
            self.isBusStopActive = true
            self.activeStopName = "Bus Passenger Stop"
            self.activeStopRemainingSeconds = duration
            SoundManager.play(.dwell)
        }

        await runDwellLoop(duration: duration, sessionID: sessionID) { [weak self] in
            guard let self, self.routeSessionController.isActive(sessionID), let sim = self.simulated else { return }
            self.applySimulatedMovement(sim, pairing: pairing)
        }

        await MainActor.run {
            guard self.routeSessionController.isActive(sessionID) else { return }
            self.isBusStopActive = false
            self.activeStopName = nil
            self.activeStopRemainingSeconds = nil
            self.skipCurrentStopRequested = false
        }
    }

    private func runDwellLoop(
        duration: TimeInterval,
        sessionID: UUID,
        onHeartbeatMainActor: @escaping @MainActor () -> Void
    ) async {
        var elapsed: Double = 0.0
        var lastWallTime = CACurrentMediaTime()

        while elapsed < duration && routeSessionController.isActive(sessionID) {
            var paused = false
            while isRoutePaused && routeSessionController.isActive(sessionID) {
                paused = true
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            guard routeSessionController.isActive(sessionID) else { break }

            if paused {
                lastWallTime = CACurrentMediaTime()
            }
            if skipCurrentStopRequested {
                skipCurrentStopRequested = false
                break
            }

            let sleepTime = min(1.0, max(0.05, duration - elapsed))
            try? await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
            guard routeSessionController.isActive(sessionID) else { break }

            let now = CACurrentMediaTime()
            let delta = min(5.0, max(0.0, now - lastWallTime))
            lastWallTime = now
            elapsed += delta

            let remaining = max(0.0, duration - elapsed)
            await MainActor.run {
                guard self.routeSessionController.isActive(sessionID) else { return }
                self.activeStopRemainingSeconds = remaining
                onHeartbeatMainActor()
            }
        }
    }

    func setTravelerName(_ name: String) {
        travelerName = name
        UserDefaults.standard.set(name, forKey: "locus.travelerName")
    }

    func testArrivalNotification() {
        let dest = routeDestinationName.isEmpty ? "Home" : routeDestinationName
        notifyRouteFinished(destination: dest, distanceMeters: 4500, durationSeconds: 680)
    }

    func notifyRouteFinished(destination: String, distanceMeters: Double = 0, durationSeconds: TimeInterval = 0) {
        guard routeNotificationsEnabled else { return }
        let trimmedName = travelerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let modeTitle = travelMode.title

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            let cleanDest = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalDest = cleanDest.isEmpty ? "Destination" : cleanDest

            if !trimmedName.isEmpty {
                content.title = "📍 \(trimmedName) arrived at \(finalDest)!"
            } else {
                content.title = "📍 Arrived at \(finalDest)!"
            }

            var parts: [String] = []
            if distanceMeters > 0 {
                parts.append(RouteBuilder.formattedDistance(distanceMeters))
            }
            if durationSeconds > 0 {
                let mins = Int(ceil(durationSeconds / 60.0))
                parts.append("\(mins) min")
            }
            parts.append(modeTitle)
            content.subtitle = parts.joined(separator: " • ")

            if !trimmedName.isEmpty {
                content.body = "\(trimmedName) safely reached \(finalDest). Telemetry is now holding steady at \(finalDest) for Life360 & Find My."
            } else {
                content.body = "You have reached \(finalDest). Telemetry is now holding steady at \(finalDest) for Life360 & Find My."
            }

            content.sound = .default
            content.userInfo = [
                "url": "locus://route_completed",
                "destination": finalDest,
                "travelerName": trimmedName
            ]
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

    func addFavorite(_ place: SavedPlace) {
        addFavorite(name: place.name, coordinate: place.coordinate)
    }

    func addRecent(_ place: SavedPlace) {
        pushNamedRecent(name: place.name, coordinate: place.coordinate)
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
    /// with continuous Gauss-Markov drift that preserves true kinematic velocity and heading for Life360,
    /// injecting subtle random GPS jitter within 0.5–1.5 meters.
    func applyGPSNoise(
        to coordinate: CLLocationCoordinate2D,
        headingDegrees: Double,
        speedMPS: Double
    ) -> CLLocationCoordinate2D {
        simulationEngine.enableGPSJitter = life360RealismEnabled
        let payload = simulationEngine.generateTelemetryPayload(
            rawCoordinate: coordinate,
            headingDegrees: headingDegrees,
            speedMPS: speedMPS,
            travelMode: travelMode
        )
        return payload.coordinate
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

    func applySimulatedMovement(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard RouteSimulationEngine.isValidCoordinate(coordinate) else { return }
        let result = LocationEngine.set(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            pairingPath: pairing.pairingPath,
            deviceIP: TunnelConfig.targetIP
        )
        switch result {
        case .success:
            simulated = coordinate
            pin = coordinate
            if status != .active {
                status = .active
            }
            lastError = nil
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

    private func apply(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore, markRecent: Bool) {
        guard RouteSimulationEngine.isValidCoordinate(coordinate) else {
            lastError = "Invalid coordinate."
            return
        }
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
            audioKeeper.start()
            startResend(pairing: pairing)
            startHealth(pairing: pairing)
            if markRecent {
                pushRecent(coordinate)
            }
            RoadSpeedLimitService.shared.fetchSpeedLimit(at: coordinate)
            CrashRecoveryManager.shared.updateHeartbeat(snapshot: SpoofSessionSnapshot(
                sessionType: isFollowingRoute ? .route : (joystickActive ? .joystick : .teleport),
                coordinate: coordinate,
                locationName: Self.coordinateLabel(coordinate),
                travelMode: travelMode,
                currentSpeedMPS: currentSpeedMPS
            ))
            if liveActivitiesEnabled && !isFollowingRoute {
                LiveActivityManager.shared.startSpoofActivity(
                    locationName: Self.coordinateLabel(coordinate),
                    coordinate: coordinate,
                    speedFormatted: "Stationary",
                    isJoystick: false
                )
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
            smoothedVelocityMPS = max(0.0, smoothedVelocityMPS - 1.5)
            liveSpeedMPS = smoothedVelocityMPS
            return
        }
        let nx = joystickVector.dx / magnitude
        let ny = -joystickVector.dy / magnitude

        let now = CACurrentMediaTime()
        let dt = lastJoystickWallTime > 0 ? max(0.05, min(2.5, now - lastJoystickWallTime)) : 1.0
        lastJoystickWallTime = now

        // Kinematic joystick velocity with speed variance range (1–5 mph)
        let targetSpeed = currentSpeedMPS * min(1.0, magnitude)
        let liveSpeed: Double
        if speedRandomnessEnabled {
            liveSpeed = simulationEngine.computeNextSpeed(
                baseSpeedMPS: targetSpeed,
                travelMode: travelMode,
                turnAngleDegrees: 0,
                elapsedSeconds: dt
            )
        } else {
            smoothedVelocityMPS = smoothedVelocityMPS * 0.40 + targetSpeed * 0.60
            liveSpeed = max(0.8, smoothedVelocityMPS)
        }
        liveSpeedMPS = liveSpeed
        let meters = liveSpeed * dt

        let headingDeg = RouteSimulationEngine.normalizeBearing(atan2(nx, ny) * 180.0 / .pi)
        let nextRaw = offset(coordinate: current, eastMeters: nx * meters, northMeters: ny * meters)
        let nextNoisy = life360RealismEnabled
            ? applyGPSNoise(to: nextRaw, headingDegrees: headingDeg, speedMPS: liveSpeed)
            : nextRaw

        applySimulatedMovement(nextNoisy, pairing: pairing)
        if liveActivitiesEnabled && !isFollowingRoute {
            LiveActivityManager.shared.updateSpoofActivity(
                locationName: "Joystick Navigation",
                coordinate: nextNoisy,
                speedFormatted: speedUnit.format(liveSpeed),
                isJoystick: true
            )
        }
    }

    private func startResend(pairing: PairingStore) {
        resendTimer?.invalidate()
        guard !isFollowingRoute && !joystickActive else { return }
        // 2.5s high-frequency keepalive with 2D Brownian random walk to prevent Life360 0mph timeouts
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated else { return }
                guard !self.isFollowingRoute && !self.joystickActive else { return }
                var targetCoord = sim
                if self.stationaryDriftEnabled {
                    // 2D Brownian drift with restorative spring pulling back toward base anchor
                    let driftStepEast = Double.random(in: -0.15...0.15) - (self.cumulativeDriftEast * 0.25)
                    let driftStepNorth = Double.random(in: -0.15...0.15) - (self.cumulativeDriftNorth * 0.25)
                    self.cumulativeDriftEast = min(0.8, max(-0.8, self.cumulativeDriftEast + driftStepEast))
                    self.cumulativeDriftNorth = min(0.8, max(-0.8, self.cumulativeDriftNorth + driftStepNorth))
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
        RunLoop.main.add(timer, forMode: .common)
        resendTimer = timer
        sessionResources.setResendTimer(timer)
    }

    private func stopResend() {
        resendTimer?.invalidate()
        resendTimer = nil
        sessionResources.setResendTimer(nil)
    }

    private func startHealth(pairing: PairingStore) {
        healthTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
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
        healthTimer = timer
        sessionResources.setHealthTimer(timer)
    }

    private func stopHealth() {
        healthTimer?.invalidate()
        healthTimer = nil
        sessionResources.setHealthTimer(nil)
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
            Task { @MainActor [weak self] in
                self?.endBackground()
            }
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
        RouteSimulationEngine.offsetCoordinate(coordinate, eastMeters: eastMeters, northMeters: northMeters)
    }
}

/// Thread-safe handle bag so `SpoofSession.deinit` can invalidate timers and cancel active tasks
/// without triggering Swift 5/6 `@MainActor` isolation warnings.
private final class NonisolatedSessionResources: @unchecked Sendable {
    private let lock = NSLock()
    private var routeTask: Task<Void, Never>?
    private var resendTimer: Timer?
    private var healthTimer: Timer?
    private var joystickTimer: Timer?

    func setRouteTask(_ task: Task<Void, Never>?) {
        lock.lock()
        routeTask = task
        lock.unlock()
    }

    func setResendTimer(_ timer: Timer?) {
        lock.lock()
        resendTimer = timer
        lock.unlock()
    }

    func setHealthTimer(_ timer: Timer?) {
        lock.lock()
        healthTimer = timer
        lock.unlock()
    }

    func setJoystickTimer(_ timer: Timer?) {
        lock.lock()
        joystickTimer = timer
        lock.unlock()
    }

    deinit {
        lock.lock()
        let task = routeTask
        let resend = resendTimer
        let health = healthTimer
        let joy = joystickTimer
        routeTask = nil
        resendTimer = nil
        healthTimer = nil
        joystickTimer = nil
        lock.unlock()

        task?.cancel()
        let timers = [resend, health, joy].compactMap { $0 }
        if !timers.isEmpty {
            DispatchQueue.main.async {
                timers.forEach { $0.invalidate() }
            }
        }
    }
}
