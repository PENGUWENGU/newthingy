import CoreLocation
import Foundation
import SwiftUI

// MARK: - Crash Recovery State Snapshot

public struct SpoofSessionSnapshot: Codable, Equatable {
    public enum SessionType: String, Codable {
        case teleport
        case joystick
        case route
    }

    public var sessionType: SessionType
    public var lastCoordinate: CodableCoordinate
    public var locationName: String
    public var travelModeRaw: String
    public var currentSpeedMPS: Double
    public var timestamp: Date

    // Route-specific recovery details
    public var routeName: String?
    public var routeCoordinates: [CodableCoordinate]?
    public var routeWaypoints: [SavedWaypoint]?
    public var currentSegmentIndex: Int?
    public var routeProgress: Double?
    public var isLoop: Bool?
    public var remainingDistanceMeters: Double?

    public init(
        sessionType: SessionType,
        coordinate: CLLocationCoordinate2D,
        locationName: String = "Interrupted Location",
        travelMode: TravelMode = .drive,
        currentSpeedMPS: Double = 11.2,
        routeName: String? = nil,
        routeCoordinates: [CLLocationCoordinate2D]? = nil,
        routeWaypoints: [RouteWaypoint]? = nil,
        currentSegmentIndex: Int? = nil,
        routeProgress: Double? = nil,
        isLoop: Bool? = nil,
        remainingDistanceMeters: Double? = nil
    ) {
        self.sessionType = sessionType
        self.lastCoordinate = CodableCoordinate(coordinate)
        self.locationName = locationName
        self.travelModeRaw = travelMode.rawValue
        self.currentSpeedMPS = currentSpeedMPS
        self.timestamp = Date()
        self.routeName = routeName
        self.routeCoordinates = routeCoordinates?.map { CodableCoordinate($0) }
        self.routeWaypoints = routeWaypoints?.map { SavedWaypoint(id: $0.id, coordinate: $0.coordinate, name: $0.name, stopDuration: $0.stopDuration) }
        self.currentSegmentIndex = currentSegmentIndex
        self.routeProgress = routeProgress
        self.isLoop = isLoop
        self.remainingDistanceMeters = remainingDistanceMeters
    }
}

// MARK: - Crash Recovery Manager

@MainActor
public final class CrashRecoveryManager: ObservableObject {
    public static let shared = CrashRecoveryManager()

    private static let snapshotKey = "locus.crash_recovery.session_snapshot"
    private static let activeSpoofingFlagKey = "locus.crash_recovery.was_active"

    @Published public var pendingRecoverySnapshot: SpoofSessionSnapshot? = nil
    @Published public var showRecoveryPrompt: Bool = false

    private init() {
        checkPendingCrashRecovery()
    }

    /// Check if the previous run terminated while spoofing was actively running
    public func checkPendingCrashRecovery() {
        let wasActive = UserDefaults.standard.bool(forKey: Self.activeSpoofingFlagKey)
        guard wasActive else { return }

        guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
              let snapshot = try? JSONDecoder().decode(SpoofSessionSnapshot.self, from: data) else {
            return
        }

        // Only offer recovery if the checkpoint was within the past 24 hours
        if Date().timeIntervalSince(snapshot.timestamp) < 86400 {
            self.pendingRecoverySnapshot = snapshot
            self.showRecoveryPrompt = true
        } else {
            clearSession()
        }
    }

    /// Continuously updates the heartbeat snapshot while spoofing or driving
    public func updateHeartbeat(snapshot: SpoofSessionSnapshot) {
        UserDefaults.standard.set(true, forKey: Self.activeSpoofingFlagKey)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        }
    }

    /// Clears the crash recovery flag when spoofing is explicitly ended normally
    public func clearSession() {
        UserDefaults.standard.set(false, forKey: Self.activeSpoofingFlagKey)
        UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
        self.pendingRecoverySnapshot = nil
        self.showRecoveryPrompt = false
    }

    /// Dismisses prompt without resuming
    public func dismissRecovery() {
        clearSession()
    }
}
