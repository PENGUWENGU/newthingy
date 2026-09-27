import CoreLocation
import SwiftUI

struct RoutePlannerSheet: View {
    @Binding var selectedMethod: RouteMethod
    @Binding var waypoints: [CLLocationCoordinate2D]
    @Binding var snapToRoads: Bool
    @Binding var routeCoords: [CLLocationCoordinate2D]
    @Binding var drawnPath: [CLLocationCoordinate2D]
    @Binding var isRouting: Bool

    var onBuildRoadRoute: () -> Void
    var onBuildDirectRoute: () -> Void
    var onReverseRoute: () -> Void
    var onLoopRoute: () -> Void
    var onPlay: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onClearAll: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    private var activePath: [CLLocationCoordinate2D] {
        if !routeCoords.isEmpty { return routeCoords }
        if !drawnPath.isEmpty { return drawnPath }
        return []
    }

    private var totalDistance: CLLocationDistance {
        RouteBuilder.totalDistance(coordinates: activePath)
    }

    private var estimatedDurationText: String {
        RouteBuilder.formattedDuration(distance: totalDistance, speedMPS: session.currentSpeedMPS)
    }

    var body: some View {
        NavigationStack {
            List {
                // Method Switcher Section
                Section {
                    Picker("Route Method", selection: $selectedMethod) {
                        ForEach(RouteMethod.allCases) { method in
                            Label(method.rawValue, systemImage: method.icon)
                                .tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                    Text(selectedMethod.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Summary Stats Section if we have route data
                if !activePath.isEmpty {
                    Section("Route Statistics") {
                        HStack {
                            Label("Distance", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                            Spacer()
                            Text(RouteBuilder.formattedDistance(totalDistance))
                                .font(.subheadline.monospaced().weight(.semibold))
                        }
                        HStack {
                            Label("Est. Duration", systemImage: "clock")
                            Spacer()
                            Text(estimatedDurationText)
                                .font(.subheadline.monospaced().weight(.semibold))
                        }
                        HStack {
                            Label("Points Count", systemImage: "circle.grid.cross")
                            Spacer()
                            Text("\(activePath.count) points")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Method Specific Section
                if selectedMethod == .points {
                    pointsMethodSection
                } else {
                    freehandMethodSection
                }

                // Actions Section
                Section("Playback & File") {
                    Button(action: {
                        dismiss()
                        onPlay()
                    }) {
                        Label("Follow Route", systemImage: "play.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(activePath.count >= 2 ? LocusTheme.accent : .secondary)
                    }
                    .disabled(activePath.count < 2)

                    Button(action: onImportGPX) {
                        Label("Import GPX Track", systemImage: "square.and.arrow.down")
                    }

                    Button(action: onExportGPX) {
                        Label("Export GPX Track", systemImage: "square.and.arrow.up")
                    }
                    .disabled(activePath.isEmpty)

                    if !activePath.isEmpty || !waypoints.isEmpty || !drawnPath.isEmpty {
                        Button(role: .destructive, action: onClearAll) {
                            Label("Clear All Route Data", systemImage: "trash")
                        }
                    }
                }

                Section {
                    Text("Routes follow Apple Maps roads & paths or custom straight lines according to the active method. Speed variations simulate natural movement.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Route Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    // MARK: - Points Method View
    @ViewBuilder
    private var pointsMethodSection: some View {
        Section("Waypoints Configuration") {
            Toggle(isOn: $snapToRoads) {
                Label("Snap to Roads / Paths", systemImage: "road.lanes")
            }
            .tint(LocusTheme.accent)

            HStack(spacing: 8) {
                Button("Add Current Spoof") {
                    if let sim = session.simulated {
                        waypoints.append(sim)
                    } else if let pin = session.pin {
                        waypoints.append(pin)
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption)

                if let pin = session.pin {
                    Button("Add Pin") {
                        waypoints.append(pin)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }

            if waypoints.count >= 2 {
                HStack {
                    Button {
                        onReverseRoute()
                    } label: {
                        Label("Reverse", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)

                    Spacer()

                    Button {
                        onLoopRoute()
                    } label: {
                        Label("Loop to Start", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }

                Button {
                    if snapToRoads {
                        onBuildRoadRoute()
                    } else {
                        onBuildDirectRoute()
                    }
                } label: {
                    if isRouting {
                        HStack {
                            ProgressView()
                            Text("Calculating Road Route…")
                        }
                    } else {
                        Label(
                            snapToRoads ? "Calculate Road Route" : "Build Direct Point Route",
                            systemImage: snapToRoads ? "road.lanes.curved.right" : "ruler"
                        )
                        .font(.body.weight(.semibold))
                    }
                }
                .disabled(isRouting)
            }
        }

        Section("Waypoints List (\(waypoints.count))") {
            if waypoints.isEmpty {
                Text("No waypoints added yet. Tap on the map to add waypoint pins.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(waypoints.enumerated()), id: \.offset) { index, coord in
                    HStack {
                        ZStack {
                            Circle()
                                .fill(index == 0 ? LocusTheme.statusGood : (index == waypoints.count - 1 ? LocusTheme.accentSecondary : LocusTheme.accent))
                                .frame(width: 22, height: 22)
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(index == 0 ? "Start Point" : (index == waypoints.count - 1 ? "End Point" : "Waypoint #\(index + 1)"))
                                .font(.subheadline.weight(.medium))
                            Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            withAnimation {
                                waypoints.remove(at: index)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onDelete { indexSet in
                    waypoints.remove(atOffsets: indexSet)
                }

                if !waypoints.isEmpty {
                    Button(role: .destructive) {
                        waypoints.removeAll()
                    } label: {
                        Text("Clear All Waypoints")
                    }
                }
            }
        }
    }

    // MARK: - Freehand Method View
    @ViewBuilder
    private var freehandMethodSection: some View {
        Section("Freehand Sketching") {
            Text("Touch and drag your finger smoothly across the map to draw any custom route in real-time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if drawnPath.isEmpty {
                HStack {
                    Image(systemName: "hand.draw")
                        .font(.title2)
                        .foregroundStyle(LocusTheme.accentSecondary)
                    Text("No freehand drawing yet. Switch to the map and drag to sketch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    Label("Drawn Coordinates", systemImage: "pencil.line")
                    Spacer()
                    Text("\(drawnPath.count) points")
                        .font(.subheadline.monospaced())
                }

                HStack {
                    Button {
                        onLoopRoute()
                    } label: {
                        Label("Close Loop", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)

                    Spacer()

                    Button {
                        onReverseRoute()
                    } label: {
                        Label("Reverse Path", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }

                Button(role: .destructive) {
                    drawnPath.removeAll()
                } label: {
                    Label("Clear Freehand Sketch", systemImage: "trash")
                }
            }
        }
    }
}
