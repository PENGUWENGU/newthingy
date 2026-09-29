import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

#if canImport(ActivityKit) && canImport(WidgetKit)
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
        Color(hex: state.badgeColorHex) ?? Color.orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Header Row (matching reference Lock Screen card)
            HStack(alignment: .center, spacing: 10) {
                // Clock / Transit Icon
                ZStack {
                    Circle()
                        .fill(badgeColor.opacity(0.2))
                        .frame(width: 34, height: 34)
                    Image(systemName: state.isCompleted ? "checkmark" : "clock.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(badgeColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.statusTitle)
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

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

                if !state.currentSpeedFormatted.isEmpty && !state.isCompleted {
                    Text(state.currentSpeedFormatted)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }

            // Progress Bar Track with Moving Marker (matching Transit card)
            GeometryReader { geo in
                let trackWidth = geo.size.width
                let progressClamped = CGFloat(min(1.0, max(0.0, state.progress)))

                ZStack(alignment: .leading) {
                    // Track Background
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 7)

                    // Active Progress Track
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [badgeColor.opacity(0.8), badgeColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(14, trackWidth * progressClamped), height: 7)

                    // Moving Walker / Vehicle Badge along track
                    HStack(spacing: 0) {
                        Spacer()
                            .frame(width: max(0, (trackWidth - 22) * progressClamped))

                        ZStack {
                            Circle()
                                .fill(badgeColor)
                                .frame(width: 22, height: 22)
                                .shadow(color: badgeColor.opacity(0.6), radius: 4, y: 1)
                            Image(systemName: state.travelModeIcon)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .frame(height: 22)

            // Bottom Arrival & Time Row
            HStack(alignment: .center) {
                HStack(spacing: 5) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(badgeColor)
                    Text(state.arrivalText)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Text(state.remainingTimeText)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.95))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(red: 0.12, green: 0.08, blue: 0.05).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(badgeColor.opacity(0.35), lineWidth: 1)
                )
        )
    }
}
#endif
