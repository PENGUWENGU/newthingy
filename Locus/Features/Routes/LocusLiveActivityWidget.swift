import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(AppIntents) && canImport(ActivityKit)
import AppIntents
import ActivityKit

@available(iOS 17.0, *)
struct ToggleRouteSimulationIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Route"
    static var description = IntentDescription("Toggles pause state in Locus route simulation.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .locusToggleRoutePause, object: nil)
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

            // WidgetKit-safe Progress Track with Glowing Fill & Mode Badge
            let progressClamped = min(1.0, max(0.0, state.progress))
            let stopLoc = max(0.02, min(0.99, progressClamped))

            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: badgeColor.opacity(0.85), location: 0.0),
                                    .init(color: badgeColor, location: stopLoc),
                                    .init(color: Color.white.opacity(0.16), location: min(1.0, stopLoc + 0.005)),
                                    .init(color: Color.white.opacity(0.16), location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 10)
                }

                ZStack {
                    Circle()
                        .fill(badgeColor)
                        .frame(width: 26, height: 26)
                    Image(systemName: state.travelModeIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
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
                        .foregroundStyle(badgeColor)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.10, green: 0.09, blue: 0.08).opacity(0.96))
        )
    }
}

@available(iOS 16.1, *)
struct LocusRouteLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LocusRouteActivityAttributes.self) { context in
            LocusLiveActivityWidgetView(context: context)
                .activityBackgroundTint(Color(red: 0.10, green: 0.09, blue: 0.08))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.travelModeIcon)
                            .foregroundStyle(parseLiveActivityColor(hex: context.state.badgeColorHex, fallback: .orange))
                        Text(context.state.statusTitle)
                            .font(.subheadline.weight(.heavy))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.currentSpeedFormatted)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(parseLiveActivityColor(hex: context.state.badgeColorHex, fallback: .orange))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(value: min(1.0, max(0.0, context.state.progress)))
                            .tint(parseLiveActivityColor(hex: context.state.badgeColorHex, fallback: .orange))
                        HStack {
                            Text(context.state.arrivalText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !context.state.remainingDistanceText.isEmpty && !context.state.isCompleted {
                                Text("\(context.state.remainingDistanceText) • \(context.state.remainingTimeText)")
                                    .font(.caption2.weight(.bold))
                            } else {
                                Text(context.state.remainingTimeText)
                                    .font(.caption2.weight(.bold))
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: context.state.travelModeIcon)
                    .foregroundStyle(parseLiveActivityColor(hex: context.state.badgeColorHex, fallback: .orange))
            } compactTrailing: {
                Text(context.state.remainingTimeText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(parseLiveActivityColor(hex: context.state.badgeColorHex, fallback: .orange))
            } minimal: {
                Image(systemName: context.state.travelModeIcon)
                    .foregroundStyle(parseLiveActivityColor(hex: context.state.badgeColorHex, fallback: .orange))
            }
        }
    }
}

@available(iOS 16.1, *)
struct LocusSpoofLiveActivityWidgetView: View {
    let context: ActivityViewContext<LocusSpoofActivityAttributes>

    var body: some View {
        let state = context.state
        let tint = parseLiveActivityColor(hex: state.badgeColorHex, fallback: Color(red: 0.19, green: 0.82, blue: 0.35))

        VStack(spacing: 12) {
            // Header bar
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                    Text("LOCUS • SPOOF ACTIVE")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(tint)
                        .tracking(1.0)
                }

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(state.spoofStartedAt, style: .timer)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.12), in: Capsule())
            }

            // Location details & telemetry pill
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: state.isJoystickMoving ? "gamecontroller.fill" : "mappin.and.ellipse")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.locationTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(state.coordinateLabel)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(state.speedFormatted)
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(tint)
                    Text(state.isJoystickMoving ? "Moving" : "Holding")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // Bottom banner
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                    Text("Continuous GPS telemetry active for Life360 & Find My")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.10, green: 0.09, blue: 0.08).opacity(0.96))
        )
    }
}

@available(iOS 16.1, *)
struct LocusSpoofLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LocusSpoofActivityAttributes.self) { context in
            LocusSpoofLiveActivityWidgetView(context: context)
                .activityBackgroundTint(Color(red: 0.10, green: 0.09, blue: 0.08))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.isJoystickMoving ? "gamecontroller.fill" : "location.north.circle.fill")
                            .foregroundStyle(parseLiveActivityColor(hex: context.state.badgeColorHex, fallback: Color(red: 0.19, green: 0.82, blue: 0.35)))
                        Text(context.state.statusHeadline)
                            .font(.subheadline.weight(.heavy))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.speedFormatted)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(parseLiveActivityColor(hex: context.state.badgeColorHex, fallback: Color(red: 0.19, green: 0.82, blue: 0.35)))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.locationTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(context.state.coordinateLabel)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(parseLiveActivityColor(hex: context.state.badgeColorHex, fallback: Color(red: 0.19, green: 0.82, blue: 0.35)))
                                .frame(width: 8, height: 8)
                            Text(context.state.spoofStartedAt, style: .timer)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: context.state.isJoystickMoving ? "gamecontroller.fill" : "location.fill")
                    .foregroundStyle(parseLiveActivityColor(hex: context.state.badgeColorHex, fallback: Color(red: 0.19, green: 0.82, blue: 0.35)))
            } compactTrailing: {
                Text(context.state.spoofStartedAt, style: .timer)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(parseLiveActivityColor(hex: context.state.badgeColorHex, fallback: Color(red: 0.19, green: 0.82, blue: 0.35)))
                    .frame(width: 44, alignment: .trailing)
            } minimal: {
                Image(systemName: context.state.isJoystickMoving ? "gamecontroller.fill" : "location.fill")
                    .foregroundStyle(parseLiveActivityColor(hex: context.state.badgeColorHex, fallback: Color(red: 0.19, green: 0.82, blue: 0.35)))
            }
        }
    }
}
#endif
