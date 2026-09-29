import Foundation
import CoreLocation
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    #if canImport(ActivityKit)
    private var currentActivity: Any? // Holds Activity<LocusRouteActivityAttributes>?
    #endif

    private let liveNotificationId = "locus.live.route"
    private var lastNotificationPostTime: Date = .distantPast

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
        routeDistanceMeters: Double
    ) {
        // 1. Request notification permissions if not yet granted
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        let eta = Date().addingTimeInterval(initialRemainingSeconds)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let arrivalStr = "Arrive at " + formatter.string(from: eta)

        let initialMinutes = max(1, Int(ceil(initialRemainingSeconds / 60.0)))
        let durationStr = formatRemainingDuration(initialRemainingSeconds)
        let countdownStr = "Go in \(initialMinutes) minutes"

        // 2. Post Local Live Notification for Notification Center / Lock Screen
        postLiveNotification(
            title: countdownStr,
            subtitle: "\(travelMode.title) • \(arrivalStr)",
            body: "\(destinationName) • \(durationStr) remaining (\(speedFormatted))"
        )

        // 3. ActivityKit Live Activity (iOS 16.1+)
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any previous activity
        endActivity(destinationName: destinationName)

        let state = LocusRouteActivityAttributes.ContentState(
            statusTitle: countdownStr,
            statusSubtitle: "\(travelMode.title) • \(destinationName)",
            badgeNumber: travelMode == .bus ? "234" : nil,
            badgeColorHex: travelMode == .bus ? "#FF9500" : "#0A84FF",
            progress: 0.0,
            departureCountdownText: countdownStr,
            arrivalText: arrivalStr,
            remainingTimeText: durationStr,
            destinationName: destinationName,
            currentSpeedFormatted: speedFormatted,
            travelModeIcon: travelMode.icon,
            isCompleted: false
        )

        let attributes = LocusRouteActivityAttributes(
            routeId: routeId,
            startLocationName: startName,
            targetDestinationName: destinationName
        )

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
        #endif
    }

    func updateActivity(
        progress: Double,
        remainingDistanceMeters: Double,
        remainingDurationSeconds: TimeInterval,
        destinationName: String,
        travelMode: TravelMode,
        speedFormatted: String,
        activeStopName: String? = nil
    ) {
        let eta = Date().addingTimeInterval(remainingDurationSeconds)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let arrivalStr = "Arrive at " + formatter.string(from: eta)

        let minutesLeft = max(1, Int(ceil(remainingDurationSeconds / 60.0)))
        let durationStr = formatRemainingDuration(remainingDurationSeconds)

        let title: String
        let subtitle: String

        if let stop = activeStopName {
            title = "Stopping at \(stop)"
            subtitle = "Departing in \(minutesLeft) min"
        } else if minutesLeft <= 1 {
            title = "Arriving now"
            subtitle = destinationName
        } else {
            title = "Go in \(minutesLeft) minutes"
            subtitle = "\(travelMode.title) • in \(minutesLeft) minutes"
        }

        // Throttle local notification updates to every 12 seconds so notification sound/banners don't spam
        if Date().timeIntervalSince(lastNotificationPostTime) >= 12 || minutesLeft <= 1 {
            postLiveNotification(
                title: title,
                subtitle: "\(subtitle) • \(arrivalStr)",
                body: "\(destinationName) • \(durationStr) left (\(speedFormatted))"
            )
        }

        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *), let activity = currentActivity as? Activity<LocusRouteActivityAttributes> else { return }

        let state = LocusRouteActivityAttributes.ContentState(
            statusTitle: title,
            statusSubtitle: subtitle,
            badgeNumber: travelMode == .bus ? "234" : nil,
            badgeColorHex: travelMode == .bus ? "#FF9500" : "#0A84FF",
            progress: min(1.0, max(0.0, progress)),
            departureCountdownText: title,
            arrivalText: arrivalStr,
            remainingTimeText: durationStr,
            destinationName: destinationName,
            currentSpeedFormatted: speedFormatted,
            travelModeIcon: travelMode.icon,
            isCompleted: false
        )

        Task {
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(120)))
        }
        #endif
    }

    func endActivity(destinationName: String = "Destination") {
        // Clear active live notification
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [liveNotificationId])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [liveNotificationId])

        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *), let activity = currentActivity as? Activity<LocusRouteActivityAttributes> else { return }

        let finalState = LocusRouteActivityAttributes.ContentState(
            statusTitle: "Route Completed!",
            statusSubtitle: "Arrived at \(destinationName)",
            badgeNumber: nil,
            badgeColorHex: "#30D158",
            progress: 1.0,
            departureCountdownText: "Arrived",
            arrivalText: "Arrived safely",
            remainingTimeText: "0 min",
            destinationName: destinationName,
            currentSpeedFormatted: "0.0 mph",
            travelModeIcon: "checkmark.circle.fill",
            isCompleted: true
        )

        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(30)))
            self.currentActivity = nil
        }
        #endif
    }

    private func postLiveNotification(title: String, subtitle: String, body: String) {
        lastNotificationPostTime = Date()
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = nil // Silent continuous update so it doesn't beep repeatedly
        content.userInfo = ["url": "locus://route_active"]

        let request = UNNotificationRequest(identifier: liveNotificationId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
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
}
