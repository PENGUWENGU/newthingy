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

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss
    @State private var editingWaypoint: RouteWaypoint?
    @State private var editNameText = ""

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

    private var estimatedDuration: TimeInterval {
        RouteBuilder.estimatedDuration(distance: totalDistance, speed: session.currentSpeedMPS)
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
                        Text("Add Waypoints")
                    } footer: {
                        Text("You can also tap anywhere on the map in Points mode to add waypoints.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Section("Waypoints (\(waypoints.count))") {
                        if waypoints.isEmpty {
                            Text("No waypoints added yet. Tap on the map or use the buttons above.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(waypoints.enumerated()), id: \.element.id) { index, wp in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(badgeColor(for: index, total: waypoints.count))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Text("\(index + 1)")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.black)
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(wp.name.isEmpty ? (index == 0 ? "Start Point" : (index == waypoints.count - 1 ? "End Point" : "Waypoint \(index + 1)")) : wp.name)
                                            .font(.subheadline.weight(.medium))
                                        Text(String(format: "%.5f, %.5f", wp.coordinate.latitude, wp.coordinate.longitude))
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
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
                                        if let first = waypoints.first, waypoints.last != first {
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
                                        .tint(.white)
                                } else {
                                    Label(
                                        connectionType == .road ? "Calculate Road Route" : "Build Straight Route",
                                        systemImage: connectionType == .road ? "road.lanes" : "line.diagonal"
                                    )
                                    .font(.headline)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(LocusTheme.accent)
                        .foregroundStyle(.black)
                        .disabled(waypoints.count < 2 || isRouting)
                    }
                }

                // MARK: - Method 2: Freehand
                if method == .freehand {
                    Section("Freehand Drawing") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Image(systemName: "hand.draw.fill")
                                    .font(.title2)
                                    .foregroundStyle(LocusTheme.accentSecondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Continuous Touch Sketch")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Drag your finger across the map to sketch freeform trajectories.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)

                            HStack(spacing: 16) {
                                LabeledContent("Raw points", value: "\(freehandCoordinates.count)")
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
                                    if let first = freehandCoordinates.first, freehandCoordinates.last != first {
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

                // MARK: - Route Summary & Follow
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
                                Text("Est. Duration (\(String(format: "%.1f", session.currentSpeedMPS)) m/s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(RouteBuilder.formattedDuration(estimatedDuration))
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(LocusTheme.accent)
                            }
                        }
                        .padding(.vertical, 4)

                        Toggle(isOn: $loopRoute) {
                            Label("Repeat route continuously (Loop)", systemImage: "repeat")
                                .font(.subheadline)
                        }

                        if session.isFollowingRoute {
                            VStack(spacing: 8) {
                                ProgressView(value: session.routeProgress)
                                    .tint(LocusTheme.accent)
                                Button {
                                    onStopRoute()
                                } label: {
                                    HStack {
                                        Spacer()
                                        Label("Stop Following Route", systemImage: "stop.fill")
                                            .font(.headline)
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(LocusTheme.danger)
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

                // MARK: - GPX Exchange
                Section("GPX Exchange") {
                    Button(action: onImportGPX) {
                        Label("Import GPX Track", systemImage: "square.and.arrow.down")
                    }
                    Button(action: onExportGPX) {
                        Label("Export GPX Track", systemImage: "square.and.arrow.up")
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
