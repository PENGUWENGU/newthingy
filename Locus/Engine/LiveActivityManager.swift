import Foundation
import CoreLocation
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    #if canImport(ActivityKit)
    private var currentActivity: Any? // Holds Activity<LocusRouteActivityAttributes>?
    #endif

    private init() {}

    var isActivityActive: Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            return currentActivity != nil
        }
        #endif
        return false
    }

    func startActivity(
        routeId: String = UUID().uuidString,
        startName: String = "Current Location",
        destinationName: String,
        travelMode: TravelMode,
        speedFormatted: String,
        initialRemainingSeconds: TimeInterval,
        routeDistanceMeters: Double,
        isPaused: Bool = false
    ) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }

        // Synchronously detach previous activity reference so its async end never clears the new activity
        let oldActivity = self.currentActivity as? Activity<LocusRouteActivityAttributes>
        self.currentActivity = nil

        let eta = Date().addingTimeInterval(initialRemainingSeconds)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let arrivalStr = "Arrive at " + formatter.string(from: eta)

        let initialMinutes = max(1, Int(ceil(initialRemainingSeconds / 60.0)))
        let durationStr = formatRemainingDuration(initialRemainingSeconds)
        let distanceStr = formatDistance(routeDistanceMeters)
        let countdownStr = "Go in \(initialMinutes) min\(initialMinutes == 1 ? "" : "s")"
        let accentHex = ThemePreference.accent.primaryColor.toHex()

        let state = LocusRouteActivityAttributes.ContentState(
            statusTitle: countdownStr,
            statusSubtitle: "\(travelMode.title) • \(destinationName)",
            badgeNumber: travelMode == .bus ? "234" : nil,
            badgeColorHex: travelMode == .bus ? "#FF9500" : accentHex,
            progress: 0.0,
            departureCountdownText: countdownStr,
            arrivalText: arrivalStr,
            remainingTimeText: durationStr,
            remainingDistanceText: distanceStr,
            destinationName: destinationName,
            currentSpeedFormatted: speedFormatted,
            travelModeIcon: travelMode.icon,
            isPaused: isPaused,
            isCompleted: false
        )

        let attributes = LocusRouteActivityAttributes(
            routeId: routeId,
            startLocationName: startName,
            targetDestinationName: destinationName
        )

        Task { @MainActor in
            if let oldActivity {
                await oldActivity.end(nil, dismissalPolicy: .immediate)
            }
            for stale in Activity<LocusRouteActivityAttributes>.activities {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
            do {
                let activity = try Activity<LocusRouteActivityAttributes>.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: Date().addingTimeInterval(3600)),
                    pushType: nil
                )
                self.currentActivity = activity
            } catch {
                print("[LiveActivityManager] Failed to start ActivityKit Live Activity: \(error.localizedDescription)")
            }
        }
        #endif
    }

    func updateActivity(
        progress: Double,
        remainingDistanceMeters: Double,
        remainingDurationSeconds: TimeInterval,
        destinationName: String,
        travelMode: TravelMode,
        speedFormatted: String,
        activeStopName: String? = nil,
        isPaused: Bool = false
    ) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        let resolvedActivity = (currentActivity as? Activity<LocusRouteActivityAttributes>)
            ?? Activity<LocusRouteActivityAttributes>.activities.first
        guard let activity = resolvedActivity else { return }
        if currentActivity == nil {
            currentActivity = activity
        }

        let eta = Date().addingTimeInterval(remainingDurationSeconds)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let arrivalStr = "Arrive at " + formatter.string(from: eta)

        let minutesLeft = max(1, Int(ceil(remainingDurationSeconds / 60.0)))
        let durationStr = formatRemainingDuration(remainingDurationSeconds)
        let distanceStr = formatDistance(remainingDistanceMeters)
        let accentHex = ThemePreference.accent.primaryColor.toHex()

        let title: String
        let subtitle: String

        if let stop = activeStopName {
            title = "Stopping at \(stop)"
            subtitle = "Departing in \(minutesLeft) min"
        } else if minutesLeft <= 1 {
            title = "Arriving now"
            subtitle = destinationName
        } else {
            title = "Go in \(minutesLeft) min\(minutesLeft == 1 ? "" : "s")"
            subtitle = "\(travelMode.title) • \(destinationName)"
        }

        let state = LocusRouteActivityAttributes.ContentState(
            statusTitle: title,
            statusSubtitle: subtitle,
            badgeNumber: travelMode == .bus ? "234" : nil,
            badgeColorHex: travelMode == .bus ? "#FF9500" : accentHex,
            progress: min(1.0, max(0.0, progress)),
            departureCountdownText: title,
            arrivalText: arrivalStr,
            remainingTimeText: durationStr,
            remainingDistanceText: distanceStr,
            destinationName: destinationName,
            currentSpeedFormatted: speedFormatted,
            travelModeIcon: travelMode.icon,
            isPaused: isPaused,
            isCompleted: false
        )

        Task {
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(120)))
        }
        #endif
    }

    func endActivity(destinationName: String = "Destination") {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        let activityToEnd = (currentActivity as? Activity<LocusRouteActivityAttributes>)
            ?? Activity<LocusRouteActivityAttributes>.activities.first
        self.currentActivity = nil
        guard let activity = activityToEnd else { return }

        let finalState = LocusRouteActivityAttributes.ContentState(
            statusTitle: "Route Completed!",
            statusSubtitle: "Arrived at \(destinationName)",
            badgeNumber: nil,
            badgeColorHex: "#30D158",
            progress: 1.0,
            departureCountdownText: "Arrived",
            arrivalText: "Arrived safely",
            remainingTimeText: "0 min",
            remainingDistanceText: "0 m",
            destinationName: destinationName,
            currentSpeedFormatted: "0.0 mph",
            travelModeIcon: "checkmark.circle.fill",
            isPaused: false,
            isCompleted: true
        )

        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(15)))
        }
        #endif
    }

    private func formatRemainingDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(ceil(seconds / 60.0))
        if totalMinutes < 60 {
            return "\(totalMinutes) min"
        } else {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            return mins > 0 ? "\(hours) h \(mins) min" : "\(hours) h"
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        } else {
            return String(format: "%.1f km", meters / 1000.0)
        }
    }
}
