import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif
import SwiftUI

#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct LocusRouteActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var statusTitle: String
        var statusSubtitle: String
        var badgeNumber: String?
        var badgeColorHex: String
        var progress: Double
        var departureCountdownText: String
        var arrivalText: String
        var remainingTimeText: String
        var destinationName: String
        var currentSpeedFormatted: String
        var travelModeIcon: String
        var isCompleted: Bool

        init(
            statusTitle: String,
            statusSubtitle: String,
            badgeNumber: String? = nil,
            badgeColorHex: String = "#FF9500",
            progress: Double = 0.0,
            departureCountdownText: String = "",
            arrivalText: String = "",
            remainingTimeText: String = "",
            destinationName: String = "",
            currentSpeedFormatted: String = "",
            travelModeIcon: String = "figure.walk",
            isCompleted: Bool = false
        ) {
            self.statusTitle = statusTitle
            self.statusSubtitle = statusSubtitle
            self.badgeNumber = badgeNumber
            self.badgeColorHex = badgeColorHex
            self.progress = progress
            self.departureCountdownText = departureCountdownText
            self.arrivalText = arrivalText
            self.remainingTimeText = remainingTimeText
            self.destinationName = destinationName
            self.currentSpeedFormatted = currentSpeedFormatted
            self.travelModeIcon = travelModeIcon
            self.isCompleted = isCompleted
        }
    }

    var routeId: String
    var startLocationName: String
    var targetDestinationName: String

    init(routeId: String, startLocationName: String = "Start", targetDestinationName: String = "Destination") {
        self.routeId = routeId
        self.startLocationName = startLocationName
        self.targetDestinationName = targetDestinationName
    }
}
#endif
