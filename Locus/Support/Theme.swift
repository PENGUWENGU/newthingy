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
    case custom = "Custom"

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
        case .custom:
            return Color(hex: ThemePreference.customPrimaryHex) ?? Color(red: 0.35, green: 0.78, blue: 0.72)
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
        case .custom:
            return Color(hex: ThemePreference.customSecondaryHex) ?? Color(red: 0.95, green: 0.55, blue: 0.28)
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

    static let customPrimaryHexKey = "locus.theme.custom_primary_hex"
    static let customSecondaryHexKey = "locus.theme.custom_secondary_hex"

    static var customPrimaryHex: String {
        get {
            UserDefaults.standard.string(forKey: customPrimaryHexKey) ?? "#59C6B8"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: customPrimaryHexKey)
        }
    }

    static var customSecondaryHex: String {
        get {
            UserDefaults.standard.string(forKey: customSecondaryHexKey) ?? "#F28C47"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: customSecondaryHexKey)
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

// MARK: - Color Hex, RGB & HSB Extensions

extension Color {
    init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else {
            return nil
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "#59C6B8"
        }
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    func componentsRGB() -> (r: Int, g: Int, b: Int) {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return (89, 198, 184)
        }
        return (Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }

    func componentsHSB() -> (h: Double, s: Double, b: Double) {
        let uiColor = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            return (172, 55, 78)
        }
        return (Double(h * 360), Double(s * 100), Double(b * 100))
    }

    static func fromRGB(r: Int, g: Int, b: Int) -> Color {
        let rc = Double(max(0, min(255, r))) / 255.0
        let gc = Double(max(0, min(255, g))) / 255.0
        let bc = Double(max(0, min(255, b))) / 255.0
        return Color(red: rc, green: gc, blue: bc)
    }

    static func fromHSB(h: Double, s: Double, b: Double) -> Color {
        let hue = max(0, min(360, h)) / 360.0
        let sat = max(0, min(100, s)) / 100.0
        let bri = max(0, min(100, b)) / 100.0
        return Color(hue: hue, saturation: sat, brightness: bri)
    }
}
