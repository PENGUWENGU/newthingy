import SwiftUI
import CoreLocation

/// Interactive, dynamic speed customizer with live animated speedometer preview,
/// realistic presets matching user requirements, and a 1–5 mph random variance range.
struct SpeedCustomizerSheet: View {
    @ObservedObject var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    // Staged Draft State before saving
    @State private var stagedSpeedText: String = ""
    @State private var stagedUnit: SpeedUnit = .mph
    @State private var stagedVarianceMPH: Double = 3.0
    @State private var stagedRandomnessEnabled: Bool = true
    @State private var stagedMode: TravelMode = .drive
    @State private var isCustomOverrideActive: Bool = false
    @State private var errorMessage: String? = nil

    // Dynamic Live Preview Stage State
    @State private var liveGaugeVelocity: Double = 35.0
    @State private var miniVehicleOffset: CGFloat = 0.0
    @State private var needleAngle: Double = 0.0
    @State private var isAcceleratingPulse: Bool = false
    @State private var previewTimer: Timer? = nil

    private var currentDraftSpeedMPS: Double {
        if isCustomOverrideActive, let parsed = SpeedInput.parse(stagedSpeedText, unit: stagedUnit) {
            return parsed
        }
        return stagedMode.baseSpeed
    }

    private var currentDraftSpeedInUnit: Double {
        stagedUnit.fromMPS(currentDraftSpeedMPS)
    }

    private var speedVarianceInUnit: Double {
        stagedUnit.fromMPS(stagedVarianceMPH / 2.236936)
    }

    private var speedRangeMin: Double {
        max(0.2, currentDraftSpeedInUnit - (stagedRandomnessEnabled ? speedVarianceInUnit : 0.0))
    }

