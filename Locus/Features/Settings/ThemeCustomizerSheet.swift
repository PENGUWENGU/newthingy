import SwiftUI

struct ThemeCustomizerSheet: View {
    @ObservedObject var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    enum PreviewStageMode: String, CaseIterable, Identifiable {
        case mapSim = "Map Sim"
        case liveActivity = "Live Activity"
        case joystickDeck = "Joystick"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .mapSim: return "map.fill"
            case .liveActivity: return "platter.filled.top.iphone"
            case .joystickDeck: return "gamecontroller.fill"
            }
        }
    }

    enum CustomTarget: String, CaseIterable, Identifiable {
        case primary = "Primary"
        case secondary = "Secondary"
        case textColor = "Text"
        case menuTint = "Menu"
        case glassTint = "Glass"
        case completionFlash = "Flash"

        var id: String { rawValue }

        var fullTitle: String {
            switch self {
            case .primary: return "Primary Accent"
            case .secondary: return "Secondary Accent"
            case .textColor: return "Custom Text Color"
            case .menuTint: return "Menu Surface Tint"
            case .glassTint: return "Background Glass Tint"
            case .completionFlash: return "Route Completion Flash"
            }
        }
    }

    enum ColorFormat: String, CaseIterable, Identifiable {
        case hex = "HEX"
        case rgb = "RGB"
        case hsb = "HSB"
        case palette = "Wheel"
        var id: String { rawValue }
    }

    struct DraftThemeState: Equatable {
        var accentTheme: AccentColorTheme
        var primaryHex: String
        var secondaryHex: String
        var textColorHex: String
        var isCustomTextColorEnabled: Bool
        var menuTintHex: String
        var isMenuTintEnabled: Bool
        var glassTintHex: String
        var isGlassTintEnabled: Bool
        var completionFlashHex: String
        var pathWidth: PathWidthPreference
        var uiAppearance: UIAppearanceStyle
        var showWaypointLabels: Bool

        var effectivePrimary: Color {
            if accentTheme == .custom {
                return Color(hex: primaryHex) ?? Color(red: 0.35, green: 0.78, blue: 0.72)
            }
            return accentTheme.primaryColor
        }

        var effectiveSecondary: Color {
            if accentTheme == .custom {
                return Color(hex: secondaryHex) ?? Color(red: 0.95, green: 0.55, blue: 0.28)
            }
            return accentTheme.secondaryColor
        }

        var effectiveText: Color {
            if isCustomTextColorEnabled, let c = Color(hex: textColorHex) {
                return c
            }
            return .white
        }

        var effectiveGlass: Color {
            if isGlassTintEnabled, let c = Color(hex: glassTintHex) {
                return c
            }
            return Color(red: 0.08, green: 0.10, blue: 0.15)
        }

        var effectiveMenu: Color {
            if isMenuTintEnabled, let c = Color(hex: menuTintHex) {
                return c
            }
            return effectiveGlass
        }

        var effectiveFlash: Color {
            Color(hex: completionFlashHex) ?? Color(red: 0.20, green: 0.83, blue: 0.60)
        }
    }

    struct SurprisePalette {
        let name: String
        let primaryHex: String
        let secondaryHex: String
        let glassHex: String
        let flashHex: String
    }

    private let surprisePalettes: [SurprisePalette] = [
        SurprisePalette(name: "Tokyo Drift Neon", primaryHex: "#00F5D4", secondaryHex: "#FF2A85", glassHex: "#0B132B", flashHex: "#00F5D4"),
        SurprisePalette(name: "Cyberpunk Outrun", primaryHex: "#FFBE0B", secondaryHex: "#FB5607", glassHex: "#1A0B2E", flashHex: "#FF006E"),
        SurprisePalette(name: "Arctic Aurora", primaryHex: "#38BDF8", secondaryHex: "#A855F7", glassHex: "#091526", flashHex: "#34D399"),
        SurprisePalette(name: "Solar Flare", primaryHex: "#FF5E5B", secondaryHex: "#FFCA3A", glassHex: "#1F1114", flashHex: "#FFCA3A"),
        SurprisePalette(name: "Emerald Matrix", primaryHex: "#10B981", secondaryHex: "#06B6D4", glassHex: "#061A14", flashHex: "#34D399"),
        SurprisePalette(name: "Ultraviolet Pulse", primaryHex: "#C084FC", secondaryHex: "#F472B6", glassHex: "#160D29", flashHex: "#C084FC"),
        SurprisePalette(name: "Obsidian Gold", primaryHex: "#F59E0B", secondaryHex: "#FDE047", glassHex: "#141413", flashHex: "#F59E0B")
    ]

    // Saved vs Staged Draft State
    @State private var savedState: DraftThemeState
    @State private var draft: DraftThemeState
    @State private var isComparingOriginal: Bool = false
    @State private var currentSurpriseName: String? = nil

    // Playground Stage State
    @State private var stageMode: PreviewStageMode = .mapSim
    @State private var previewTravelMode: TravelMode = .drive
    @State private var simProgress: Double = 0.28
    @State private var isAutoPlayingSim: Bool = true
    @State private var dashPhase: CGFloat = 0
    @State private var puckPulse: Bool = false
    @State private var previewFlashActive: Bool = false
    @State private var bouncedWaypointIndex: Int? = nil
    @State private var tapRipplePoint: CGPoint? = nil
    @State private var tapRippleScale: CGFloat = 0.2
    @State private var showSavedToast: Bool = false

    // Interactive Mini Joystick State
    @State private var joyStickOffset: CGSize = .zero
    @State private var joyPuckPosition: CGPoint = CGPoint(x: 150, y: 82)
    @State private var joyTrail: [CGPoint] = []

    // Working Color Studio State
    @State private var customTarget: CustomTarget = .primary
    @State private var colorFormat: ColorFormat = .hex
    @State private var hexInput: String = ""
    @State private var redVal: Double = 89
    @State private var greenVal: Double = 198
    @State private var blueVal: Double = 184
    @State private var hueVal: Double = 172
    @State private var satVal: Double = 55
    @State private var briVal: Double = 78
    @State private var nativeColor: Color = .teal
    @State private var soundEnabled: Bool = SoundManager.shared.isSoundEnabled

    private let simTimer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()

    init(session: SpoofSession) {
        self.session = session
        let initial = DraftThemeState(
            accentTheme: session.accentTheme,
            primaryHex: session.customPrimaryHex,
            secondaryHex: session.customSecondaryHex,
            textColorHex: session.customTextColorHex,
            isCustomTextColorEnabled: session.isCustomTextColorEnabled,
            menuTintHex: session.customMenuTintHex,
            isMenuTintEnabled: session.isMenuTintEnabled,
            glassTintHex: session.glassTintHex,
            isGlassTintEnabled: session.isGlassTintEnabled,
            completionFlashHex: session.completionFlashHex,
            pathWidth: session.pathWidth,
            uiAppearance: session.uiAppearance,
            showWaypointLabels: session.showWaypointLabels
        )
        _savedState = State(initialValue: initial)
        _draft = State(initialValue: initial)
    }

    private var activePreview: DraftThemeState {
        isComparingOriginal ? savedState : draft
    }

    private var hasUnsavedChanges: Bool {
        draft != savedState
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Top Interactive Live Preview Stage
                interactivePreviewStage
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .background(Color(UIColor.systemGroupedBackground))

                Divider().opacity(0.3)

                // MARK: - Customization Controls ScrollView
                Form {
                    presetThemesSection
                    customColorStudioSection
                    pathThicknessAndStyleSection
                    soundAndOverlaysSection
                }

                // MARK: - Bottom Save / Revert Action Bar
                bottomCommitBar
            }
            .navigationTitle("Theme Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        SoundManager.play(.tap)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        commitChangesAndSave(closeSheet: true)
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(draft.effectivePrimary)
                }
            }
            .onAppear {
                soundEnabled = SoundManager.shared.isSoundEnabled
                syncEditorSlidersFromDraft()
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    puckPulse = true
                }
            }
            .onReceive(simTimer) { _ in
                tickPlaygroundSimulation()
            }
        }
    }

    // MARK: - Interactive Preview Stage

    private var interactivePreviewStage: some View {
        VStack(spacing: 10) {
            // Stage Header & Mode Switcher
            HStack(spacing: 6) {
                ForEach(PreviewStageMode.allCases) { mode in
                    let isSelected = stageMode == mode
                    Button {
                        SoundManager.play(.tap)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            stageMode = mode
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.caption.weight(.bold))
                            Text(mode.rawValue)
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(isSelected ? .black : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isSelected ? activePreview.effectivePrimary : Color.primary.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Flash Test Button
                Button {
                    triggerPreviewFlash()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("Flash")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(activePreview.effectiveFlash))
                }
                .buttonStyle(.plain)

                // Compare Before/After Button
                if hasUnsavedChanges {
                    Text(isComparingOriginal ? "ORIGINAL" : "COMPARE")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(isComparingOriginal ? .black : activePreview.effectivePrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isComparingOriginal ? Color.orange : Color.primary.opacity(0.10))
                        )
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !isComparingOriginal {
                                        SoundManager.play(.tap)
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            isComparingOriginal = true
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        isComparingOriginal = false
                                    }
                                }
                        )
                }
            }

            // Stage Canvas Card
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.07, blue: 0.11),
                                activePreview.effectiveGlass.opacity(0.85),
                                Color(red: 0.04, green: 0.05, blue: 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Subtle map grid lines
                PlaygroundGridBackground(accent: activePreview.effectivePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                // Selected Stage Content
                Group {
                    switch stageMode {
                    case .mapSim:
                        mapSimStageContent
                    case .liveActivity:
                        liveActivityStageContent
                    case .joystickDeck:
                        joystickStageContent
                    }
                }
                .padding(12)

                // Route Completion Flash Overlay
                if previewFlashActive {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(activePreview.effectiveFlash.opacity(0.48))
                        .overlay(
                            VStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("Route Completed Flash!")
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(.white)
                            }
                            .padding(14)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                        )
                        .transition(.opacity)
                }

                // Saved Confirmation Overlay
                if showSavedToast {
                    VStack {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.black)
                            Text("Theme Saved & Applied!")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.black)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(activePreview.effectivePrimary))
                        .shadow(color: activePreview.effectivePrimary.opacity(0.5), radius: 10)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 196)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [activePreview.effectivePrimary.opacity(0.65), activePreview.effectiveSecondary.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: activePreview.effectivePrimary.opacity(0.18), radius: 12, y: 4)
        }
    }

    // MARK: - Stage 1: Animated Map & Route Simulation

    private var mapSimStageContent: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let p1 = CGPoint(x: w * 0.12, y: h * 0.72)
            let p2 = CGPoint(x: w * 0.48, y: h * 0.34)
            let p3 = CGPoint(x: w * 0.86, y: h * 0.56)
            let puckPt = pointAlongThreePointCurve(p1: p1, p2: p2, p3: p3, t: CGFloat(simProgress))

            ZStack {
                // Tap anywhere to trigger teleport ripple
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                SoundManager.play(.tap)
                                tapRipplePoint = value.location
                                tapRippleScale = 0.2
                                withAnimation(.easeOut(duration: 0.55)) {
                                    tapRippleScale = 2.2
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                                    tapRipplePoint = nil
                                }
                            }
                    )

                // Outer Glow Route Path
                PlaygroundRouteShape(p1: p1, p2: p2, p3: p3)
                    .stroke(
                        LinearGradient(
                            colors: [activePreview.effectivePrimary.opacity(0.35), activePreview.effectiveSecondary.opacity(0.35)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: activePreview.pathWidth.glowWidth + 3, lineCap: .round, lineJoin: .round)
                    )

                // Main Route Path
                PlaygroundRouteShape(p1: p1, p2: p2, p3: p3)
                    .stroke(
                        LinearGradient(
                            colors: [activePreview.effectivePrimary, activePreview.effectiveSecondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: activePreview.pathWidth.width, lineCap: .round, lineJoin: .round)
                    )

                // Marching Animated Dashes
                PlaygroundRouteShape(p1: p1, p2: p2, p3: p3)
                    .stroke(
                        Color.white.opacity(0.75),
                        style: StrokeStyle(
                            lineWidth: max(2, activePreview.pathWidth.width * 0.42),
                            lineCap: .round,
                            dash: [7, 10],
                            dashPhase: dashPhase
                        )
                    )

                // Tap Ripple
                if let ripple = tapRipplePoint {
                    Circle()
                        .stroke(activePreview.effectiveSecondary, lineWidth: 2)
                        .frame(width: 36, height: 36)
                        .scaleEffect(tapRippleScale)
                        .opacity(Double(2.2 - tapRippleScale))
                        .position(ripple)
                }

                // Interactive Waypoint Pins
                ForEach(Array([p1, p2, p3].enumerated()), id: \.offset) { idx, pt in
                    Button {
                        SoundManager.play(.dwell)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) {
                            bouncedWaypointIndex = idx
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation { bouncedWaypointIndex = nil }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(idx == 2 ? activePreview.effectiveSecondary : activePreview.effectivePrimary)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.4), radius: 3)

                            if activePreview.showWaypointLabels {
                                Text("\(idx + 1)")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundStyle(.black)
                            } else {
                                Circle()
                                    .fill(Color.black.opacity(0.65))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .scaleEffect(bouncedWaypointIndex == idx ? 1.38 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .position(pt)
                }

                // Moving Spoof Puck
                ZStack {
                    Circle()
                        .stroke(activePreview.effectivePrimary.opacity(0.65), lineWidth: 2)
                        .frame(width: 38, height: 38)
                        .scaleEffect(puckPulse ? 1.32 : 0.82)
                        .opacity(puckPulse ? 0.15 : 0.85)

                    Circle()
                        .fill(activePreview.effectivePrimary.opacity(0.28))
                        .frame(width: 28, height: 28)

                    Circle()
                        .fill(activePreview.effectivePrimary)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
                .position(puckPt)

                // Top & Bottom Mini Chrome Overlays
                VStack {
                    // Mini Top Status & Mode Bar
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text(currentSurpriseName ?? activePreview.accentTheme.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(activePreview.effectiveText)
                            .lineLimit(1)

                        Spacer()

                        Text(session.speedUnit.format(previewTravelMode.baseSpeed))
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(activePreview.effectivePrimary))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(previewPanelBackground(cornerRadius: 12))

                    Spacer()

                    // Interactive Mini Bottom Control Bar
                    HStack(spacing: 6) {
                        ForEach([TravelMode.walk, .cycle, .drive]) { mode in
                            let selected = previewTravelMode == mode
                            Button {
                                SoundManager.play(.toggle)
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                    previewTravelMode = mode
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 10, weight: .bold))
                                    Text(mode.title)
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(selected ? .black : activePreview.effectiveText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(selected ? activePreview.effectivePrimary : Color.white.opacity(0.10))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        Button {
                            SoundManager.play(.toggle)
                            isAutoPlayingSim.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isAutoPlayingSim ? "pause.fill" : "play.fill")
                                Text(isAutoPlayingSim ? "Simulating" : "Paused")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(activePreview.effectiveSecondary))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(previewPanelBackground(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: - Stage 2: Interactive Live Activity Scrubber

    private var liveActivityStageContent: some View {
        let minsLeft = max(1, Int(ceil((1.0 - simProgress) * 24.0)))
        let distMeters = max(0, (1.0 - simProgress) * 4200.0)
        let stopLoc = max(0.02, min(0.99, simProgress))

        return VStack(alignment: .leading, spacing: 10) {
            // Mock Lock Screen Live Activity Card
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(activePreview.effectivePrimary.opacity(0.24))
                            .frame(width: 36, height: 36)
                        Image(systemName: previewTravelMode.icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(activePreview.effectivePrimary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(simProgress >= 0.98 ? "Arriving now" : "Go in \(minsLeft) mins")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(activePreview.effectiveText)

                        Text("\(previewTravelMode.title) • Downtown Station")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(activePreview.effectiveText.opacity(0.78))
                    }

                    Spacer()

                    Text(session.speedUnit.format(previewTravelMode.baseSpeed))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(activePreview.effectivePrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }

                // Progress Track with Moving Vehicle Icon
                GeometryReader { geo in
                    let clamped = CGFloat(min(1.0, max(0.0, stopLoc)))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .frame(height: 8)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [activePreview.effectivePrimary, activePreview.effectiveSecondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(14, geo.size.width * clamped), height: 8)

                        ZStack {
                            Circle()
                                .fill(activePreview.effectivePrimary)
                                .frame(width: 24, height: 24)
                                .shadow(color: activePreview.effectivePrimary.opacity(0.75), radius: 5)
                            Image(systemName: previewTravelMode.icon)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                        }
                        .offset(x: max(0, min(geo.size.width - 24, (geo.size.width - 24) * clamped)))
                    }
                }
                .frame(height: 24)

                HStack {
                    Label("Arrive at 8:42 PM", systemImage: "mappin.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(activePreview.effectiveText)
                    Spacer()
                    Text("\(RouteBuilder.formattedDistance(distMeters)) • \(minsLeft) min")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(activePreview.effectivePrimary)
                }
            }
            .padding(12)
            .background(previewPanelBackground(cornerRadius: 18))

            // Interactive Scrubber Slider
            HStack(spacing: 8) {
                Button {
                    SoundManager.play(.toggle)
                    isAutoPlayingSim.toggle()
                } label: {
                    Image(systemName: isAutoPlayingSim ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(activePreview.effectivePrimary)
                }
                .buttonStyle(.plain)

                Text("Scrub Route")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))

                Slider(value: Binding(
                    get: { simProgress },
                    set: { newVal in
                        isAutoPlayingSim = false
                        simProgress = newVal
                        if newVal >= 0.99 && !previewFlashActive {
                            triggerPreviewFlash()
                        }
                    }
                ), in: 0...1)
                .tint(activePreview.effectivePrimary)

                Text("\(Int(simProgress * 100))%")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(activePreview.effectiveSecondary)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, 6)
        }
    }

    // MARK: - Stage 3: Interactive Mini Joystick Playground

    private var joystickStageContent: some View {
        HStack(spacing: 14) {
            // Left: Draggable Mini Thumbstick
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(activePreview.effectiveMenu.opacity(0.85))
                        .frame(width: 108, height: 108)
                        .overlay(
                            Circle()
                                .stroke(activePreview.effectivePrimary.opacity(0.45), lineWidth: 1.5)
                        )

                    Circle()
                        .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: 68, height: 68)

                    // Thumbstick Knob
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [activePreview.effectivePrimary, activePreview.effectiveSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .shadow(color: activePreview.effectivePrimary.opacity(0.6), radius: 6)
                        .overlay(
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.black)
                        )
                        .offset(joyStickOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let maxR: CGFloat = 32
                                    let dx = value.translation.width
                                    let dy = value.translation.height
                                    let dist = hypot(dx, dy)
                                    if dist > maxR {
                                        joyStickOffset = CGSize(width: dx / dist * maxR, height: dy / dist * maxR)
                                    } else {
                                        joyStickOffset = value.translation
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                                        joyStickOffset = .zero
                                    }
                                }
                        )
                }

                Text("Drag Joystick!")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(activePreview.effectiveText.opacity(0.85))
            }

            // Right: Live Steering Arena
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    // Trail Path
                    if joyTrail.count > 1 {
                        Path { path in
                            path.move(to: joyTrail[0])
                            for pt in joyTrail.dropFirst() {
                                path.addLine(to: pt)
                            }
                        }
                        .stroke(
                            LinearGradient(
                                colors: [activePreview.effectiveSecondary.opacity(0.2), activePreview.effectivePrimary],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: activePreview.pathWidth.width, lineCap: .round, lineJoin: .round)
                        )
                    }

                    // Steered Puck
                    ZStack {
                        Circle()
                            .fill(activePreview.effectivePrimary.opacity(0.28))
                            .frame(width: 30, height: 30)
                        Circle()
                            .fill(activePreview.effectivePrimary)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                    .position(
                        x: min(max(18, joyPuckPosition.x), geo.size.width - 18),
                        y: min(max(18, joyPuckPosition.y), geo.size.height - 18)
                    )

                    VStack {
                        HStack {
                            Text("LIVE JOYSTICK ARENA")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(activePreview.effectivePrimary)
                            Spacer()
                            Button("Clear Trail") {
                                SoundManager.play(.tap)
                                joyTrail.removeAll()
                            }
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(activePreview.effectiveSecondary)
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        Spacer()
                    }
                }
            }
        }
    }

    private func previewPanelBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            if activePreview.uiAppearance == .highContrast {
                shape.fill(activePreview.effectiveMenu.opacity(0.95))
                shape.stroke(Color.white.opacity(0.25), lineWidth: 1.2)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(activePreview.effectiveMenu.opacity(activePreview.uiAppearance == .minimal ? 0.35 : 0.65))
                shape.stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
        }
    }

    // MARK: - Form Sections

    private var presetThemesSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    // Surprise Me Button
                    Button {
                        rollSurprisePalette()
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.pink, .orange, .yellow, .mint, .cyan, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 46, height: 46)
                                Image(systemName: "dice.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                            .shadow(color: .pink.opacity(0.4), radius: 6, y: 2)

                            Text("Surprise!")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(draft.effectivePrimary)
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(AccentColorTheme.allCases) { theme in
                        let isSelected = draft.accentTheme == theme
                        Button {
                            SoundManager.play(.toggle)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                                currentSurpriseName = nil
                                draft.accentTheme = theme
                                syncEditorSlidersFromDraft()
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
                                            .frame(width: 46, height: 46)
                                    } else {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [theme.primaryColor, theme.secondaryColor],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 46, height: 46)
                                    }

                                    Circle()
                                        .stroke(Color.white, lineWidth: isSelected ? 3 : 0)
                                        .frame(width: 46, height: 46)

                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 15, weight: .black))
                                            .foregroundStyle(theme == .custom || theme == .monochrome ? .white : .black)
                                    }
                                }
                                .shadow(color: (theme == .custom ? draft.effectivePrimary : theme.primaryColor).opacity(0.35), radius: 5, y: 2)

                                Text(theme.rawValue.components(separatedBy: " ").first ?? theme.rawValue)
                                    .font(.caption2.weight(isSelected ? .bold : .regular))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
        } header: {
            HStack {
                Text("Preset Themes & Vibe Generator")
                Spacer()
                if let surprise = currentSurpriseName {
                    Text(surprise)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(draft.effectivePrimary)
                }
            }
        } footer: {
            Text("Tap 'Surprise!' to generate a custom designer palette or pick a preset. All changes preview above before you hit Save.")
        }
    }

    private var customColorStudioSection: some View {
        Section {
            // Scrollable Target Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CustomTarget.allCases) { target in
                        let selected = customTarget == target
                        Button {
                            SoundManager.play(.tap)
                            customTarget = target
                            syncEditorSlidersFromDraft()
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(colorForTarget(target))
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                                Text(target.rawValue)
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(selected ? .black : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selected ? draft.effectivePrimary : Color.primary.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            // Optional Enable Toggle for Text / Menu / Glass Tints
            if customTarget == .textColor {
                Toggle("Enable Custom Text Color", isOn: $draft.isCustomTextColorEnabled)
            } else if customTarget == .menuTint {
                Toggle("Enable Custom Menu Surface Tint", isOn: $draft.isMenuTintEnabled)
            } else if customTarget == .glassTint {
                Toggle("Enable Custom Background Glass Tint", isOn: $draft.isGlassTintEnabled)
            }

            // Color Format Switcher
            Picker("Color Input Mode", selection: $colorFormat) {
                ForEach(ColorFormat.allCases) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            }
            .pickerStyle(.segmented)

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

            colorPreviewCard
        } header: {
            HStack {
                Text("Custom Color Studio — \(customTarget.fullTitle)")
                Spacer()
            }
        }
    }

    private var hexControls: some View {
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
                    if cleaned.count == 6, Color(hex: "#" + cleaned) != nil {
                        updateDraftHex("#" + cleaned, updateSliders: true)
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

    private var rgbControls: some View {
        VStack(spacing: 10) {
            rgbSliderRow(label: "Red", value: $redVal, color: .red)
            rgbSliderRow(label: "Green", value: $greenVal, color: .green)
            rgbSliderRow(label: "Blue", value: $blueVal, color: .blue)
        }
        .padding(.vertical, 4)
    }

    private func rgbSliderRow(label: String, value: Binding<Double>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...255, step: 1)
                .tint(color)
                .onChange(of: value.wrappedValue) { _, _ in
                    applyRGBToDraft()
                }
        }
    }

    private var hsbControls: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
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
                    .onChange(of: hueVal) { _, _ in applyHSBToDraft() }
            }

            VStack(alignment: .leading, spacing: 2) {
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
                    .onChange(of: satVal) { _, _ in applyHSBToDraft() }
            }

            VStack(alignment: .leading, spacing: 2) {
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
                    .onChange(of: briVal) { _, _ in applyHSBToDraft() }
            }
        }
        .padding(.vertical, 4)
    }

    private var paletteControls: some View {
        ColorPicker("Select \(customTarget.fullTitle)", selection: $nativeColor, supportsOpacity: false)
            .onChange(of: nativeColor) { _, newColor in
                updateDraftHex(newColor.toHex(), updateSliders: true)
            }
            .padding(.vertical, 4)
    }

    private var colorPreviewCard: some View {
        let swatch = colorForTarget(customTarget)
        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(swatch)
                .frame(width: 48, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: swatch.opacity(0.4), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(hexForTarget(customTarget))
                    .font(.subheadline.monospaced().weight(.bold))
                Text("RGB (\(Int(redVal)), \(Int(greenVal)), \(Int(blueVal))) • HSB (\(Int(hueVal))°, \(Int(satVal))%, \(Int(briVal))%)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if customTarget == .completionFlash {
                Button("Test Flash") {
                    triggerPreviewFlash()
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(draft.effectiveFlash)
                .foregroundStyle(.black)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    private var pathThicknessAndStyleSection: some View {
        Section {
            Picker("Route Line Thickness", selection: $draft.pathWidth) {
                ForEach(PathWidthPreference.allCases) { width in
                    Text(width.rawValue).tag(width)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.pathWidth) { _, _ in
                SoundManager.play(.toggle)
            }

            Picker("UI Material Style", selection: $draft.uiAppearance) {
                ForEach(UIAppearanceStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.uiAppearance) { _, _ in
                SoundManager.play(.toggle)
            }
        } header: {
            Text("Path Geometry & Glass Material")
        } footer: {
            Text("Watch the mini-map and HUD panels in the preview stage above respond immediately to thickness and glass material changes.")
        }
    }

    private var soundAndOverlaysSection: some View {
        Section {
            Toggle("Show Waypoint Numbers on Map", isOn: $draft.showWaypointLabels)
                .onChange(of: draft.showWaypointLabels) { _, _ in
                    SoundManager.play(.toggle)
                }

            Toggle("Button Audio Feedback", isOn: $soundEnabled)
                .onChange(of: soundEnabled) { _, newValue in
                    SoundManager.shared.isSoundEnabled = newValue
                    if newValue {
                        SoundManager.play(.tap)
                    }
                }
        } header: {
            Text("Overlays & Feedback")
        }
    }

    // MARK: - Bottom Save / Revert Bar

    private var bottomCommitBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack(spacing: 12) {
                Button {
                    SoundManager.play(.toggle)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        draft = savedState
                        currentSurpriseName = nil
                        syncEditorSlidersFromDraft()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Revert")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(hasUnsavedChanges ? .primary : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .disabled(!hasUnsavedChanges)

                Button {
                    commitChangesAndSave(closeSheet: false)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: hasUnsavedChanges ? "sparkles" : "checkmark.circle.fill")
                        Text(hasUnsavedChanges ? "Save & Apply Theme" : "Theme Saved")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [draft.effectivePrimary, draft.effectiveSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: draft.effectivePrimary.opacity(0.35), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Simulation & Helper Logic

    private func tickPlaygroundSimulation() {
        dashPhase -= 1.4

        if isAutoPlayingSim {
            let speedFactor: Double
            switch previewTravelMode {
            case .walk, .sidewalk: speedFactor = 0.0022
            case .run: speedFactor = 0.0040
            case .cycle: speedFactor = 0.0062
            case .bus, .drive: speedFactor = 0.0095
            }
            simProgress += speedFactor
            if simProgress > 1.0 {
                simProgress = 0.0
            }
        }

        if stageMode == .joystickDeck && (abs(joyStickOffset.width) > 2 || abs(joyStickOffset.height) > 2) {
            let nextX = min(max(20, joyPuckPosition.x + joyStickOffset.width * 0.12), 185)
            let nextY = min(max(20, joyPuckPosition.y + joyStickOffset.height * 0.12), 145)
            let nextPt = CGPoint(x: nextX, y: nextY)
            joyPuckPosition = nextPt
            joyTrail.append(nextPt)
            if joyTrail.count > 45 {
                joyTrail.removeFirst()
            }
        }
    }

    private func triggerPreviewFlash() {
        SoundManager.play(.success)
        withAnimation(.easeIn(duration: 0.12)) {
            previewFlashActive = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.easeOut(duration: 0.35)) {
                previewFlashActive = false
            }
        }
    }

    private func rollSurprisePalette() {
        SoundManager.play(.success)
        let choices = surprisePalettes.filter { $0.name != currentSurpriseName }
        guard let picked = choices.randomElement() ?? surprisePalettes.first else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            currentSurpriseName = picked.name
            draft.accentTheme = .custom
            draft.primaryHex = picked.primaryHex
            draft.secondaryHex = picked.secondaryHex
            draft.glassTintHex = picked.glassHex
            draft.isGlassTintEnabled = true
            draft.menuTintHex = picked.glassHex
            draft.isMenuTintEnabled = true
            draft.completionFlashHex = picked.flashHex
            syncEditorSlidersFromDraft()
        }
    }

    private func commitChangesAndSave(closeSheet: Bool) {
        SoundManager.play(.success)
        session.applyThemeConfiguration(
            accentTheme: draft.accentTheme,
            primaryHex: draft.primaryHex,
            secondaryHex: draft.secondaryHex,
            textColorHex: draft.textColorHex,
            isCustomTextColorEnabled: draft.isCustomTextColorEnabled,
            menuTintHex: draft.menuTintHex,
            isMenuTintEnabled: draft.isMenuTintEnabled,
            glassTintHex: draft.glassTintHex,
            isGlassTintEnabled: draft.isGlassTintEnabled,
            completionFlashHex: draft.completionFlashHex,
            pathWidth: draft.pathWidth,
            uiAppearance: draft.uiAppearance,
            showWaypointLabels: draft.showWaypointLabels
        )
        savedState = draft

        if closeSheet {
            dismiss()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showSavedToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    showSavedToast = false
                }
            }
        }
    }

    private func hexForTarget(_ target: CustomTarget) -> String {
        switch target {
        case .primary: return draft.primaryHex
        case .secondary: return draft.secondaryHex
        case .textColor: return draft.textColorHex
        case .menuTint: return draft.menuTintHex
        case .glassTint: return draft.glassTintHex
        case .completionFlash: return draft.completionFlashHex
        }
    }

    private func colorForTarget(_ target: CustomTarget) -> Color {
        Color(hex: hexForTarget(target)) ?? draft.effectivePrimary
    }

    private func syncEditorSlidersFromDraft() {
        let hex = hexForTarget(customTarget)
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

    private func updateDraftHex(_ hex: String, updateSliders: Bool) {
        switch customTarget {
        case .primary:
            draft.primaryHex = hex
            draft.accentTheme = .custom
        case .secondary:
            draft.secondaryHex = hex
            draft.accentTheme = .custom
        case .textColor:
            draft.textColorHex = hex
            draft.isCustomTextColorEnabled = true
        case .menuTint:
            draft.menuTintHex = hex
            draft.isMenuTintEnabled = true
        case .glassTint:
            draft.glassTintHex = hex
            draft.isGlassTintEnabled = true
        case .completionFlash:
            draft.completionFlashHex = hex
        }

        if updateSliders, let color = Color(hex: hex) {
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

    private func applyRGBToDraft() {
        let color = Color.fromRGB(r: Int(redVal), g: Int(greenVal), b: Int(blueVal))
        let hex = color.toHex()
        hexInput = String(hex.dropFirst())
        nativeColor = color
        let hsb = color.componentsHSB()
        hueVal = hsb.h
        satVal = hsb.s
        briVal = hsb.b
        updateDraftHex(hex, updateSliders: false)
    }

    private func applyHSBToDraft() {
        let color = Color.fromHSB(h: hueVal, s: satVal, b: briVal)
        let hex = color.toHex()
        hexInput = String(hex.dropFirst())
        nativeColor = color
        let rgb = color.componentsRGB()
        redVal = Double(rgb.r)
        greenVal = Double(rgb.g)
        blueVal = Double(rgb.b)
        updateDraftHex(hex, updateSliders: false)
    }

    private func pointAlongThreePointCurve(p1: CGPoint, p2: CGPoint, p3: CGPoint, t: CGFloat) -> CGPoint {
        let clamped = min(1.0, max(0.0, t))
        if clamped < 0.5 {
            let localT = clamped * 2.0
            let c1 = CGPoint(x: (p1.x + p2.x) * 0.5, y: p1.y)
            return quadBezier(p0: p1, c: c1, p1: p2, t: localT)
        } else {
            let localT = (clamped - 0.5) * 2.0
            let c2 = CGPoint(x: (p2.x + p3.x) * 0.5, y: p3.y)
            return quadBezier(p0: p2, c: c2, p1: p3, t: localT)
        }
    }

    private func quadBezier(p0: CGPoint, c: CGPoint, p1: CGPoint, t: CGFloat) -> CGPoint {
        let inv = 1.0 - t
        let x = inv * inv * p0.x + 2 * inv * t * c.x + t * t * p1.x
        let y = inv * inv * p0.y + 2 * inv * t * c.y + t * t * p1.y
        return CGPoint(x: x, y: y)
    }
}

private struct PlaygroundRouteShape: Shape {
    let p1: CGPoint
    let p2: CGPoint
    let p3: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: p1)
        let c1 = CGPoint(x: (p1.x + p2.x) * 0.5, y: p1.y)
        path.addQuadCurve(to: p2, control: c1)
        let c2 = CGPoint(x: (p2.x + p3.x) * 0.5, y: p3.y)
        path.addQuadCurve(to: p3, control: c2)
        return path
    }
}

private struct PlaygroundGridBackground: View {
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 28
            var gridPath = Path()
            var x: CGFloat = 0
            while x <= size.width {
                gridPath.move(to: CGPoint(x: x, y: 0))
                gridPath.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                gridPath.move(to: CGPoint(x: 0, y: y))
                gridPath.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(gridPath, with: .color(accent.opacity(0.08)), lineWidth: 1)
        }
    }
}
