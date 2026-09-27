import SwiftUI

// MARK: - Accent Color Theme

enum AccentColorTheme: String, CaseIterable, Identifiable {
    case mint = "Mint Teal"
    case blue = "Electric Blue"
    case purple = "Amethyst Violet"
    case orange = "Sunset Amber"
    case green = "Emerald Matrix"
    case pink = "Cyberpunk Pink"
    case monochrome = "Monochrome Slate"

    var id: String { rawValue }

    var primaryColor: Color {
        switch self {
        case .mint: return Color(red: 0.35, green: 0.78, blue: 0.72)
        case .blue: return Color(red: 0.20, green: 0.62, blue: 1.00)
        case .purple: return Color(red: 0.72, green: 0.45, blue: 0.98)
        case .orange: return Color(red: 1.00, green: 0.55, blue: 0.20)
        case .green: return Color(red: 0.22, green: 0.86, blue: 0.48)
        case .pink: return Color(red: 1.00, green: 0.32, blue: 0.64)
        case .monochrome: return Color(red: 0.92, green: 0.92, blue: 0.94)
        }
    }

    var secondaryColor: Color {
        switch self {
        case .mint: return Color(red: 0.95, green: 0.55, blue: 0.28)
        case .blue: return Color(red: 0.35, green: 0.85, blue: 0.75)
        case .purple: return Color(red: 0.98, green: 0.45, blue: 0.65)
        case .orange: return Color(red: 0.95, green: 0.82, blue: 0.25)
        case .green: return Color(red: 0.38, green: 0.78, blue: 1.00)
        case .pink: return Color(red: 0.32, green: 0.86, blue: 0.96)
        case .monochrome: return Color(red: 0.60, green: 0.60, blue: 0.65)
        }
    }

    var previewGradient: LinearGradient {
        LinearGradient(
            colors: [primaryColor, secondaryColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Path Line Width Preference

enum PathWidthPreference: String, CaseIterable, Identifiable {
    case slim = "Slim (3.5pt)"
    case standard = "Standard (5.5pt)"
    case bold = "Bold (8pt)"

    var id: String { rawValue }

    var width: CGFloat {
        switch self {
        case .slim: return 3.5
        case .standard: return 5.5
        case .bold: return 8.0
        }
    }

    var glowWidth: CGFloat {
        switch self {
        case .slim: return 6.5
        case .standard: return 9.0
        case .bold: return 12.0
        }
    }
}

// MARK: - UI Glass & Appearance Style

enum UIAppearanceStyle: String, CaseIterable, Identifiable {
    case glass = "Liquid Glass"
    case highContrast = "High Contrast Dark"
    case minimal = "Minimal Translucent"

    var id: String { rawValue }
}

// MARK: - Theme Persistence Manager

enum ThemePreference {
    static let accentKey = "locus.theme.accent"
    static let pathWidthKey = "locus.theme.path_width"
    static let appearanceKey = "locus.theme.appearance"
    static let showWaypointLabelsKey = "locus.theme.show_waypoint_labels"

    static var accent: AccentColorTheme {
        get {
            guard let raw = UserDefaults.standard.string(forKey: accentKey),
                  let theme = AccentColorTheme(rawValue: raw) else {
                return .mint
            }
            return theme
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: accentKey)
        }
    }

    static var pathWidth: PathWidthPreference {
        get {
            guard let raw = UserDefaults.standard.string(forKey: pathWidthKey),
                  let width = PathWidthPreference(rawValue: raw) else {
                return .standard
            }
            return width
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: pathWidthKey)
        }
    }

    static var appearance: UIAppearanceStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: appearanceKey),
                  let style = UIAppearanceStyle(rawValue: raw) else {
                return .glass
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: appearanceKey)
        }
    }

    static var showWaypointLabels: Bool {
        get {
            if UserDefaults.standard.object(forKey: showWaypointLabelsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: showWaypointLabelsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showWaypointLabelsKey)
        }
    }
}

// MARK: - Dynamic Theme Colors

enum LocusTheme {
    static var accent: Color {
        ThemePreference.accent.primaryColor
    }

    static var accentSecondary: Color {
        ThemePreference.accent.secondaryColor
    }

    static let danger = Color(red: 0.92, green: 0.32, blue: 0.36)

    static var panelStroke: Color {
        switch ThemePreference.appearance {
        case .glass: return Color.white.opacity(0.12)
        case .highContrast: return Color.white.opacity(0.24)
        case .minimal: return Color.white.opacity(0.06)
        }
    }

    static let statusGood = Color(red: 0.30, green: 0.86, blue: 0.55)
    static let statusWarn = Color(red: 0.98, green: 0.78, blue: 0.28)
    static let statusBad = Color(red: 0.92, green: 0.32, blue: 0.36)
}

enum LocusGlassStyle {
    case regular
    case clear
    case interactive
}

/// Liquid Glass on iOS 26+; material fallback earlier.
struct LocusGlassModifier<S: Shape>: ViewModifier {
    var style: LocusGlassStyle
    var shape: S
    var tint: Color?

    func body(content: Content) -> some View {
        let appearance = ThemePreference.appearance

        if appearance == .highContrast {
            content
                .background {
                    shape.fill(Color(white: 0.12).opacity(0.95))
                }
                .overlay(shape.stroke(LocusTheme.panelStroke, lineWidth: 1.5))
                .contentShape(shape)
        } else if #available(iOS 26.0, *), appearance == .glass {
            content
                .glassEffect(glass, in: shape)
                .contentShape(shape)
        } else {
            content
                .background {
                    shape.fill(appearance == .minimal ? .thinMaterial : .ultraThinMaterial)
                    if let tint {
                        shape.fill(tint.opacity(0.45))
                    }
                }
                .overlay(shape.stroke(LocusTheme.panelStroke, lineWidth: 1))
                .contentShape(shape)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var g: Glass = style == .clear ? .clear : .regular
        if style == .interactive { g = g.interactive() }
        if let tint { g = g.tint(tint) }
        return g
    }
}

extension View {
    func locusGlass<S: Shape>(
        _ style: LocusGlassStyle = .regular,
        tint: Color? = nil,
        in shape: S
    ) -> some View {
        modifier(LocusGlassModifier(style: style, shape: shape, tint: tint))
    }

    func locusGlass(_ style: LocusGlassStyle = .regular, tint: Color? = nil) -> some View {
        locusGlass(style, tint: tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
