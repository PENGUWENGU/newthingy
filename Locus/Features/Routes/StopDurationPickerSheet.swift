import SwiftUI

struct StopDurationPickerSheet: View {
    let waypointIndex: Int
    let waypointName: String
    let initialDuration: TimeInterval
    let onSave: (TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var hours: Int = 0
    @State private var minutes: Int = 0
    @State private var seconds: Int = 0

    init(
        waypointIndex: Int,
        waypointName: String,
        initialDuration: TimeInterval,
        onSave: @escaping (TimeInterval) -> Void
    ) {
        self.waypointIndex = waypointIndex
        self.waypointName = waypointName
        self.initialDuration = initialDuration
        self.onSave = onSave

        let total = Int(initialDuration)
        _hours = State(initialValue: total / 3600)
        _minutes = State(initialValue: (total % 3600) / 60)
        _seconds = State(initialValue: total % 60)
    }

    private var totalSeconds: TimeInterval {
        TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    private var formattedTotal: String {
        guard totalSeconds > 0 else { return "Pass-through (No dwell stop)" }
        var parts: [String] = []
        if hours > 0 {
            parts.append("\(hours) \(hours == 1 ? "hour" : "hours")")
        }
        if minutes > 0 {
            parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        }
        if seconds > 0 || parts.isEmpty {
            parts.append("\(seconds) \(seconds == 1 ? "second" : "seconds")")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Selected Dwell Duration Summary
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: totalSeconds > 0 ? "clock.badge.fill" : "arrow.right.circle.fill")
                            .font(.title2)
                            .foregroundStyle(totalSeconds > 0 ? Color.orange : Color.secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(totalSeconds > 0 ? "Dwell Stop Duration" : "Pass-through Waypoint")
                                .font(.subheadline.weight(.semibold))
                            Text(formattedTotal)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(waypointName.isEmpty ? "Waypoint \(waypointIndex + 1)" : waypointName)
                }

                // MARK: - Wheel Pickers
                Section {
                    HStack(spacing: 0) {
                        // Hours
                        VStack(spacing: 2) {
                            Text("Hours")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Picker("Hours", selection: $hours) {
                                ForEach(0...24, id: \.self) { h in
                                    Text("\(h)").tag(h)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        }

                        // Minutes
                        VStack(spacing: 2) {
                            Text("Minutes")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Picker("Minutes", selection: $minutes) {
                                ForEach(0...59, id: \.self) { m in
                                    Text("\(m)").tag(m)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        }

                        // Seconds
                        VStack(spacing: 2) {
                            Text("Seconds")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Picker("Seconds", selection: $seconds) {
                                ForEach(0...59, id: \.self) { s in
                                    Text("\(s)").tag(s)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        }
                    }
                    .frame(height: 140)
                } header: {
                    Text("Customize Stop Duration")
                } footer: {
                    Text("The route simulation will automatically pause and dwell at this waypoint for the selected time before moving to the next point.")
                }

                // MARK: - Quick Presets
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            presetButton(label: "Pass-through", h: 0, m: 0, s: 0)
                            presetButton(label: "15s", h: 0, m: 0, s: 15)
                            presetButton(label: "30s", h: 0, m: 0, s: 30)
                            presetButton(label: "1m", h: 0, m: 1, s: 0)
                            presetButton(label: "2m", h: 0, m: 2, s: 0)
                            presetButton(label: "5m", h: 0, m: 5, s: 0)
                            presetButton(label: "10m", h: 0, m: 10, s: 0)
                            presetButton(label: "30m", h: 0, m: 30, s: 0)
                            presetButton(label: "1h", h: 1, m: 0, s: 0)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Quick Presets")
                }

                // MARK: - Clear Stop Button
                if totalSeconds > 0 {
                    Section {
                        Button(role: .destructive) {
                            onSave(0)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Remove Stop (Pass-through)")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Set Stop Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(totalSeconds)
                        dismiss()
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(LocusTheme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func presetButton(label: String, h: Int, m: Int, s: Int) -> some View {
        let isSelected = hours == h && minutes == m && seconds == s
        return Button {
            hours = h
            minutes = m
            seconds = s
        } label: {
            Text(label)
                .font(.caption.weight(isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .black : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.orange : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}
