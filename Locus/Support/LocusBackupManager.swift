import Foundation
import SwiftUI
import UIKit

// MARK: - Comprehensive Backup & Profile Model

struct LocusBackupProfile: Codable {
    var version: Int = 1
    var exportDate: Date = Date()
    var appVersion: String = "1.0.2"

    // Theme & Visual Preferences
    struct ThemeBackup: Codable {
        var accentTheme: String
        var customPrimaryHex: String
        var customSecondaryHex: String
        var customTextColorHex: String
        var isCustomTextColorEnabled: Bool
        var customMenuTintHex: String
        var isMenuTintEnabled: Bool
        var customGlassTintHex: String
        var isGlassTintEnabled: Bool
        var appearanceStyle: String
        var completionFlashHex: String
    }
    var theme: ThemeBackup

    // Simulation Defaults & Movement Preferences
    struct DefaultsBackup: Codable {
        var defaultTravelMode: String
        var speedUnit: String
        var customSpeedMPS: Double?
        var speedVarianceMPH: Double
        var speedRandomnessEnabled: Bool
        var smartTrafficLights: Bool
        var busModeSmartStops: Bool
        var travelerName: String
        var liveActivitiesEnabled: Bool
        var targetTunnelIP: String
        var defaultConnectionType: String
        var isSoundEnabled: Bool
    }
    var defaults: DefaultsBackup

    // User Stored Data
    var favorites: [SavedPlace]
    var recents: [SavedPlace]
    var savedRoutes: [SavedRoute]

    // Device Pairing Credentials (Optional base64 plist)
    var pairingPlistBase64: String?
}

// MARK: - Backup & Transfer Manager

@MainActor
final class LocusBackupManager {
    static let shared = LocusBackupManager()
    private init() {}

