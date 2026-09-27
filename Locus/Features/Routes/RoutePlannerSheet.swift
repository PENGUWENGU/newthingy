import CoreLocation
import SwiftUI

struct RoutePlannerSheet: View {
    @Binding var method: RouteCreationMethod
    @Binding var connectionType: RouteConnectionType
    @Binding var waypoints: [RouteWaypoint]
    @Binding var freehandCoordinates: [CLLocationCoordinate2D]
    @Binding var calculatedRoute: [CLLocationCoordinate2D]
    @Binding var isRouting: Bool
    @Binding var loopRoute: Bool

    var onBuildRoute: () -> Void
    var onPlayRoute: () -> Void
    var onStopRoute: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onSmoothFreehand: () -> Void
    var onClearRoute: () -> Void
    var onAddPinAsWaypoint: () -> Void
    var onAddSpoofAsWaypoint: () -> Void
    var onLoadRoute: (SavedRoute) -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var editingWaypoint: RouteWaypoint?
    @State private var editNameText = ""

    // Saved Routes UI State
    @State private var showSaveAlert = false
    @State private var saveRouteNameText = ""
    @State private var showSaveSuccessBanner = false
    @State private var routeToRename: SavedRoute?
    @State private var renameText = ""
    @State private var showRenameAlert = false

    private var activePath: [CLLocationCoordinate2D] {
        if !calculatedRoute.isEmpty {
            return calculatedRoute
        } else if method == .freehand {
            return freehandCoordinates
        } else {
            return waypoints.map(\.coordinate)
        }
    }

    private var totalDistance: CLLocationDistance {
        RouteBuilder.totalDistance(of: activePath)
    }

    private var totalStopsDuration: TimeInterval {
        waypoints.reduce(0) { $0 + $1.stopDuration }
    }

    private var estimatedDuration: TimeInterval {
        RouteBuilder.estimatedDuration(distance: totalDistance, speed: session.currentSpeedMPS) + totalStopsDuration
    }

