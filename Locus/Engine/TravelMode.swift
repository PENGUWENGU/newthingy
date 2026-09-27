import CoreLocation
import MapKit
import Foundation

enum TravelMode: String, CaseIterable, Identifiable {
    case walk, run, cycle, drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "Walk"
        case .run: return "Run"
        case .cycle: return "Cycle"
        case .drive: return "Drive"
        }
    }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .cycle: return "bicycle"
        case .drive: return "car.fill"
        }
    }

    /// Base meters per second before natural variation.
    var baseSpeed: CLLocationSpeed {
        switch self {
        case .walk: return 1.4
        case .run: return 3.3
        case .cycle: return 6.5
        case .drive: return 13.4
        }
    }

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .walk, .run: return .walking
        case .cycle, .drive: return .automobile
        }
    }
}

/// Validates and normalizes user-entered custom movement speeds.
///
/// This is the single gatekeeper for turning raw text from a text field into a safe,
/// finite `CLLocationSpeed` (meters per second). Nothing outside this type should
/// attempt to parse a speed string.
enum SpeedInput {
    /// Floor for a custom speed. Anything at or below this is treated as invalid rather
    /// than silently clamped, since a near-zero or negative speed isn't a meaningful
    /// movement rate.
    static let minimumMetersPerSecond: Double = 0.05
    /// Generous ceiling so the control stays usable for testing/dev scenarios far outside
    /// walk/run/cycle/drive, without allowing a stray keystroke to produce an unusable value.
    static let maximumMetersPerSecond: Double = 1000

    /// Parses free-form text into a safe custom speed in meters per second.
    ///
    /// Returns `nil` for anything that isn't a genuine positive, finite number: empty
    /// input, non-numeric text, `NaN`, `+Infinity`/`-Infinity`, or a value `<= 0`.
    /// A value that parses fine but falls outside the practical range is clamped rather
    /// than rejected, since the input itself was well-formed.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Tolerate a comma decimal separator (common outside en-US locales) in addition
        // to a period, without affecting normal parsing of plain integers/decimals.
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) else { return nil }
        guard value.isFinite, !value.isNaN, value > 0 else { return nil }
        return min(max(value, minimumMetersPerSecond), maximumMetersPerSecond)
    }
}

/// Persists the user's custom speed override the same way the rest of Locus persists
/// simple settings (see `TunnelConfig`): a plain `UserDefaults`-backed namespace.
enum SpeedPreference {
    static let valueKey = "locus.customSpeedMPS"
    static let enabledKey = "locus.customSpeedEnabled"

    /// The stored custom speed, or `nil` if no override is currently enabled/saved.
    static var storedValue: Double? {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return nil }
        let raw = UserDefaults.standard.double(forKey: valueKey)
        guard raw.isFinite, raw > 0 else { return nil }
        return raw
    }

    /// Saves a validated custom speed, or pass `nil` to disable the override and fall
    /// back to the selected travel mode's preset speed.
    static func setCustomSpeed(_ value: Double?) {
        if let value, value.isFinite, value > 0 {
            UserDefaults.standard.set(value, forKey: valueKey)
            UserDefaults.standard.set(true, forKey: enabledKey)
        } else {
            UserDefaults.standard.set(false, forKey: enabledKey)
        }
    }
}