    /// Exports all colors, routes, places, defaults, and pairing file to JSON.
    func createBackupJSON(session: SpoofSession, pairing: PairingStore) -> (data: Data, url: URL)? {
        let themeBackup = LocusBackupProfile.ThemeBackup(
            accentTheme: session.accentTheme.rawValue,
            customPrimaryHex: session.customPrimaryHex,
            customSecondaryHex: session.customSecondaryHex,
            customTextColorHex: session.customTextColorHex,
            isCustomTextColorEnabled: session.isCustomTextColorEnabled,
            customMenuTintHex: session.customMenuTintHex,
            isMenuTintEnabled: session.isMenuTintEnabled,
            customGlassTintHex: session.glassTintHex,
            isGlassTintEnabled: session.isGlassTintEnabled,
            appearanceStyle: ThemePreference.appearance.rawValue,
            completionFlashHex: session.completionFlashHex
        )

        let defaultsBackup = LocusBackupProfile.DefaultsBackup(
            defaultTravelMode: session.travelMode.rawValue,
            speedUnit: session.speedUnit.rawValue,
            customSpeedMPS: session.customSpeedMPS,
            speedVarianceMPH: session.speedVarianceMPH,
            speedRandomnessEnabled: session.speedRandomnessEnabled,
            smartTrafficLights: session.smartTrafficLights,
            busModeSmartStops: session.busModeSmartStops,
            travelerName: session.travelerName,
            liveActivitiesEnabled: session.liveActivitiesEnabled,
            targetTunnelIP: TunnelConfig.targetIP,
            defaultConnectionType: session.defaultConnectionType.rawValue,
            isSoundEnabled: SoundManager.shared.isSoundEnabled
        )

        var pairingBase64: String? = nil
        if pairing.hasPairingFile, let rawData = try? Data(contentsOf: pairing.pairingURL) {
            pairingBase64 = rawData.base64EncodedString()
        }

        let profile = LocusBackupProfile(
            version: 1,
            exportDate: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.2",
            theme: themeBackup,
            defaults: defaultsBackup,
            favorites: session.favorites,
            recents: session.recents,
            savedRoutes: SavedRoute.load(),
            pairingPlistBase64: pairingBase64
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(profile) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Locus-Backup-\(timestamp).json")

        do {
            try data.write(to: tempURL)
            return (data, tempURL)
        } catch {
            return nil
        }
    }

    /// Restores complete state from a JSON profile.
    @discardableResult
    func restoreBackup(from data: Data, session: SpoofSession, pairing: PairingStore) throws -> String {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let profile = try decoder.decode(LocusBackupProfile.self, from: data)

        // 1. Restore Theme & Colors
        if let accent = AccentColorTheme(rawValue: profile.theme.accentTheme) {
            session.accentTheme = accent
            ThemePreference.accent = accent
        }
        session.customPrimaryHex = profile.theme.customPrimaryHex
        session.customSecondaryHex = profile.theme.customSecondaryHex
        session.customTextColorHex = profile.theme.customTextColorHex
        session.isCustomTextColorEnabled = profile.theme.isCustomTextColorEnabled
        session.customMenuTintHex = profile.theme.customMenuTintHex
        session.isMenuTintEnabled = profile.theme.isMenuTintEnabled
        session.glassTintHex = profile.theme.customGlassTintHex
        session.isGlassTintEnabled = profile.theme.isGlassTintEnabled
        session.completionFlashHex = profile.theme.completionFlashHex

        ThemePreference.customPrimaryHex = profile.theme.customPrimaryHex
        ThemePreference.customSecondaryHex = profile.theme.customSecondaryHex
        ThemePreference.customTextColorHex = profile.theme.customTextColorHex
        ThemePreference.isCustomTextColorEnabled = profile.theme.isCustomTextColorEnabled
        ThemePreference.customMenuTintHex = profile.theme.customMenuTintHex
        ThemePreference.isMenuTintEnabled = profile.theme.isMenuTintEnabled
        ThemePreference.customGlassTintHex = profile.theme.customGlassTintHex
        ThemePreference.isGlassTintEnabled = profile.theme.isGlassTintEnabled

        if let appearance = UIAppearanceStyle(rawValue: profile.theme.appearanceStyle) {
            ThemePreference.appearance = appearance
        }

        // 2. Restore Defaults & Simulation
        if let mode = TravelMode(rawValue: profile.defaults.defaultTravelMode) {
            session.selectTravelMode(mode)
        }
        if let unit = SpeedUnit(rawValue: profile.defaults.speedUnit) {
            session.setSpeedUnit(unit)
        }
        if let customSpeed = profile.defaults.customSpeedMPS {
            session.setCustomSpeed(customSpeed)
        }
        session.setSpeedVariance(profile.defaults.speedVarianceMPH)
        session.setSpeedRandomnessEnabled(profile.defaults.speedRandomnessEnabled)
        session.smartTrafficLights = profile.defaults.smartTrafficLights
        session.busModeSmartStops = profile.defaults.busModeSmartStops
        session.travelerName = profile.defaults.travelerName
        session.liveActivitiesEnabled = profile.defaults.liveActivitiesEnabled
        UserDefaults.standard.set(profile.defaults.liveActivitiesEnabled, forKey: "locus.liveActivitiesEnabled")
        TunnelConfig.setTargetIP(profile.defaults.targetTunnelIP)
        if let connType = RouteConnectionType(rawValue: profile.defaults.defaultConnectionType) {
            session.setDefaultConnectionType(connType)
        }
        SoundManager.shared.isSoundEnabled = profile.defaults.isSoundEnabled

        // 3. Restore Favorites & Recents
        for place in profile.favorites {
            session.addFavorite(place)
        }
        for place in profile.recents {
            session.addRecent(place)
        }

        // 4. Restore Saved Routes
        var existingRoutes = SavedRoute.load()
        for newRoute in profile.savedRoutes {
            if !existingRoutes.contains(where: { $0.id == newRoute.id }) {
                existingRoutes.append(newRoute)
            }
        }
        if let routeData = try? JSONEncoder().encode(existingRoutes) {
            UserDefaults.standard.set(routeData, forKey: "locus.saved_routes")
        }

        // 5. Restore Pairing File if included
        var restoredPairing = false
        if let base64 = profile.pairingPlistBase64,
           let pairingData = Data(base64Encoded: base64) {
            try? pairing.installPairingData(pairingData)
            pairing.refresh()
            restoredPairing = true
        }

        session.objectWillChange.send()

        var summary = "Restored theme, \(profile.savedRoutes.count) routes, and \(profile.favorites.count) favorites."
        if restoredPairing {
            summary += " Pairing credentials restored."
        }
        return summary
    }

    /// Share sheet launcher for export file.
    func presentShareSheet(with fileURL: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        rootVC.present(activityVC, animated: true)
    }
}
