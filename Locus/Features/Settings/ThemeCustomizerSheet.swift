import SwiftUI

struct ThemeCustomizerSheet: View {
    @ObservedObject var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    enum CustomTarget: String, CaseIterable, Identifiable {
        case primary = "Primary Accent"
        case secondary = "Secondary Accent"
        case glassTint = "Glass Tint"
        case completionFlash = "Route Complete Flash"
        var id: String { rawValue }
    }

    enum ColorFormat: String, CaseIterable, Identifiable {
        case hex = "HEX"
        case rgb = "RGB"
        case hsb = "HSB / HSL"
        case palette = "Palette"
        var id: String { rawValue }
    }

    @State private var customTarget: CustomTarget = .primary
    @State private var colorFormat: ColorFormat = .hex

    // Working color state
    @State private var hexInput: String = ""
    @State private var redVal: Double = 89
    @State private var greenVal: Double = 198
    @State private var blueVal: Double = 184
    @State private var hueVal: Double = 172
    @State private var satVal: Double = 55
    @State private var briVal: Double = 78
    @State private var nativeColor: Color = .teal

    @State private var soundEnabled: Bool = SoundManager.shared.isSoundEnabled

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Accent Preset Themes
                presetThemesSection

                // MARK: - Custom Color Studio (RGB, HEX, HSB, Palette)
                customColorStudioSection

                // MARK: - Path Line Thickness
                pathThicknessSection

                // MARK: - UI Glass & Material Style
                appearanceStyleSection

                // MARK: - Sound Feedback
                soundEffectsSection

