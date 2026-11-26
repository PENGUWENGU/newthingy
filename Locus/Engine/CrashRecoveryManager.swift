import CoreLocation
import Foundation
import SwiftUI

// MARK: - Crash Recovery State Snapshot

struct SpoofSessionSnapshot: Codable, Equatable {
    enum SessionType: String, Codable {
        case teleport
        case joystick
        case route
    }

    var sessionType: SessionType
    var lastCoordinate: CodableCoordinate
    var locationName: String
    var travelModeRaw: String
    var currentSpeedMPS: Double
    var timestamp: Date

    // Route-specific recovery details
    var routeName: String?
    var routeCoordinates: [CodableCoordinate]?
    var routeCoordinateSegments: [[CodableCoordinate]]?
    var routeWaypoints: [SavedWaypoint]?
    var currentSegmentIndex: Int?
    var routeProgress: Double?
    var isLoop: Bool?
    var remainingDistanceMeters: Double?

    init(
        sessionType: SessionType,
        coordinate: CLLocationCoordinate2D,
        locationName: String = "Interrupted Location",
        travelMode: TravelMode = .drive,
        currentSpeedMPS: Double = 11.2,
        routeName: String? = nil,
        routeCoordinates: [CLLocationCoordinate2D]? = nil,
        routeCoordinateSegments: [[CLLocationCoordinate2D]]? = nil,
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
        if let segs = routeCoordinateSegments?.filter({ !$0.isEmpty }), !segs.isEmpty {
            self.routeCoordinateSegments = segs.map { $0.map { CodableCoordinate($0) } }
            self.routeCoordinates = segs.flatMap { $0 }.map { CodableCoordinate($0) }
        } else {
            self.routeCoordinateSegments = nil
            self.routeCoordinates = routeCoordinates?.map { CodableCoordinate($0) }
        }
        self.routeWaypoints = routeWaypoints?.map { SavedWaypoint(id: $0.id, coordinate: $0.coordinate, name: $0.name, stopDuration: $0.stopDuration) }
        self.currentSegmentIndex = currentSegmentIndex
        self.routeProgress = routeProgress
        self.isLoop = isLoop
        self.remainingDistanceMeters = remainingDistanceMeters
    }
}

// MARK: - Crash Recovery Manager

@MainActor
final class CrashRecoveryManager: ObservableObject {
    static let shared = CrashRecoveryManager()

    nonisolated static let snapshotKey = "locus.crash_recovery.session_snapshot"
    nonisolated static let activeSpoofingFlagKey = "locus.crash_recovery.was_active"

    @Published var pendingRecoverySnapshot: SpoofSessionSnapshot? = nil
    @Published var showRecoveryPrompt: Bool = false

    private nonisolated static let stateLock = NSLock()
    private nonisolated(unsafe) static var sessionEpoch: UInt64 = 0

    private init() {
        checkPendingCrashRecovery()
    }

    /// Check if the previous run terminated while spoofing was actively running
    func checkPendingCrashRecovery() {
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

    /// Continuously updates the heartbeat snapshot while spoofing or driving (callable from background simulation tasks)
    nonisolated func updateHeartbeat(snapshot: SpoofSessionSnapshot) {
        Self.stateLock.lock()
        Self.sessionEpoch &+= 1
        UserDefaults.standard.set(true, forKey: Self.activeSpoofingFlagKey)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        }
        Self.stateLock.unlock()
    }

    /// Clears the crash recovery flag when spoofing is explicitly ended normally
    nonisolated func clearSession() {
        Self.stateLock.lock()
        Self.sessionEpoch &+= 1
        let capturedEpoch = Self.sessionEpoch
        UserDefaults.standard.set(false, forKey: Self.activeSpoofingFlagKey)
        UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
        Self.stateLock.unlock()

        Task { @MainActor [weak self] in
            Self.stateLock.lock()
            let currentEpoch = Self.sessionEpoch
            Self.stateLock.unlock()
            guard currentEpoch == capturedEpoch else { return }
            self?.pendingRecoverySnapshot = nil
            self?.showRecoveryPrompt = false
        }
    }

    /// Dismisses prompt without resuming
    func dismissRecovery() {
        clearSession()
    }
}
