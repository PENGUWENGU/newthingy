import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(AppIntents)
import AppIntents

@available(iOS 16.0, *)
struct ToggleRouteSimulationIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Route"
    static var description = IntentDescription("Toggles pause state in Locus route simulation.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("locusToggleRoutePause"), object: nil)
        }
        return .result()
    }
}
#endif

#if canImport(ActivityKit) && canImport(WidgetKit)

private func parseLiveActivityColor(hex: String, fallback: Color = .orange) -> Color {
    let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    guard Scanner(string: clean).scanHexInt64(&int) else { return fallback }
    switch clean.count {
    case 3:
        let r = Double((int >> 8) * 17) / 255.0
        let g = Double((int >> 4 & 0xF) * 17) / 255.0
        let b = Double((int & 0xF) * 17) / 255.0
        return Color(red: r, green: g, blue: b)
    case 6:
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    case 8:
        let r = Double((int >> 24) & 0xFF) / 255.0
        let g = Double((int >> 16) & 0xFF) / 255.0
        let b = Double((int >> 8) & 0xFF) / 255.0
        let a = Double(int & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b, opacity: a)
    default:
        return fallback
    }
}

@available(iOS 16.1, *)
struct LocusLiveActivityWidgetView: View {
    let context: ActivityViewContext<LocusRouteActivityAttributes>

    init(context: ActivityViewContext<LocusRouteActivityAttributes>) {
        self.context = context
    }

    private var state: LocusRouteActivityAttributes.ContentState {
        context.state
    }

    private var badgeColor: Color {
        parseLiveActivityColor(hex: state.badgeColorHex, fallback: .orange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Header: Icon + Title + Live Speed & Interactive Pause Button
            HStack(alignment: .center, spacing: 10) {
                // Large Glowing Transit Icon
                ZStack {
                    Circle()
                        .fill(badgeColor.opacity(0.25))
                        .frame(width: 40, height: 40)
                    Image(systemName: state.isCompleted ? "checkmark" : (state.isPaused ? "pause.fill" : "clock.fill"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(badgeColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(state.statusTitle)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if state.isPaused {
                            Text("PAUSED")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.yellow))
                        }
                    }

                    HStack(spacing: 6) {
                        if let badge = state.badgeNumber {
                            Text(badge)
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(badgeColor))
                        }
                        Text(state.statusSubtitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Speed Pill & Interactive Pause Button
                HStack(spacing: 8) {
                    if !state.currentSpeedFormatted.isEmpty && !state.isCompleted {
                        Text(state.currentSpeedFormatted)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }

                    #if canImport(AppIntents)
                    if #available(iOS 17.0, *), !state.isCompleted {
                        Button(intent: ToggleRouteSimulationIntent()) {
                            Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                    }
                    #endif
                }
            }

            // Big Rich Progress Bar Track with Moving Walker/Vehicle Glyph
            GeometryReader { geo in
                let trackWidth = geo.size.width
                let progressClamped = CGFloat(min(1.0, max(0.0, state.progress)))

                ZStack(alignment: .leading) {
                    // Track Background
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .frame(height: 8)

                    // Active Glowing Progress Track
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [badgeColor.opacity(0.8), badgeColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(16, trackWidth * progressClamped), height: 8)

                    // Moving Walker / Vehicle Badge along track
                    HStack(spacing: 0) {
                        Spacer()
                            .frame(width: max(0, (trackWidth - 26) * progressClamped))

                        ZStack {
                            Circle()
                                .fill(badgeColor)
                                .frame(width: 26, height: 26)
                                .shadow(color: badgeColor.opacity(0.7), radius: 5, y: 1)
                            Image(systemName: state.travelModeIcon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .frame(height: 26)

            // Bottom Arrival ETA, Distance Left, and Time Remaining
            HStack(alignment: .center) {
                HStack(spacing: 5) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(badgeColor)
                    Text(state.arrivalText)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                HStack(spacing: 8) {
                    if !state.remainingDistanceText.isEmpty && !state.isCompleted {
                        Text(state.remainingDistanceText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Text(state.remainingTimeText)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.12, green: 0.08, blue: 0.05).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(badgeColor.opacity(0.4), lineWidth: 1.2)
                )
        )
    }
}

@available(iOS 16.1, *)
struct LocusRouteLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LocusRouteActivityAttributes.self) { context in
            // Lock Screen and Notification Center Widget
            LocusLiveActivityWidgetView(context: context)
        } dynamicIsland: { context in
            let tintColor = parseLiveActivityColor(hex: context.state.badgeColorHex, fallback: .orange)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: context.state.travelModeIcon)
                            .foregroundStyle(tintColor)
                        Text(context.state.statusTitle)
                            .font(.headline.weight(.heavy))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.arrivalText)
                        .font(.subheadline.weight(.bold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LocusLiveActivityWidgetView(context: context)
                }
            } compactLeading: {
                Image(systemName: context.state.travelModeIcon)
                    .foregroundStyle(tintColor)
            } compactTrailing: {
                Text(context.state.remainingTimeText)
                    .font(.caption2.weight(.bold))
            } minimal: {
                Image(systemName: context.state.travelModeIcon)
                    .foregroundStyle(tintColor)
            }
        }
    }
}
#endif