                // MARK: - Map Waypoint Badges
                mapOverlaysSection
            }
            .navigationTitle("Customize UI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        SoundManager.play(.tap)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
            .onAppear {
                soundEnabled = SoundManager.shared.isSoundEnabled
                loadCurrentColors()
            }
        }
    }

    // MARK: - Sections
    
    private var soundEffectsSection: some View {
        Section {
            Toggle("Button Audio Feedback", isOn: $soundEnabled)
                .onChange(of: soundEnabled) { _, newValue in
                    SoundManager.shared.isSoundEnabled = newValue
                    if newValue {
                        SoundManager.play(.tap)
                    }
                }
        } header: {
            Text("Sound & Feedback")
        } footer: {
            Text("Plays subtle system sound effects when tapping controls, toggling modes, and completing actions.")
        }
    }

    private var presetThemesSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(AccentColorTheme.allCases) { theme in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                session.setAccentTheme(theme)
                                loadCurrentColors()
                            }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    if theme == .custom {
                                        Circle()
                                            .fill(
                                                AngularGradient(
                                                    gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]),
                                                    center: .center
                                                )
                                            )
                                            .frame(width: 44, height: 44)
                                    } else {
                                        Circle()
                                            .fill(theme.primaryColor)
                                            .frame(width: 44, height: 44)
                                    }

                                    Circle()
                                        .stroke(Color.white, lineWidth: session.accentTheme == theme ? 3 : 0)

                                    if session.accentTheme == theme {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .black))
                                            .foregroundStyle(theme == .custom || theme == .monochrome ? .white : .black)
                                    }
                                }
                                .shadow(color: (theme == .custom ? Color.purple : theme.primaryColor).opacity(0.35), radius: 5, y: 2)

                                Text(theme.rawValue.components(separatedBy: " ").first ?? theme.rawValue)
                                    .font(.caption2.weight(session.accentTheme == theme ? .bold : .regular))
                                    .foregroundStyle(session.accentTheme == theme ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
        } header: {
            Text("Accent Themes")
        } footer: {
            Text("Select a curated color theme, or choose 'Custom' to dial in your exact RGB, HEX, or HSB colors.")
        }
    }

    private var customColorStudioSection: some View {
        Section {
            // Target Selector: Primary vs Secondary
            Picker("Target Color", selection: $customTarget) {
                ForEach(CustomTarget.allCases) { target in
                    Text(target.rawValue).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: customTarget) { _, _ in
                loadCurrentColors()
            }

            // Color Format Switcher: HEX / RGB / HSB / Palette
            Picker("Format", selection: $colorFormat) {
                ForEach(ColorFormat.allCases) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            }
            .pickerStyle(.segmented)

            // Dynamic Format Controls
            switch colorFormat {
            case .hex:
                hexControls
            case .rgb:
                rgbControls
            case .hsb:
                hsbControls
            case .palette:
                paletteControls
            }

            // Live Swatch & Values Preview
            colorPreviewCard
        } header: {
            HStack {
                Text("Custom Color Studio")
                Spacer()
                if session.accentTheme == .custom {
                    Text("ACTIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(LocusTheme.accent)
                }
            }
        } footer: {
            Text("Primary accent styles route lines, telemetry, and main buttons; Secondary accent styles freehand paths and stop highlights.")
        }
    }

    // MARK: - Color Format Controls

    private var hexControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HEX Color Code")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("#")
                    .font(.headline.monospaced())
                    .foregroundStyle(.secondary)

                TextField("RRGGBB", text: $hexInput)
                    .font(.headline.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: hexInput) { _, val in
                        var cleaned = val.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
                        if cleaned.count > 6 {
                            cleaned = String(cleaned.prefix(6))
                        }
                        if cleaned != hexInput {
                            hexInput = cleaned
                        }
                        if cleaned.count == 6, let _ = Color(hex: "#" + cleaned) {
                            applyHex("#" + cleaned)
                        }
                    }

                if hexInput.count == 6 && Color(hex: "#" + hexInput) != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        }
        .padding(.vertical, 4)
    }

    private var rgbControls: some View {
        VStack(spacing: 12) {
            rgbSliderRow(label: "Red", value: $redVal, color: .red)
            rgbSliderRow(label: "Green", value: $greenVal, color: .green)
            rgbSliderRow(label: "Blue", value: $blueVal, color: .blue)
        }
        .padding(.vertical, 4)
    }

    private func rgbSliderRow(label: String, value: Binding<Double>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...255, step: 1) {
                Text(label)
            }
            .tint(color)
            .onChange(of: value.wrappedValue) { _, _ in
                applyRGB()
            }
        }
    }

    private var hsbControls: some View {
        VStack(spacing: 12) {
            // Hue
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Hue")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(Int(hueVal))°")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $hueVal, in: 0...360, step: 1)
                    .tint(.purple)
                    .onChange(of: hueVal) { _, _ in applyHSB() }
            }

            // Saturation
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Saturation")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(Int(satVal))%")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $satVal, in: 0...100, step: 1)
                    .tint(.cyan)
                    .onChange(of: satVal) { _, _ in applyHSB() }
            }

            // Brightness
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Brightness")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(Int(briVal))%")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $briVal, in: 0...100, step: 1)
                    .tint(.yellow)
                    .onChange(of: briVal) { _, _ in applyHSB() }
            }
        }
        .padding(.vertical, 4)
    }

    private var paletteControls: some View {
        ColorPicker("Choose from Palette", selection: $nativeColor, supportsOpacity: false)
            .onChange(of: nativeColor) { _, newColor in
                let hex = newColor.toHex()
                applyHex(hex)
            }
            .padding(.vertical, 4)
    }

    private var colorPreviewCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(currentColor)
                .frame(width: 50, height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: currentColor.opacity(0.4), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(currentHex)
                    .font(.subheadline.monospaced().weight(.bold))
                    .foregroundStyle(.primary)

                Text("RGB: (\(Int(redVal)), \(Int(greenVal)), \(Int(blueVal)))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)

                Text("HSB: (\(Int(hueVal))°, \(Int(satVal))%, \(Int(briVal))%)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if session.accentTheme != .custom {
                Button("Apply") {
                    session.setAccentTheme(.custom)
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(currentColor)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    // MARK: - Other Settings

    private var pathThicknessSection: some View {
        Section {
            Picker("Path Thickness", selection: Binding(
                get: { session.pathWidth },
                set: { session.setPathWidth($0) }
            )) {
                ForEach(PathWidthPreference.allCases) { width in
                    Text(width.rawValue).tag(width)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Live Route Line Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Capsule()
                    .fill(session.accentTheme.primaryColor)
                    .frame(width: 100, height: session.pathWidth.width)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Route Line Thickness")
        } footer: {
            Text("Controls the stroke width of planned and active navigation paths on the map.")
        }
    }

    private var appearanceStyleSection: some View {
        Section {
            Picker("Appearance Style", selection: Binding(
                get: { session.uiAppearance },
                set: { session.setUIAppearance($0) }
            )) {
                ForEach(UIAppearanceStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Interface Style")
        } footer: {
            Text("Liquid Glass uses Apple's native glass shaders; High Contrast uses solid opaque backing for maximum outdoor visibility.")
        }
    }

    private var mapOverlaysSection: some View {
        Section {
            Toggle("Show Waypoint Numbers", isOn: Binding(
                get: { session.showWaypointLabels },
                set: { session.setShowWaypointLabels($0) }
            ))
        } header: {
            Text("Map Overlays")
        } footer: {
            Text("Display sequential numbered badges on route waypoints on the map.")
        }
    }

    // MARK: - Helpers

    private var currentHex: String {
        switch customTarget {
        case .primary: return ThemePreference.customPrimaryHex
        case .secondary: return ThemePreference.customSecondaryHex
        case .glassTint: return ThemePreference.glassTintHex
        case .completionFlash: return ThemePreference.completionFlashHex
        }
    }

    private var currentColor: Color {
        Color(hex: currentHex) ?? {
            switch customTarget {
            case .primary: return Color(red: 0.35, green: 0.78, blue: 0.72)
            case .secondary: return Color(red: 0.95, green: 0.55, blue: 0.28)
            case .glassTint: return Color(red: 0.35, green: 0.78, blue: 0.72)
            case .completionFlash: return Color.green
            }
        }()
    }

    private func loadCurrentColors() {
        let hex = currentHex
        let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        hexInput = clean
        if let color = Color(hex: hex) {
            let rgb = color.componentsRGB()
            redVal = Double(rgb.r)
            greenVal = Double(rgb.g)
            blueVal = Double(rgb.b)

            let hsb = color.componentsHSB()
            hueVal = hsb.h
            satVal = hsb.s
            briVal = hsb.b

            nativeColor = color
        }
    }

    private func applyTargetHex(_ hex: String) {
        switch customTarget {
        case .primary:
            session.setCustomPrimaryHex(hex)
        case .secondary:
            session.setCustomSecondaryHex(hex)
        case .glassTint:
            ThemePreference.glassTintHex = hex
            ThemePreference.hasCustomGlassTint = true
        case .completionFlash:
            ThemePreference.completionFlashHex = hex
        }
    }

    private func applyHex(_ hex: String) {
        applyTargetHex(hex)
        if let color = Color(hex: hex) {
            let rgb = color.componentsRGB()
            redVal = Double(rgb.r)
            greenVal = Double(rgb.g)
            blueVal = Double(rgb.b)

            let hsb = color.componentsHSB()
            hueVal = hsb.h
            satVal = hsb.s
            briVal = hsb.b

            nativeColor = color
        }
    }

    private func applyRGB() {
        let r = Int(redVal)
        let g = Int(greenVal)
        let b = Int(blueVal)
        let color = Color.fromRGB(r: r, g: g, b: b)
        let hex = color.toHex()
        hexInput = String(hex.dropFirst())
        nativeColor = color

        let hsb = color.componentsHSB()
        hueVal = hsb.h
        satVal = hsb.s
        briVal = hsb.b

        applyTargetHex(hex)
    }

    private func applyHSB() {
        let color = Color.fromHSB(h: hueVal, s: satVal, b: briVal)
        let hex = color.toHex()
        hexInput = String(hex.dropFirst())
        nativeColor = color

        let rgb = color.componentsRGB()
        redVal = Double(rgb.r)
        greenVal = Double(rgb.g)
        blueVal = Double(rgb.b)

        applyTargetHex(hex)
    }
}
