import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct MapHomeView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore

    @StateObject private var search = PlaceSearchCompleter()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    // Route Mode State (Points & Freehand)
    @State private var routeModeActive = false
    @State private var routeMethod: RouteCreationMethod = .points
    @State private var routeConnectionType: RouteConnectionType = RouteConnectionPreference.defaultType
    @State private var waypoints: [RouteWaypoint] = []
    @State private var freehandCoordinates: [CLLocationCoordinate2D] = []
    @State private var calculatedRoute: [CLLocationCoordinate2D] = []
    @State private var isRouting = false
    @State private var loopRoute = false
    @State private var selectedWaypointId: UUID?
    @State private var showRouteSheet = false
    @State private var showGPXImporter = false
    @State private var isFreehandDragging = false
    @State private var importedGPXTrack: GPXTrack?
    @State private var showMapSaveRouteAlert = false
    @State private var mapSaveRouteName = ""
    @State private var showThemeSheet = false
    @State private var isFreehandDrawingMode = true
    @State private var editingStopWaypointIndex: Int? = nil
    @State private var pathDashPhase: CGFloat = 0
    @State private var puckPulsing = false
    @State private var showEndSpoofConfirmation = false
    @State private var showFavoritePrompt = false
    @State private var pendingFavoriteCoordinate: CLLocationCoordinate2D? = nil
    @State private var favoriteNameInput = ""
    @State private var showFavoriteAnimation = false
    private let pathAnimationTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    // Standard Pin State
    @State private var pinSelected = false
    @State private var isDraggingPin = false
    @State private var suppressNextMapTap = false
    @State private var pinPlaceName: String?

    private var mapStyle: MapStyle {
        switch session.mapStyleIndex {
        case 1: return .hybrid(elevation: .realistic)
        case 2: return .imagery(elevation: .realistic)
        default: return .standard(elevation: .realistic)
        }
    }

    private var displayRouteCoordinates: [CLLocationCoordinate2D] {
        if !calculatedRoute.isEmpty {
            return calculatedRoute
        } else if routeMethod == .freehand {
            return freehandCoordinates
        } else if waypoints.count >= 2 {
            return waypoints.map(\.coordinate)
        }
        return []
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapContainerView
            topChrome
            completionFlashOverlay
            favoriteCelebrationOverlay
        }
        .onAppear(perform: handleOnAppear)
        .onChange(of: session.defaultConnectionType, handleDefaultConnectionTypeChange)
        .onReceive(pathAnimationTimer, perform: handlePathAnimationTick)
        .onChange(of: session.pin?.latitude) { _, newValue in
            if newValue == nil { pinSelected = false }
        }
        .sheet(isPresented: $showRouteSheet) {
            routePlannerSheetView
        }
        .sheet(isPresented: $showThemeSheet) {
            ThemeCustomizerSheet(session: session)
        }
        .sheet(isPresented: stopPickerBinding) {
            stopPickerSheetView
        }
        .alert("Save Route", isPresented: $showMapSaveRouteAlert) {
            saveRouteAlertView
        } message: {
            Text("Enter a name to save this route to your device.")
        }
        .alert("End Route Spoofing?", isPresented: $showEndSpoofConfirmation) {
            endSpoofAlertView
        } message: {
            Text("Are you sure you want to stop following this route and end simulated movement?")
        }
        .alert("Save Favorite Place", isPresented: $showFavoritePrompt) {
            favoritePromptAlertView
        } message: {
            Text("Enter a custom name for this favorite location.")
        }
    }

    private var mapContainerView: some View {
        MapReader { proxy in
            ZStack {
                Map(position: $position) {
                    UserAnnotation()

                    if let pin = session.pin, !routeModeActive {
                        Annotation("", coordinate: pin, anchor: .bottom) {
                            dropPinView(proxy: proxy)
                        }
                    }

                    waypointAnnotations

                    if let sim = session.simulated {
                        Annotation("Spoof", coordinate: sim) {
                            spoofPuckView
                        }
                    }

                    routePolylines
                }
                .mapStyle(mapStyle)
                .mapControlVisibility(.hidden)
                .onTapGesture { point in
                    searchFocused = false
                    guard !suppressNextMapTap, !isDraggingPin else { return }
                    handleMapTap(at: point, proxy: proxy)
                }

                if routeModeActive && routeMethod == .freehand && !session.isFollowingRoute {
                    FreehandCanvasTouchOverlay(
                        isDrawingEnabled: isFreehandDrawingMode,
                        onPoint: { point in
                            handleFreehandDrag(at: point, proxy: proxy)
                        },
                        onEnded: {
                            handleFreehandDragEnd()
                        }
                    )
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    @ViewBuilder
    private var completionFlashOverlay: some View {
        if session.routeFinishedFlash {
            ThemePreference.completionFlashColor
                .opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var favoriteCelebrationOverlay: some View {
        if showFavoriteAnimation {
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.body.weight(.black))
                        .foregroundStyle(.yellow)
                    Text("Saved to Favorites!")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color(UIColor.secondarySystemBackground)).shadow(color: LocusTheme.accent.opacity(0.4), radius: 12, y: 4))
                .transition(.scale.combined(with: .opacity))
                .padding(.bottom, 100)
            }
        }
    }

    private var routePlannerSheetView: some View {
        RoutePlannerSheet(
            method: $routeMethod,
            connectionType: $routeConnectionType,
            waypoints: $waypoints,
            freehandCoordinates: $freehandCoordinates,
            calculatedRoute: $calculatedRoute,
            isRouting: $isRouting,
            loopRoute: $loopRoute,
            onBuildRoute: buildPointsRoute,
            onPlayRoute: playRoute,
            onStopRoute: {
                showEndSpoofConfirmation = true
            },
            onImportGPX: {},
            onExportGPX: {},
            onSmoothFreehand: smoothFreehandRoute,
            onClearRoute: clearAllRouteData,
            onAddPinAsWaypoint: addPinAsWaypoint,
            onAddSpoofAsWaypoint: addSpoofAsWaypoint,
            onLoadRoute: loadSavedRoute
        )
        .presentationDetents([.medium, .large])
    }

    private var stopPickerBinding: Binding<Bool> {
        Binding(
            get: { editingStopWaypointIndex != nil },
            set: { if !$0 { editingStopWaypointIndex = nil } }
        )
    }

    @ViewBuilder
    private var stopPickerSheetView: some View {
        if let idx = editingStopWaypointIndex, waypoints.indices.contains(idx) {
            StopDurationPickerSheet(
                waypointIndex: idx,
                waypointName: waypoints[idx].name,
                initialDuration: waypoints[idx].stopDuration
            ) { newDuration in
                waypoints[idx].stopDuration = newDuration
                if session.isFollowingRoute {
                    session.updateActiveRoute(displayRouteCoordinates, waypoints: waypoints, loop: loopRoute)
                }
            }
        }
    }

    @ViewBuilder
    private var saveRouteAlertView: some View {
        TextField("Route Name", text: $mapSaveRouteName)
        Button("Save") {
            SoundManager.play(.success)
            saveCurrentRouteFromMap()
        }
        Button("Cancel", role: .cancel) {}
    }

    @ViewBuilder
    private var endSpoofAlertView: some View {
        Button("End Spoof", role: .destructive) {
            SoundManager.play(.alert)
            withAnimation {
                session.stopRoute()
            }
        }
        Button("Continue Route", role: .cancel) {
            SoundManager.play(.tap)
        }
    }

    @ViewBuilder
    private var favoritePromptAlertView: some View {
        TextField("Place Name", text: $favoriteNameInput)
        Button("Save") {
            if let coord = pendingFavoriteCoordinate {
                let finalName = favoriteNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Favorite Place" : favoriteNameInput
                session.addFavorite(name: finalName, coordinate: coord)
                SoundManager.play(.success)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    showFavoriteAnimation = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation { showFavoriteAnimation = false }
                }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func handleOnAppear() {
        session.startLocationUpdates()
        routeConnectionType = session.defaultConnectionType
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            puckPulsing = true
        }
    }

    private func handleDefaultConnectionTypeChange(_ old: RouteConnectionType, _ newDefault: RouteConnectionType) {
        if waypoints.isEmpty {
            routeConnectionType = newDefault
        }
    }

    private func handlePathAnimationTick(_ date: Date) {
        if session.isFollowingRoute && !session.isRoutePaused {
            pathDashPhase -= 1.6
        }
    }

    // MARK: - Map Tap & Gestures

    private func handleMapTap(at point: CGPoint, proxy: MapProxy) {
        guard let coord = proxy.convert(point, from: .local) else { return }

        if routeModeActive {
            if routeMethod == .points {
                addWaypoint(coord)
            }
        } else {
            pinSelected = false
            session.pin = coord
            pinPlaceName = nil
        }
    }

    private func handleFreehandDrag(at point: CGPoint, proxy: MapProxy) {
        guard let coord = proxy.convert(point, from: .local) else { return }
        if !isFreehandDragging {
            isFreehandDragging = true
            importedGPXTrack = nil
        }

        // Add coordinate if sufficiently distant from last point
        if let last = freehandCoordinates.last {
            let dist = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            if dist >= 2.0 {
                freehandCoordinates.append(coord)
            }
        } else {
            freehandCoordinates.append(coord)
        }
    }

    private func handleFreehandDragEnd() {
        isFreehandDragging = false
        if freehandCoordinates.count >= 2 {
            smoothFreehandRoute()
        }
    }

    // MARK: - Route Operations

    private func addWaypoint(_ coord: CLLocationCoordinate2D) {
        let name = "Waypoint \(waypoints.count + 1)"
        waypoints.append(RouteWaypoint(coordinate: coord, name: name))
        importedGPXTrack = nil
        if waypoints.count >= 2 {
            if routeConnectionType == .straight {
                calculatedRoute = RouteBuilder.multiPointStraightRoute(waypoints: waypoints.map(\.coordinate))
            } else {
                buildPointsRoute()
            }
        }
    }

    private func removeWaypoint(at index: Int) {
        guard index < waypoints.count else { return }
        waypoints.remove(at: index)
        selectedWaypointId = nil
        if waypoints.count >= 2 {
            if routeConnectionType == .straight {
                calculatedRoute = RouteBuilder.multiPointStraightRoute(waypoints: waypoints.map(\.coordinate))
            } else {
                buildPointsRoute()
            }
        } else {
            calculatedRoute.removeAll()
        }
    }

    private func toggleWaypointStop(at index: Int) {
        guard index < waypoints.count else { return }
        let current = waypoints[index].stopDuration
        let next: TimeInterval
        if current == 0 {
            next = 30
        } else if current == 30 {
            next = 60
        } else if current == 60 {
            next = 120
        } else if current == 120 {
            next = 300
        } else {
            next = 0
        }
        waypoints[index].stopDuration = next
    }

    private func addPinAsWaypoint() {
        guard let pin = session.pin else { return }
        addWaypoint(pin)
    }

    private func addSpoofAsWaypoint() {
        guard let sim = session.simulated else { return }
        addWaypoint(sim)
    }

    private func buildPointsRoute() {
        guard waypoints.count >= 2 else { return }
        if routeConnectionType == .straight {
            calculatedRoute = RouteBuilder.multiPointStraightRoute(waypoints: waypoints.map(\.coordinate))
            return
        }

        isRouting = true
        let coords = waypoints.map(\.coordinate)
        Task {
            do {
                let route = try await RouteBuilder.multiPointRoadRoute(waypoints: coords, mode: session.travelMode)
                await MainActor.run {
                    self.calculatedRoute = route
                    self.isRouting = false
                }
            } catch {
                await MainActor.run {
                    self.isRouting = false
                    // Fallback to straight line if roads unavailable in region
                    self.calculatedRoute = RouteBuilder.multiPointStraightRoute(waypoints: coords)
                    self.session.lastError = "Road route unavailable; connected with straight segments."
                }
            }
        }
    }

    private func smoothFreehandRoute() {
        guard freehandCoordinates.count >= 2 else { return }
        calculatedRoute = RouteBuilder.processFreehandPath(coordinates: freehandCoordinates, sampleMeters: 6, smooth: true)
    }

    private func clearAllRouteData() {
        waypoints.removeAll()
        freehandCoordinates.removeAll()
        calculatedRoute.removeAll()
        selectedWaypointId = nil
        importedGPXTrack = nil
    }

    private func playRoute() {
        let path = displayRouteCoordinates
        guard path.count >= 2 else {
            session.lastError = "Add at least 2 points or draw a freehand path first."
            return
        }
        if routeMethod == .freehand {
            withAnimation {
                routeMethod = .points
            }
        }
        session.followRoute(path, waypoints: waypoints, pairing: pairing, loop: loopRoute)
    }

    private func saveCurrentRouteFromMap() {
        let path = displayRouteCoordinates
        guard path.count >= 2 else { return }
        let dist = RouteBuilder.totalDistance(of: path)
        let route = SavedRoute(
            name: mapSaveRouteName,
            method: routeMethod,
            connectionType: routeConnectionType,
            waypoints: waypoints,
            coordinates: path,
            distanceMeters: dist,
            isLoop: loopRoute
        )
        session.saveRoute(route)
    }

    private func loadSavedRoute(_ savedRoute: SavedRoute) {
        routeModeActive = true
        routeMethod = savedRoute.method
        routeConnectionType = savedRoute.connectionType
        loopRoute = savedRoute.isLoop
        waypoints = savedRoute.clWaypoints

        if savedRoute.method == .points {
            freehandCoordinates = []
            if savedRoute.connectionType == .straight {
                calculatedRoute = RouteBuilder.multiPointStraightRoute(waypoints: savedRoute.clCoordinates)
            } else {
                calculatedRoute = savedRoute.clCoordinates
            }
        } else {
            waypoints = []
            freehandCoordinates = savedRoute.clCoordinates
            calculatedRoute = savedRoute.clCoordinates
        }

        importedGPXTrack = nil

        if let first = savedRoute.clCoordinates.first ?? savedRoute.clWaypoints.first?.coordinate {
            session.pin = first
        }

        if let region = MKCoordinateRegion.framing(savedRoute.clCoordinates) {
            withAnimation(.easeInOut(duration: 0.35)) {
                position = .region(region)
            }
        }
    }

    // MARK: - UI Components

    private var topChrome: some View {
        VStack(spacing: 8) {
            StatusBarView()

            searchBar

            if !searchText.isEmpty && !search.results.isEmpty {
                searchResults
            }

            // Route Mode Active Floating Bar
            if routeModeActive || session.isFollowingRoute {
                routeControlPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(alignment: .center, spacing: 10) {
                mapChromeButtons
                Spacer(minLength: 0)
                locateButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
        .safeAreaPadding(.top, 8)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: routeModeActive || session.isFollowingRoute)
    }

    @ViewBuilder
    private var routeControlPanel: some View {
        VStack(spacing: 8) {
            if session.isFollowingRoute {
                TransitRouteBannerView(
                    session: session,
                    onTogglePause: {
                        SoundManager.play(.toggle)
                        withAnimation {
                            session.togglePauseRoute()
                        }
                    },
                    onStop: {
                        SoundManager.play(.alert)
                        showEndSpoofConfirmation = true
                    },
                    onSkipStop: {
                        SoundManager.play(.tap)
                        session.skipStop()
                    },
                    onOpenPlanner: {
                        SoundManager.play(.tap)
                        showRouteSheet = true
                    }
                )
            } else {
                routeMethodSwitcher
                routeSummaryActionBar
            }
        }
        .padding(12)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var routeMethodSwitcher: some View {
        HStack(spacing: 8) {
            Button {
                SoundManager.play(.tap)
                withAnimation { routeMethod = .points }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                    Text("Points")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(routeMethod == .points ? .black : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(routeMethod == .points ? LocusTheme.accent : Color.primary.opacity(0.08))
                )
            }
            .buttonStyle(.plain)

            Button {
                SoundManager.play(.tap)
                withAnimation { routeMethod = .freehand }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.and.scribble")
                    Text("Freehand")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(routeMethod == .freehand ? .black : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(routeMethod == .freehand ? LocusTheme.accent : Color.primary.opacity(0.08))
                )
            }
            .buttonStyle(.plain)

            Button {
                withAnimation {
                    routeModeActive = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
    }

    private var routeSummaryActionBar: some View {
        let totalDist = RouteBuilder.totalDistance(of: displayRouteCoordinates)
        let estDuration = RouteBuilder.estimatedDuration(distance: totalDist, speed: session.currentSpeedMPS)

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if routeMethod == .points {
                    Text(waypoints.isEmpty ? "Tap map to add points" : "\(waypoints.count) Points • \(RouteBuilder.formattedDistance(totalDist))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                } else {
                    Text(freehandCoordinates.isEmpty ? (isFreehandDrawingMode ? "1 finger draws • 2 fingers scroll" : "Scroll & move map freely") : "Drawn Path • \(RouteBuilder.formattedDistance(totalDist))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                if displayRouteCoordinates.count >= 2 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                            .foregroundStyle(LocusTheme.accent)
                        Text("ETA: \(RouteBuilder.formattedETA(estDuration))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(LocusTheme.accent)
                    }
                }
            }

            Spacer()

            if routeMethod == .freehand {
                Button {
                    withAnimation {
                        isFreehandDrawingMode.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isFreehandDrawingMode ? "pencil.tip" : "hand.raised.fill")
                        Text(isFreehandDrawingMode ? "Draw" : "Pan")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isFreehandDrawingMode ? .black : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(isFreehandDrawingMode ? LocusTheme.accentSecondary : Color.primary.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }

            if routeMethod == .points && !waypoints.isEmpty {
                Button {
                    waypoints.removeLast()
                    if waypoints.count >= 2 {
                        buildPointsRoute()
                    } else {
                        calculatedRoute.removeAll()
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if routeMethod == .freehand && !freehandCoordinates.isEmpty {
                Button {
                    clearAllRouteData()
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Button {
                showRouteSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(LocusTheme.accent)

            if displayRouteCoordinates.count >= 2 {
                Button {
                    mapSaveRouteName = SavedRoute.suggestedName(
                        waypoints: waypoints,
                        method: routeMethod,
                        distance: totalDist
                    )
                    showMapSaveRouteAlert = true
                } label: {
                    Image(systemName: "bookmark")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(LocusTheme.accent)
                .accessibilityLabel("Save Route")

                Button {
                    playRoute()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Follow")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(LocusTheme.statusGood))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search places", text: $searchText)
                .textInputAutocapitalization(.words)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    searchFocused = false
                }
                .onChange(of: searchText) { _, value in
                    search.query = value
                }
            if searchFocused || !searchText.isEmpty {
                Button {
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear and dismiss keyboard")
            }
            if searchFocused {
                Button("Done") {
                    searchFocused = false
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(LocusTheme.accent)
            }
        }
        .padding(12)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(search.results.prefix(5), id: \.self) { item in
                Button {
                    select(completion: item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
            }
        }
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var mapChromeButtons: some View {
        HStack(spacing: 4) {
            chromeIconButton("square.3.layers.3d") {
                session.mapStyleIndex = (session.mapStyleIndex + 1) % 3
            }

            // Theme / UI Customization Button
            chromeIconButton("paintpalette.fill") {
                showThemeSheet = true
            }
            .foregroundStyle(session.accentTheme.primaryColor)

            // Route Feature Button
            chromeIconButton("point.topleft.down.to.point.bottomright.curvepath") {
                withAnimation {
                    routeModeActive.toggle()
                }
            }
            .foregroundStyle(routeModeActive ? LocusTheme.accent : .primary)

            if session.pin != nil {
                chromeIconButton("star.circle") {
                    SoundManager.play(.tap)
                    if let pin = session.pin {
                        let name = session.suggestedFavoriteName(for: pin, fallback: pinPlaceName)
                        favoriteNameInput = name
                        pendingFavoriteCoordinate = pin
                        showFavoritePrompt = true
                    }
                }
            }
        }
        .padding(6)
        .locusGlass(.clear, in: Capsule())
        .contentShape(Capsule())
    }

    private var locateButton: some View {
        Button {
            searchFocused = false
            goToCurrentLocation()
        } label: {
            Image(systemName: "location.fill")
                .font(.body.weight(.semibold))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Circle())
        .foregroundStyle(.primary)
        .contentShape(Circle())
        .accessibilityLabel("Current location")
    }

    private func dropPinView(proxy: MapProxy) -> some View {
        MapDropPin(
            selected: pinSelected,
            isDragging: isDraggingPin,
            onSelect: {
                searchFocused = false
                suppressNextMapTap = true
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    pinSelected.toggle()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    suppressNextMapTap = false
                }
            },
            onRemove: {
                suppressNextMapTap = true
                withAnimation {
                    session.pin = nil
                    pinSelected = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    suppressNextMapTap = false
                }
            },
            onDragBegan: {
                searchFocused = false
                suppressNextMapTap = true
                pinSelected = false
                isDraggingPin = true
            },
            onDragMoved: { globalPoint in
                if let coord = proxy.convert(globalPoint, from: .global) {
                    session.pin = coord
                }
            },
            onDragEnded: {
                isDraggingPin = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    suppressNextMapTap = false
                }
            }
        )
    }

    private func waypointPinView(index: Int, wp: RouteWaypoint) -> some View {
        WaypointPinView(
            index: index,
            total: waypoints.count,
            stopDuration: wp.stopDuration,
            isSelected: selectedWaypointId == wp.id,
            onSelect: {
                selectedWaypointId = (selectedWaypointId == wp.id) ? nil : wp.id
            },
            onRemove: {
                removeWaypoint(at: index)
            },
            onToggleStop: {
                editingStopWaypointIndex = index
            }
        )
    }

    @MapContentBuilder
    private var waypointAnnotations: some MapContent {
        if routeModeActive && routeMethod == .points {
            ForEach(waypoints) { wp in
                Annotation("", coordinate: wp.coordinate, anchor: .center) {
                    let idx = waypoints.firstIndex(where: { $0.id == wp.id }) ?? 0
                    waypointPinView(index: idx, wp: wp)
                }
            }
        }
    }

    @MapContentBuilder
    private var routePolylines: some MapContent {
        if session.isFollowingRoute && !session.remainingRouteCoordinates.isEmpty {
            if session.completedRouteCoordinates.count > 1 {
                MapPolyline(coordinates: session.completedRouteCoordinates)
                    .stroke(
                        routeMethod == .freehand ? LocusTheme.accentSecondary.opacity(0.3) : LocusTheme.accent.opacity(0.3),
                        style: StrokeStyle(lineWidth: max(3, session.pathWidth.width - 1.5), lineCap: .round, lineJoin: .round, dash: [6, 4])
                    )
            }

            if session.remainingRouteCoordinates.count > 1 {
                MapPolyline(coordinates: session.remainingRouteCoordinates)
                    .stroke(
                        (routeMethod == .freehand ? LocusTheme.accentSecondary : LocusTheme.accent).opacity(0.35),
                        style: StrokeStyle(lineWidth: session.pathWidth.glowWidth, lineCap: .round, lineJoin: .round)
                    )

                MapPolyline(coordinates: session.remainingRouteCoordinates)
                    .stroke(
                        routeMethod == .freehand ? LocusTheme.accentSecondary : LocusTheme.accent,
                        style: StrokeStyle(lineWidth: session.pathWidth.width, lineCap: .round, lineJoin: .round)
                    )

                MapPolyline(coordinates: session.remainingRouteCoordinates)
                    .stroke(
                        Color.white.opacity(session.isRoutePaused ? 0.25 : 0.75),
                        style: StrokeStyle(
                            lineWidth: max(2, session.pathWidth.width * 0.45),
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [8, 12],
                            dashPhase: pathDashPhase
                        )
                    )
            }
        } else if displayRouteCoordinates.count > 1 {
            MapPolyline(coordinates: displayRouteCoordinates)
                .stroke(
                    (routeMethod == .freehand ? LocusTheme.accentSecondary : LocusTheme.accent).opacity(0.25),
                    style: StrokeStyle(lineWidth: session.pathWidth.glowWidth, lineCap: .round, lineJoin: .round)
                )

            MapPolyline(coordinates: displayRouteCoordinates)
                .stroke(
                    routeMethod == .freehand ? LocusTheme.accentSecondary : LocusTheme.accent,
                    style: StrokeStyle(
                        lineWidth: session.pathWidth.width,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }

        if routeModeActive && routeMethod == .freehand && freehandCoordinates.count > 1 && calculatedRoute.isEmpty {
            MapPolyline(coordinates: freehandCoordinates)
                .stroke(
                    LocusTheme.accentSecondary,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [4, 4])
                )
        }
    }

    private var spoofPuckView: some View {
        ZStack {
            if session.isFollowingRoute {
                Circle()
                    .stroke((session.isRoutePaused ? Color.orange : LocusTheme.accent).opacity(0.6), lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .scaleEffect(session.isRoutePaused ? 1.0 : (puckPulsing ? 1.35 : 0.85))
                    .opacity(session.isRoutePaused ? 0.6 : (puckPulsing ? 0.0 : 0.85))
            }
            Circle().fill((session.isRoutePaused ? Color.orange : LocusTheme.accent).opacity(0.25))
                .frame(width: 38, height: 38)
            Circle().fill(session.isRoutePaused ? Color.orange : LocusTheme.accent)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
    }

    private func goToCurrentLocation() {
        let meters: CLLocationDistance = 900
        withAnimation(.easeInOut(duration: 0.35)) {
            if session.isSpoofing, let sim = session.simulated {
                position = .region(MKCoordinateRegion(
                    center: sim,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else if let real = session.realCoordinate {
                position = .region(MKCoordinateRegion(
                    center: real,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else {
                position = .userLocation(
                    followsHeading: false,
                    fallback: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                        latitudinalMeters: 2000,
                        longitudinalMeters: 2000
                    ))
                )
            }
        }
    }

    private func chromeIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func select(completion: MKLocalSearchCompletion) {
        Task {
            let request = MKLocalSearch.Request(completion: completion)
            if let response = try? await MKLocalSearch(request: request).start(),
               let item = response.mapItems.first {
                let coord = item.placemark.coordinate
                let title = item.name ?? completion.title
                await MainActor.run {
                    if routeModeActive && routeMethod == .points {
                        waypoints.append(RouteWaypoint(coordinate: coord, name: title))
                        if waypoints.count >= 2 {
                            buildPointsRoute()
                        }
                    } else {
                        session.pin = coord
                        pinPlaceName = title
                    }
                    position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1200, longitudinalMeters: 1200))
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                    session.addFavorite(name: title, coordinate: coord)
                    session.pushNamedRecent(name: title, coordinate: coord)
                }
            }
        }
    }

    private func importGPX(_ url: URL) {
        do {
            let track = try GPXCodec.parseTrack(url)
            importedGPXTrack = track
            calculatedRoute = RouteBuilder.sample(coordinates: track.coordinates, every: 10)
            routeModeActive = true
            if let first = track.coordinates.first {
                session.pin = first
                position = .region(MKCoordinateRegion(center: first, latitudinalMeters: 2000, longitudinalMeters: 2000))
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }

    private func exportGPX() {
        let gpx: String
        if let track = importedGPXTrack, !track.isEmpty {
            gpx = GPXCodec.export(track)
        } else {
            let path = displayRouteCoordinates
            guard !path.isEmpty else {
                session.lastError = "Nothing to export."
                return
            }
            gpx = GPXCodec.export(path)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Locus-Route.gpx")
        do {
            try gpx.data(using: .utf8)?.write(to: url)
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.keyWindow?.rootViewController {
                root.present(av, animated: true)
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}

@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    var query: String = "" {
        didSet {
            completer.queryFragment = query
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
        Task { @MainActor in self.results = items }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
