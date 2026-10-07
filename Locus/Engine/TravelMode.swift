import CoreLocation
import MapKit
import Foundation

enum TravelMode: String, CaseIterable, Identifiable {
    case walk, sidewalk, run, cycle, bus, drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "Walk"
        case .sidewalk: return "Sidewalk"
        case .run: return "Run"
        case .cycle: return "Cycle"
        case .bus: return "Bus"
        case .drive: return "Drive"
        }
    }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .sidewalk: return "figure.walk.motion"
        case .run: return "figure.run"
        case .cycle: return "bicycle"
        case .bus: return "bus.fill"
        case .drive: return "car.fill"
        }
    }

    /// Base meters per second before natural variation.
    var baseSpeed: CLLocationSpeed {
        switch self {
        case .walk: return 1.4      // ~3.1 mph
        case .sidewalk: return 1.25 // ~2.8 mph
        case .run: return 3.1       // ~6.9 mph
        case .cycle: return 5.5     // ~12.3 mph
        case .bus: return 9.8       // ~21.9 mph
        case .drive: return 13.4    // ~30.0 mph
        }
    }

    var defaultSpeedMPS: CLLocationSpeed {
        baseSpeed
    }

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .walk, .sidewalk, .run: return .walking
        case .cycle, .bus, .drive: return .automobile
        }
    }
}

/// Preferred speed display & input units (mph, km/h, m/s).
enum SpeedUnit: String, CaseIterable, Identifiable {
    case mph = "mph"
    case kmh = "km/h"
    case mps = "m/s"

    var id: String { rawValue }

    var label: String { rawValue }

    /// Converts a value in this unit to meters per second.
    func toMPS(_ value: Double) -> Double {
        switch self {
        case .mph: return value / 2.236936
        case .kmh: return value / 3.6
        case .mps: return value
        }
    }

    /// Converts meters per second into this unit.
    func fromMPS(_ mps: Double) -> Double {
        switch self {
        case .mph: return mps * 2.236936
        case .kmh: return mps * 3.6
        case .mps: return mps
        }
    }

    /// Formats speed for display with 1 decimal place and unit suffix.
    func format(_ mps: Double) -> String {
        let val = fromMPS(mps)
        return String(format: "%.1f %@", val, rawValue)
    }
}

/// Validates and normalizes user-entered custom movement speeds.
enum SpeedInput {
    static let minimumMetersPerSecond: Double = 0.05
    static let maximumMetersPerSecond: Double = 1000

    /// Parses text into meters per second using the specified or default unit.
    static func parse(_ text: String, unit: SpeedUnit = .mps) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) else { return nil }
        guard value.isFinite, !value.isNaN, value > 0 else { return nil }
        let mps = unit.toMPS(value)
        return min(max(mps, minimumMetersPerSecond), maximumMetersPerSecond)
    }
}

/// Persists the user's custom speed and preferred speed unit.
enum SpeedPreference {
    static let valueKey = "locus.customSpeedMPS"
    static let enabledKey = "locus.customSpeedEnabled"
    static let unitKey = "locus.speedUnit"

    static var preferredUnit: SpeedUnit {
        get {
            guard let raw = UserDefaults.standard.string(forKey: unitKey),
                  let unit = SpeedUnit(rawValue: raw) else {
                return .mph // Default to mph
            }
            return unit
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: unitKey)
        }
    }

    static var storedValue: Double? {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return nil }
        let raw = UserDefaults.standard.double(forKey: valueKey)
        guard raw.isFinite, raw > 0 else { return nil }
        return raw
    }

    static func setCustomSpeed(_ value: Double?) {
        if let value, value.isFinite, value > 0 {
            UserDefaults.standard.set(value, forKey: valueKey)
            UserDefaults.standard.set(true, forKey: enabledKey)
        } else {
            UserDefaults.standard.set(false, forKey: enabledKey)
        }
    }
}