    var body: some View {
        NavigationStack {
            List {
                // Method Switcher: Points vs Freehand
                Section {
                    Picker("Route Method", selection: $method) {
                        ForEach(RouteCreationMethod.allCases) { m in
                            Label(m.rawValue, systemImage: m.icon).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                }

                // MARK: - Method 1: Points
                if method == .points {
                    Section("Connection Type") {
                        Picker("Routing", selection: $connectionType) {
                            ForEach(RouteConnectionType.allCases) { type in
                                Label(type.rawValue, systemImage: type.icon).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Text("Default Mode")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if session.defaultConnectionType == connectionType {
                                Label("Default", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(LocusTheme.statusGood)
                            } else {
                                Button("Set as Default") {
                                    withAnimation {
                                        session.setDefaultConnectionType(connectionType)
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(LocusTheme.accent)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Section {
                        HStack(spacing: 12) {
                            Button {
                                onAddPinAsWaypoint()
                            } label: {
                                Label("Add Pin", systemImage: "mappin.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .disabled(session.pin == nil)

                            Button {
                                onAddSpoofAsWaypoint()
                            } label: {
                                Label("Add Spoof", systemImage: "location.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .disabled(session.simulated == nil)

                            Spacer()

                            if !waypoints.isEmpty {
                                Button("Clear", role: .destructive) {
                                    waypoints.removeAll()
                                    calculatedRoute.removeAll()
                                }
                                .font(.subheadline)
                            }
                        }
                    } header: {
                        Text("Waypoints (\(waypoints.count))")
                    } footer: {
                        Text("Tap anywhere on the map to add sequential waypoints. Drag rows to reorder.")
                    }

                    if !waypoints.isEmpty {
                        Section {
                            ForEach(Array(waypoints.enumerated()), id: \.element.id) { index, wp in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(wp.stopDuration > 0 ? Color.orange : badgeColor(for: index, total: waypoints.count))
                                        .frame(width: 24, height: 24)
                                        .overlay {
                                            Text("\(index + 1)")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.black)
                                        }

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(wp.name.isEmpty ? "Waypoint \(index + 1)" : wp.name)
                                                .font(.subheadline.weight(.medium))

                                            if wp.stopDuration > 0 {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "clock.badge.fill")
                                                    Text(wp.formattedStopDuration)
                                                }
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.orange)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(Color.orange.opacity(0.18)))
                                            }
                                        }

                                        Text(String(format: "%.5f, %.5f", wp.coordinate.latitude, wp.coordinate.longitude))
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    // Stop Duration Preset Menu
                                    Menu {
                                        Button("Pass-through (No Stop)") {
                                            setWaypointStop(at: index, duration: 0)
                                        }
                                        Divider()
                                        Button("15s Stop") {
                                            setWaypointStop(at: index, duration: 15)
                                        }
                                        Button("30s Stop") {
                                            setWaypointStop(at: index, duration: 30)
                                        }
                                        Button("1m Stop") {
                                            setWaypointStop(at: index, duration: 60)
                                        }
                                        Button("2m Stop") {
                                            setWaypointStop(at: index, duration: 120)
                                        }
                                        Button("5m Stop") {
                                            setWaypointStop(at: index, duration: 300)
                                        }
                                    } label: {
                                        Image(systemName: wp.stopDuration > 0 ? "clock.circle.fill" : "clock")
                                            .font(.body)
                                            .foregroundStyle(wp.stopDuration > 0 ? Color.orange : Color.secondary)
                                            .frame(width: 32, height: 32)
                                    }
                                }
                            }
                            .onMove { indices, newOffset in
                                waypoints.move(fromOffsets: indices, toOffset: newOffset)
                                calculatedRoute.removeAll()
                            }
                            .onDelete { indices in
                                waypoints.remove(atOffsets: indices)
                                calculatedRoute.removeAll()
                            }

                            if waypoints.count >= 2 {
                                HStack {
                                    Button {
                                        waypoints.reverse()
                                        calculatedRoute.removeAll()
                                    } label: {
                                        Label("Reverse", systemImage: "arrow.up.arrow.down")
                                            .font(.footnote)
                                    }

                                    Spacer()

                                    Button {
                                        if let first = waypoints.first, let last = waypoints.last,
                                           (first.coordinate.latitude != last.coordinate.latitude || first.coordinate.longitude != last.coordinate.longitude) {
                                            waypoints.append(RouteWaypoint(coordinate: first.coordinate, name: "Return to Start"))
                                            calculatedRoute.removeAll()
                                        }
                                    } label: {
                                        Label("Loop to Start", systemImage: "arrow.triangle.2.circlepath")
                                            .font(.footnote)
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        Button {
                            onBuildRoute()
                        } label: {
                            HStack {
                                Spacer()
                                if isRouting {
                                    ProgressView()
                                        .padding(.trailing, 6)
                                    Text("Calculating Route…")
                                        .font(.headline)
                                } else {
                                    Label(
                                        connectionType == .road ? "Recalculate Roads Route" : "Update Direct Path",
                                        systemImage: connectionType == .road ? "arrow.triangle.turn.up.right.diamond.fill" : "line.diagonal"
                                    )
                                    .font(.headline)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(waypoints.count < 2 || isRouting)
                    }
                }

                // MARK: - Method 2: Freehand
                if method == .freehand {
                    Section("Freehand Sketch Controls") {
                        Text("Drag your finger across the map to draw your path freely. Locus smooths and samples coordinates to create a seamless GPS track.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if !freehandCoordinates.isEmpty {
                            HStack {
                                LabeledContent("Raw Points", value: "\(freehandCoordinates.count)")
                                Spacer()
                                LabeledContent("Smoothed", value: "\(calculatedRoute.isEmpty ? freehandCoordinates.count : calculatedRoute.count)")
                            }
                            .font(.caption)
                        }

                        if !freehandCoordinates.isEmpty {
                            HStack(spacing: 12) {
                                Button {
                                    onSmoothFreehand()
                                } label: {
                                    Label("Smooth Path", systemImage: "waveform.path")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    if let first = freehandCoordinates.first, let last = freehandCoordinates.last,
                                       (first.latitude != last.latitude || first.longitude != last.longitude) {
                                        freehandCoordinates.append(first)
                                        onSmoothFreehand()
                                    }
                                } label: {
                                    Label("Close Loop", systemImage: "circle.circle")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                Button("Clear", role: .destructive) {
                                    onClearRoute()
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }

                // MARK: - Route Overview & Follow / Save
                if activePath.count >= 2 {
                    Section("Route Overview") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Distance")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(RouteBuilder.formattedDistance(totalDistance))
                                    .font(.title3.weight(.bold))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(session.isFollowingRoute ? "Remaining ETA" : "Est. Duration (\(String(format: "%.1f", session.currentSpeedMPS)) m/s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(session.isFollowingRoute ? RouteBuilder.formattedETA(session.remainingRouteDuration) : RouteBuilder.formattedETA(estimatedDuration))
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(session.isRoutePaused ? .orange : LocusTheme.accent)
                            }
                        }
                        .padding(.vertical, 4)

                        Toggle(isOn: $loopRoute) {
                            Label("Repeat route continuously (Loop)", systemImage: "repeat")
                                .font(.subheadline)
                        }

                        // Save Route Button
                        HStack(spacing: 10) {
                            Button {
                                saveRouteNameText = SavedRoute.suggestedName(
                                    waypoints: waypoints,
                                    method: method,
                                    distance: totalDistance
                                )
                                showSaveAlert = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Label("Save Route", systemImage: "bookmark.fill")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                            .tint(LocusTheme.accent)

                            if showSaveSuccessBanner {
                                Label("Saved!", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(LocusTheme.statusGood)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }

                        if session.isFollowingRoute {
                            VStack(spacing: 10) {
                                HStack {
                                    Label(
                                        session.isRoutePaused ? "Path Paused" : "Following Path",
                                        systemImage: session.isRoutePaused ? "pause.circle.fill" : "figure.walk.motion"
                                    )
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(session.isRoutePaused ? .orange : LocusTheme.statusGood)

                                    Spacer()

                                    Text("\(Int(session.routeProgress * 100))%")
                                        .font(.caption.monospacedDigit().weight(.bold))
                                        .foregroundStyle(.secondary)
                                }

                                ProgressView(value: session.routeProgress)
                                    .tint(session.isRoutePaused ? .orange : LocusTheme.accent)

                                HStack(spacing: 10) {
                                    Button {
                                        withAnimation {
                                            session.togglePauseRoute()
                                        }
                                    } label: {
                                        HStack {
                                            Spacer()
                                            Label(
                                                session.isRoutePaused ? "Resume Path" : "Pause Path",
                                                systemImage: session.isRoutePaused ? "play.fill" : "pause.fill"
                                            )
                                            .font(.headline)
                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(session.isRoutePaused ? LocusTheme.statusGood : .orange)
                                    .foregroundStyle(session.isRoutePaused ? .black : .white)

                                    Button {
                                        onStopRoute()
                                    } label: {
                                        HStack {
                                            Spacer()
                                            Label("Stop", systemImage: "stop.fill")
                                                .font(.headline)
                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(LocusTheme.danger)
                                }
                            }
                        } else {
                            Button {
                                onPlayRoute()
                                dismiss()
                            } label: {
                                HStack {
                                    Spacer()
                                    Label("Follow Route", systemImage: "play.fill")
                                        .font(.headline)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(LocusTheme.statusGood)
                            .foregroundStyle(.black)
                        }
                    }
                }

                // MARK: - Saved Routes Section
                Section {
                    if session.savedRoutes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("No Saved Routes", systemImage: "bookmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Create a points or freehand route above, then tap 'Save Route' to store your frequent walking and driving routes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(session.savedRoutes) { route in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(route.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        Text("\(route.formattedDistance) • \(route.formattedDate)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    HStack(spacing: 4) {
                                        Text(route.method.rawValue)
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule().fill(route.method == .points ? LocusTheme.accent.opacity(0.18) : LocusTheme.accentSecondary.opacity(0.18))
                                            )
                                            .foregroundStyle(route.method == .points ? LocusTheme.accent : LocusTheme.accentSecondary)

                                        if route.isLoop {
                                            Image(systemName: "repeat")
                                                .font(.caption2.weight(.bold))
                                                .padding(4)
                                                .background(Circle().fill(Color.secondary.opacity(0.15)))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                HStack(spacing: 10) {
                                    Button {
                                        onLoadRoute(route)
                                    } label: {
                                        Label("Load", systemImage: "arrow.down.circle")
                                            .font(.footnote.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        onLoadRoute(route)
                                        onPlayRoute()
                                        dismiss()
                                    } label: {
                                        Label("Follow", systemImage: "play.fill")
                                            .font(.footnote.weight(.semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(LocusTheme.statusGood)
                                    .foregroundStyle(.black)

                                    Spacer()

                                    Menu {
                                        Button {
                                            routeToRename = route
                                            renameText = route.name
                                            showRenameAlert = true
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }

                                        Button {
                                            exportSavedRouteGPX(route)
                                        } label: {
                                            Label("Export GPX", systemImage: "square.and.arrow.up")
                                        }

                                        Button(role: .destructive) {
                                            withAnimation {
                                                session.deleteRoute(id: route.id)
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 32, height: 32)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    withAnimation {
                                        session.deleteRoute(id: route.id)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    routeToRename = route
                                    renameText = route.name
                                    showRenameAlert = true
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Saved Routes")
                        Spacer()
                        if !session.savedRoutes.isEmpty {
                            Text("\(session.savedRoutes.count)")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(LocusTheme.accent.opacity(0.2)))
                                .foregroundStyle(LocusTheme.accent)
                        }
                    }
                }

                // MARK: - GPX Exchange
                Section("GPX Exchange") {
                    Button(action: onImportGPX) {
                        Label("Import GPX Track", systemImage: "square.and.arrow.down")
                    }
                    Button(action: onExportGPX) {
                        Label("Export Current GPX Track", systemImage: "square.and.arrow.up")
                    }
                    .disabled(activePath.isEmpty)
                }
            }
            .navigationTitle("Route Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if method == .points && !waypoints.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Save Route", isPresented: $showSaveAlert) {
                TextField("Route Name", text: $saveRouteNameText)
                Button("Save") {
                    saveCurrentRoute()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a name to save this route to your device.")
            }
            .alert("Rename Route", isPresented: $showRenameAlert) {
                TextField("New Name", text: $renameText)
                Button("Save") {
                    if let target = routeToRename {
                        session.renameRoute(id: target.id, to: renameText)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a new name for this saved route.")
            }
        }
    }

    private func saveCurrentRoute() {
        let route = SavedRoute(
            name: saveRouteNameText,
            method: method,
            connectionType: connectionType,
            waypoints: waypoints,
            coordinates: activePath,
            distanceMeters: totalDistance,
            isLoop: loopRoute
        )
        session.saveRoute(route)
        withAnimation {
            showSaveSuccessBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                showSaveSuccessBanner = false
            }
        }
    }

    private func exportSavedRouteGPX(_ route: SavedRoute) {
        let gpx = GPXCodec.export(route.clCoordinates)
        let safeName = route.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).gpx")
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

    private func badgeColor(for index: Int, total: Int) -> Color {
        if index == 0 {
            return LocusTheme.statusGood
        } else if index == total - 1 {
            return LocusTheme.accentSecondary
        } else {
            return LocusTheme.accent
        }
    }
}