    private var speedRangeMax: Double {
        currentDraftSpeedInUnit + (stagedRandomnessEnabled ? speedVarianceInUnit : 0.0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // MARK: - 1. Dynamic Live Speedometer & Motion Preview Stage
                    dynamicPreviewStage

                    // MARK: - 2. Realistic Speed Presets (Walk 1.6 mph, Drive 35 mph, etc.)
                    presetsSection

                    // MARK: - 3. Custom Speed Input
                    customSpeedInputSection

                    // MARK: - 4. Speed Randomness Range (1–5 mph for Life360)
                    varianceSection

                    // MARK: - 5. Error Notice if any
                    if let errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 14)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Movement Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        stopPreviewLoop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Changes") {
                        saveChanges()
                    }
                    .font(.headline)
                }
            }
            .onAppear {
                initializeDraft()
                startPreviewLoop()
            }
            .onDisappear {
                stopPreviewLoop()
            }
        }
    }

    // MARK: - Dynamic Preview Stage

    private var dynamicPreviewStage: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Live Kinematic Preview", systemImage: "gauge.with.needle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(session.primaryAccentColor)
                Spacer()
                Text(stagedRandomnessEnabled ? "Wandering Range: ±\(String(format: "%.1f", stagedVarianceMPH)) mph" : "Constant Speed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            // Animated Speedometer & Road Deck
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(session.primaryAccentColor.opacity(0.2), lineWidth: 1)
                    )

                VStack(spacing: 10) {
                    // Gauge & Digital Tachometer
                    ZStack {
                        // Outer arc
                        Circle()
                            .trim(from: 0.15, to: 0.85)
                            .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(90))
                            .frame(width: 130, height: 130)

                        // Colored active arc
                        Circle()
                            .trim(from: 0.15, to: 0.15 + (CGFloat(min(1.0, max(0.0, liveGaugeVelocity / 70.0))) * 0.70))
                            .stroke(
                                LinearGradient(
                                    colors: [session.primaryAccentColor, session.secondaryAccentColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .rotationEffect(.degrees(90))
                            .frame(width: 130, height: 130)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: liveGaugeVelocity)

                        // Center digital readout
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f", stagedUnit.fromMPS(liveGaugeVelocity / 2.236936)))
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.primary)

                            Text(stagedUnit.label)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 120)

                    // Range spread indicator
                    HStack(spacing: 16) {
                        VStack(spacing: 2) {
                            Text("Min Simulated")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f %@", speedRangeMin, stagedUnit.label))
                                .font(.caption.weight(.semibold))
                        }

                        Divider()
                            .frame(height: 20)

                        VStack(spacing: 2) {
                            Text("Target Cruising")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f %@", currentDraftSpeedInUnit, stagedUnit.label))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(session.primaryAccentColor)
                        }

                        Divider()
                            .frame(height: 20)

                        VStack(spacing: 2) {
                            Text("Max Simulated")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f %@", speedRangeMax, stagedUnit.label))
                                .font(.caption.weight(.semibold))
                        }
                    }

                    // Mini Track with Vehicle traversing smoothly
                    ZStack(alignment: .leading) {
                        // Road surface
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 28)

                        // Center dashed road markings
                        HStack(spacing: 8) {
                            ForEach(0..<10) { _ in
                                Rectangle()
                                    .fill(Color.primary.opacity(0.12))
                                    .frame(width: 10, height: 2)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Animated traveler icon
                        Image(systemName: stagedMode.icon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(session.primaryAccentColor)
                            .padding(6)
                            .background(Circle().fill(Color(uiColor: .systemBackground)).shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1))
                            .offset(x: miniVehicleOffset)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                    // Fun Interactive Throttle Button
                    Button {
                        triggerAccelerationPulse()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isAcceleratingPulse ? "flame.fill" : "bolt.fill")
                                .foregroundStyle(.orange)
                            Text(isAcceleratingPulse ? "Accelerating..." : "Tap to Test Throttle Kick")
                                .font(.caption.weight(.bold))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 6)
                }
                .padding(.vertical, 14)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mode Presets")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                presetCard(mode: .walk, displayMph: 1.6, subtitle: "1–2 mph")
                presetCard(mode: .sidewalk, displayMph: 1.2, subtitle: "Stroll")
                presetCard(mode: .run, displayMph: 6.0, subtitle: "Jogging")
                presetCard(mode: .cycle, displayMph: 12.0, subtitle: "Bicycle")
                presetCard(mode: .bus, displayMph: 22.0, subtitle: "Transit")
                presetCard(mode: .drive, displayMph: 35.0, subtitle: "Car (Life360)")
            }
            .padding(.horizontal, 16)
        }
    }

    private func presetCard(mode: TravelMode, displayMph: Double, subtitle: String) -> some View {
        let isSelected = !isCustomOverrideActive && stagedMode == mode
        return Button {
            SoundManager.play(.tap)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                stagedMode = mode
                isCustomOverrideActive = false
                let speedInUnit = stagedUnit.fromMPS(mode.baseSpeed)
                stagedSpeedText = String(format: "%.1f", speedInUnit)
                liveGaugeVelocity = mode.baseSpeed * 2.236936
                errorMessage = nil
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isSelected ? .white : session.primaryAccentColor)

                Text(mode.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(String(format: "%.1f %@", stagedUnit.fromMPS(mode.baseSpeed), stagedUnit.label))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)

                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? session.primaryAccentColor : Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom Speed Input Section

    private var customSpeedInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom Speed Override")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            VStack(spacing: 12) {
                // Unit Picker
                Picker("Unit", selection: $stagedUnit) {
                    ForEach(SpeedUnit.allCases) { u in
                        Text(u.label).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: stagedUnit) { _, newUnit in
                    let mps = currentDraftSpeedMPS
                    stagedSpeedText = String(format: "%.1f", newUnit.fromMPS(mps))
                }

                // Text field
                HStack {
                    TextField("Enter custom speed", text: $stagedSpeedText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: stagedSpeedText) { _, newText in
                            if let parsed = SpeedInput.parse(newText, unit: stagedUnit) {
                                isCustomOverrideActive = true
                                liveGaugeVelocity = parsed * 2.236936
                                errorMessage = nil
                            }
                        }

                    Text(stagedUnit.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)
                }

                if isCustomOverrideActive {
                    HStack {
                        Label("Custom speed override active", systemImage: "slider.horizontal.3")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(session.primaryAccentColor)
                        Spacer()
                        Button("Revert to Preset") {
                            withAnimation {
                                isCustomOverrideActive = false
                                stagedSpeedText = String(format: "%.1f", stagedUnit.fromMPS(stagedMode.baseSpeed))
                                liveGaugeVelocity = stagedMode.baseSpeed * 2.236936
                            }
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemGroupedBackground)))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Variance Range (1–5 mph)

    private var varianceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Life360 Anti-Detection & Realism")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            VStack(spacing: 14) {
                Toggle(isOn: $stagedRandomnessEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Random Speed Fluctuations")
                            .font(.subheadline.weight(.semibold))
                        Text("Varies throttle continuously so speed is NOT constant. Life360 flags constant speeds as stationary botting.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if stagedRandomnessEnabled {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Speed Variance Range:")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("±\(String(format: "%.0f", stagedVarianceMPH)) mph")
                                .font(.caption.weight(.black).monospacedDigit())
                                .foregroundStyle(session.primaryAccentColor)
                        }

                        // 1 to 5 mph picker pills
                        HStack(spacing: 8) {
                            ForEach([1.0, 2.0, 3.0, 4.0, 5.0], id: \.self) { rangeVal in
                                let isPicked = abs(stagedVarianceMPH - rangeVal) < 0.1
                                Button {
                                    SoundManager.play(.toggle)
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                        stagedVarianceMPH = rangeVal
                                    }
                                } label: {
                                    Text("±\(Int(rangeVal)) mph")
                                        .font(.caption2.weight(isPicked ? .bold : .medium))
                                        .foregroundStyle(isPicked ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(isPicked ? session.primaryAccentColor : Color.primary.opacity(0.06))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("A ±3 mph variance at 35 mph naturally cycles between 32 and 38 mph, matching real foot throttle pressure.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemGroupedBackground)))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Lifecycle & Actions

    private func initializeDraft() {
        stagedUnit = session.speedUnit
        stagedVarianceMPH = session.speedVarianceMPH
        stagedRandomnessEnabled = session.speedRandomnessEnabled
        stagedMode = session.travelMode

        if let custom = session.customSpeedMPS {
            isCustomOverrideActive = true
            stagedSpeedText = String(format: "%.1f", stagedUnit.fromMPS(custom))
            liveGaugeVelocity = custom * 2.236936
        } else {
            isCustomOverrideActive = false
            stagedSpeedText = String(format: "%.1f", stagedUnit.fromMPS(session.travelMode.baseSpeed))
            liveGaugeVelocity = session.travelMode.baseSpeed * 2.236936
        }
    }

    private func startPreviewLoop() {
        previewTimer?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: true) { _ in
            Task { @MainActor in
                updatePreviewTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        previewTimer = timer
    }

    private func stopPreviewLoop() {
        previewTimer?.invalidate()
        previewTimer = nil
    }

    private func updatePreviewTick() {
        let baseMPH = currentDraftSpeedMPS * 2.236936

        // Oscillate with dynamic speed variance
        if stagedRandomnessEnabled && !isAcceleratingPulse {
            let variance = stagedVarianceMPH
            let wave = sin(Date().timeIntervalSince1970 * 1.8) * variance
            let noise = Double.random(in: -0.3...0.3)
            liveGaugeVelocity = max(0.5, baseMPH + wave + noise)
        } else if !isAcceleratingPulse {
            liveGaugeVelocity = baseMPH
        }

        // Animate mini track vehicle
        let speedMPS = liveGaugeVelocity / 2.236936
        let advance = CGFloat(speedMPS * 0.15 * 6.0)
        miniVehicleOffset += advance
        if miniVehicleOffset > 220 {
            miniVehicleOffset = 0
        }
    }

    private func triggerAccelerationPulse() {
        SoundManager.play(.tap)
        isAcceleratingPulse = true
        withAnimation(.easeIn(duration: 0.4)) {
            liveGaugeVelocity += 12.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.6)) {
                self.isAcceleratingPulse = false
            }
        }
    }

    private func saveChanges() {
        SoundManager.play(.success)
        session.setSpeedUnit(stagedUnit)
        session.setSpeedVariance(stagedVarianceMPH)
        session.setSpeedRandomnessEnabled(stagedRandomnessEnabled)

        if isCustomOverrideActive {
            if session.setCustomSpeed(fromText: stagedSpeedText, unit: stagedUnit) {
                dismiss()
            } else {
                SoundManager.play(.alert)
                errorMessage = "Please enter a valid positive speed number."
            }
        } else {
            session.clearCustomSpeed()
            session.selectTravelMode(stagedMode)
            dismiss()
        }
    }
}
