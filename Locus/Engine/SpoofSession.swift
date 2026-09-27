import CoreLocation
import Foundation
import MapKit
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

@MainActor
final class SpoofSession: ObservableObject {
    @Published var status: SpoofStatus = .idle
    @Published var pin: CLLocationCoordinate2D?
    @Published var simulated: CLLocationCoordinate2D?
    @Published var travelMode: TravelMode = .walk
    /// Non-nil when the user has entered a custom speed to use instead of the selected
    /// travel mode's preset. This is the ONLY other input to movement speed besides
    /// `travelMode` — see `currentSpeedMPS`, the single place that resolves the two.
    @Published var customSpeedMPS: Double?
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

    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []
    @Published var savedRoutes: [SavedRoute] = []
    @Published var defaultConnectionType: RouteConnectionType = RouteConnectionPreference.defaultType
    @Published var accentTheme: AccentColorTheme = ThemePreference.accent
    @Published var pathWidth: PathWidthPreference = ThemePreference.pathWidth
    @Published var uiAppearance: UIAppearanceStyle = ThemePreference.appearance
    @Published var showWaypointLabels: Bool = ThemePreference.showWaypointLabels

    private var resendTimer: Timer?
    private var healthTimer: Timer?
    private var joystickTimer: Timer?
    private var routeTask: Task<Void, Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var joystickVector: CGVector = .zero
    private let locationKeeper = BackgroundKeepAlive()
    private var skipCurrentStopRequested = false

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
    }

    func setDefaultConnectionType(_ type: RouteConnectionType) {
        defaultConnectionType = type
        RouteConnectionPreference.defaultType = type
    }

    func skipStop() {
        skipCurrentStopRequested = true
    }

    func setAccentTheme(_ theme: AccentColorTheme) {
        accentTheme = theme
        ThemePreference.accent = theme
    }

    func setCustomPrimaryHex(_ hex: String) {
        ThemePreference.customPrimaryHex = hex
        accentTheme = .custom
        ThemePreference.accent = .custom
        objectWillChange.send()
    }

    func setCustomSecondaryHex(_ hex: String) {
        ThemePreference.customSecondaryHex = hex
        accentTheme = .custom
        ThemePreference.accent = .custom
        objectWillChange.send()
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
    }

    /// Recalculates estimated remaining route duration when speed is changed during route playback.
    func updateRemainingRouteDuration() {
        guard isFollowingRoute else { return }
        let travel = RouteBuilder.estimatedDuration(distance: remainingRouteDistance, speed: currentSpeedMPS)
        let dwellLeft = activeStopRemainingSeconds ?? 0
        remainingRouteDuration = travel + dwellLeft
    }

    /// Validates and applies a custom speed typed by the user (see `SpeedInput`),
    /// persisting it so it survives relaunch. Safe to call while the joystick is
    /// active — it only changes the value `tickJoystick` reads next tick.
    /// Returns `false` without changing anything if the text isn't a valid speed.
    @discardableResult
    func setCustomSpeed(fromText text: String) -> Bool {
        guard let value = SpeedInput.parse(text) else { return false }
        customSpeedMPS = value
        SpeedPreference.setCustomSpeed(value)
        updateRemainingRouteDuration()
        return true
    }

    /// Clears any custom speed override, reverting to the selected travel mode's preset.
    func clearCustomSpeed() {
        customSpeedMPS = nil
        SpeedPreference.setCustomSpeed(nil)
        updateRemainingRouteDuration()
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
    }

    func pauseRoute() {
        guard isFollowingRoute && !isRoutePaused else { return }
        isRoutePaused = true
    }

    func resumeRoute() {
        guard isFollowingRoute && isRoutePaused else { return }
        isRoutePaused = false
    }

    func togglePauseRoute() {
        if isRoutePaused {
            resumeRoute()
        } else {
            pauseRoute()
        }
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
        skipCurrentStopRequested = false

        let totalRouteDistance = RouteBuilder.totalDistance(of: coordinates)
        remainingRouteDistance = totalRouteDistance
        let travelDuration = RouteBuilder.estimatedDuration(distance: totalRouteDistance, speed: currentSpeedMPS)
        let totalStopsDuration = waypoints.reduce(0) { $0 + $1.stopDuration }
        remainingRouteDuration = travelDuration + totalStopsDuration

        // Precompute cumulative suffix distances to quickly compute accurate remaining distance
        var suffixDistances = [CLLocationDistance](repeating: 0, count: coordinates.count)
        for i in (0..<(coordinates.count - 1)).reversed() {
            let seg = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
                .distance(from: CLLocation(latitude: coordinates[i + 1].latitude, longitude: coordinates[i + 1].longitude))
            suffixDistances[i] = suffixDistances[i + 1] + seg
        }

        let definedStops = waypoints.filter { $0.stopDuration > 0 }

        routeTask = Task { [weak self] in
            guard let self else { return }
            var shouldContinue = true
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

                // Check starting point stop
                if let stopIdx = pendingStops.firstIndex(where: {
                    CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                        .distance(from: CLLocation(latitude: previous.latitude, longitude: previous.longitude)) < 15
                }) {
                    let stop = pendingStops.remove(at: stopIdx)
                    await self.performStop(stop)
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

                        // Dynamic live speed read on every tick: immediately responds to speed changes
                        let speedMPS = self.currentSpeedMPS
                        let liveSpeed = max(0.5, speedMPS * Double.random(in: 0.95...1.05))
                        let dt: TimeInterval = 0.25
                        let stepDist = max(0.1, liveSpeed * dt)
                        distanceInSegment = min(segDist, distanceInSegment + stepDist)

                        let t = segDist > 0 ? (distanceInSegment / segDist) : 1.0
                        let coord = CLLocationCoordinate2D(
                            latitude: previous.latitude + (next.latitude - previous.latitude) * t,
                            longitude: previous.longitude + (next.longitude - previous.longitude) * t
                        )

                        let remainingInSegment = max(0, segDist - distanceInSegment)
                        let remainingDistance = remainingInSegment + suffixDistances[idx + 1]
                        let remainingTravel = RouteBuilder.estimatedDuration(distance: remainingDistance, speed: self.currentSpeedMPS)
                        let remainingStops = pendingStops.reduce(0) { $0 + $1.stopDuration }

                        // Slices for animated polyline progress
                        let completedSlice = Array(coordinates[0...idx]) + [coord]
                        let remainingSlice = [coord] + Array(coordinates[(idx + 1)...])

                        await MainActor.run {
                            self.apply(coord, pairing: pairing, markRecent: false)
                            self.routeProgress = min(1.0, max(0.0, 1.0 - (remainingDistance / max(1.0, totalRouteDistance))))
                            self.remainingRouteDistance = remainingDistance
                            self.remainingRouteDuration = remainingTravel + remainingStops
                            self.completedRouteCoordinates = completedSlice
                            self.remainingRouteCoordinates = remainingSlice
                        }

                        try? await Task.sleep(nanoseconds: UInt64(dt * 1_000_000_000))
                    }

                    await MainActor.run {
                        self.routeProgress = Double(idx + 1) / Double(totalSegments)
                    }

                    // Check if 'next' coordinate matches a pending stop
                    if let stopIdx = pendingStops.firstIndex(where: {
                        CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                            .distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude)) < 15
                    }) {
                        let stop = pendingStops.remove(at: stopIdx)
                        await self.performStop(stop)
                    }

                    previous = next
                }
                if !loop || Task.isCancelled {
                    shouldContinue = false
                }
            }
            await MainActor.run {
                self.isFollowingRoute = false
                self.isRoutePaused = false
                self.routeProgress = 0.0
                self.remainingRouteDistance = 0.0
                self.remainingRouteDuration = 0.0
                self.completedRouteCoordinates = []
                self.remainingRouteCoordinates = []
                self.activeStopName = nil
                self.activeStopRemainingSeconds = nil
            }
        }
    }

    private func performStop(_ stop: RouteWaypoint) async {
        guard stop.stopDuration > 0 else { return }
        let stopName = stop.name.isEmpty ? "Scheduled Stop" : stop.name
        let duration = stop.stopDuration
        await MainActor.run {
            self.activeStopName = stopName
            self.activeStopRemainingSeconds = duration
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
            self.activeStopName = nil
            self.activeStopRemainingSeconds = nil
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
        guard magnitude > 0.08 else { return }
        let nx = joystickVector.dx / magnitude
        let ny = -joystickVector.dy / magnitude
        let speed = currentSpeedMPS * min(1.0, magnitude) * Double.random(in: 0.9...1.1)
        let dt = 0.25
        let meters = speed * dt
        let next = offset(coordinate: current, eastMeters: nx * meters, northMeters: ny * meters)
        apply(next, pairing: pairing, markRecent: false)
    }

    private func startResend(pairing: PairingStore) {
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated else { return }
                _ = LocationEngine.set(
                    latitude: sim.latitude,
                    longitude: sim.longitude,
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
