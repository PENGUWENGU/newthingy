import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif
import SwiftUI

#if canImport(ActivityKit)
@available(iOS 16.1, *)
public struct LocusRouteActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var statusTitle: String
        public var statusSubtitle: String
        public var badgeNumber: String?
        public var badgeColorHex: String
        public var progress: Double
        public var departureCountdownText: String
        public var arrivalText: String
        public var remainingTimeText: String
        public var destinationName: String
        public var currentSpeedFormatted: String
        public var travelModeIcon: String
        public var isCompleted: Bool

        public init(
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

    public var routeId: String
    public var startLocationName: String
    public var targetDestinationName: String

    public init(routeId: String, startLocationName: String = "Start", targetDestinationName: String = "Destination") {
        self.routeId = routeId
        self.startLocationName = startLocationName
        self.targetDestinationName = targetDestinationName
    }
}
#endif
