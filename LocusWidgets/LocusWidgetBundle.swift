import ActivityKit
import WidgetKit
import SwiftUI

#if canImport(ActivityKit) && canImport(WidgetKit)
@available(iOS 16.1, *)
@main
struct LocusWidgetBundle: WidgetBundle {
    var body: some Widget {
        LocusRouteLiveActivityWidget()
        LocusSpoofLiveActivityWidget()
    }
}
#endif
