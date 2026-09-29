import WidgetKit
import SwiftUI

#if canImport(ActivityKit)
@main
struct LocusWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            LocusRouteLiveActivityWidget()
        }
    }
}
#endif
