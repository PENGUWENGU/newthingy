import SwiftUI
import CoreLocation

/// Unified Live Activity style Route HUD matching Locus Liquid Glass design system.
struct TransitRouteBannerView: View {
    @ObservedObject var session: SpoofSession
    var onTogglePause: (() -> Void)? = nil
    var onStop: (() -> Void)? = nil
    var onSkipStop: (() -> Void)? = nil
    var onOpenPlanner: (() -> Void)? = nil

    @State private var isCollapsed: Bool = false

    init(
        session: SpoofSession,
        onTogglePause: (() -> Void)? = nil,
        onStop: (() -> Void)? = nil,
        onSkipStop: (() -> Void)? = nil,
        onOpenPlanner: (() -> Void)? = nil
    ) {
        self.session = session
        self.onTogglePause = onTogglePause
        self.onStop = onStop
        self.onSkipStop = onSkipStop
        self.onOpenPlanner = onOpenPlanner
    }

    private var arrivalTimeString: String {
        let arrivalDate = Date().addingTimeInterval(session.remainingRouteDuration)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: arrivalDate)
    }

    private var remainingDurationString: String {
        let total = Int(session.remainingRouteDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours) h \(minutes) min"
        } else if minutes > 0 {
            return "\(minutes) min"
        } else {
            return "\(total) sec"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Live Route Activity Card
            VStack(alignment: .leading, spacing: 10) {
                // Header Row
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LocusTheme.accent.opacity(0.18))
                            .frame(width: 38, height: 38)
                        Image(systemName: headerIconName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(LocusTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(headerTitle)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(LocusTheme.textColor)

                            if session.isRoutePaused {
                                Text("PAUSED")
                                    .font(.system(size: 10, weight: .black))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.85)))
                                    .foregroundStyle(.black)
                            }
                        }

                        HStack(spacing: 6) {
                            // Travel Mode Badge
                            HStack(spacing: 3) {
                                Image(systemName: session.travelMode.icon)
                                    .font(.system(size: 10, weight: .bold))
                                Text(session.travelMode.title)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 6).fill(LocusTheme.accent))
                            .foregroundStyle(.black)

                            Text(subHeaderDetail)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(LocusTheme.textColor.opacity(0.8))
                        }
                    }

                    Spacer()

                    // Quick Collapse / Expand
                    Button {
                        SoundManager.play(.tap)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(LocusTheme.textColor.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }

                // Dwell Stop Active Banner
                if let stopName = session.activeStopName, let seconds = session.activeStopRemainingSeconds {
                    HStack(spacing: 8) {
                        Image(systemName: session.isTrafficLightStopActive ? "trafficlight.fill" : (session.isBusStopActive ? "bus.fill" : "clock.badge.fill"))
                            .font(.subheadline)
                            .foregroundStyle(LocusTheme.accentSecondary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(stopName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(LocusTheme.textColor)
                            Text("Dwelling • \(Int(ceil(seconds)))s remaining")
                                .font(.caption2)
                                .foregroundStyle(LocusTheme.textColor.opacity(0.75))
                        }

                        Spacer()

                        Button {
                            SoundManager.play(.toggle)
                            if let onSkipStop {
                                onSkipStop()
                            } else {
                                session.skipCurrentStop()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "forward.fill")
                                Text("Skip")
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(LocusTheme.accentSecondary))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(LocusTheme.accentSecondary.opacity(0.12)))
                }

                if !isCollapsed {
                    // Route Progress Bar
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.12))
                                    .frame(height: 6)

                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [LocusTheme.accent, LocusTheme.accentSecondary],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(8, geo.size.width * CGFloat(session.routeProgress)), height: 6)

                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 12, height: 12)
                                    .shadow(color: LocusTheme.accent.opacity(0.8), radius: 4)
                                    .offset(x: max(0, min(geo.size.width - 12, (geo.size.width * CGFloat(session.routeProgress)) - 6)))
                            }
                        }
                        .frame(height: 12)
                    }

                    // ETA & Duration Line
                    HStack(alignment: .center) {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(LocusTheme.accent)
                            Text("Arrive at \(arrivalTimeString)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(LocusTheme.textColor)
                        }

                        Spacer()

                        Text(remainingDurationString)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(LocusTheme.accent)
                    }

                    Divider().opacity(0.2)

                    // Control Buttons
                    HStack(spacing: 10) {
                        Button {
                            SoundManager.play(.toggle)
                            if let onTogglePause {
                                onTogglePause()
                            } else {
                                withAnimation {
                                    session.togglePauseRoute()
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: session.isRoutePaused ? "play.fill" : "pause.fill")
                                Text(session.isRoutePaused ? "Resume" : "Pause")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LocusTheme.textColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)

                        Button {
                            SoundManager.play(.alert)
                            if let onStop {
                                onStop()
                            } else {
                                session.stopRoute()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                Text("End Route")
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(LocusTheme.danger.opacity(0.85)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var headerIconName: String {
        if session.activeStopName != nil {
            return "clock.badge.fill"
        }
        return "location.north.line.fill"
    }

    private var headerTitle: String {
        if session.remainingRouteDuration > 60 {
            let mins = Int(ceil(session.remainingRouteDuration / 60))
            return "Arrive in \(mins) min\(mins == 1 ? "" : "s")"
        } else if session.remainingRouteDuration > 0 {
            return "Arriving momentarily"
        } else {
            return "Arrived at Destination"
        }
    }

    private var subHeaderDetail: String {
        let effectiveSpeed = (session.isRoutePaused || session.activeStopName != nil)
            ? 0.0
            : (session.liveSpeedMPS > 0.1 ? session.liveSpeedMPS : session.currentSpeedMPS)
        let speedText = session.speedUnit.format(effectiveSpeed)
        let distText = RouteBuilder.formattedDistance(session.remainingRouteDistance)
        return "\(distText) left • \(speedText)"
    }
}
