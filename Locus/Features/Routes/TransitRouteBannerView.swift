import SwiftUI
import CoreLocation

struct TransitRouteBannerView: View {
    @ObservedObject var session: SpoofSession
    var onEndRouteRequest: () -> Void

    @State private var isCollapsed: Bool = false

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
        VStack(spacing: 0) {
            // Main Apple Transit Live Card matching IMG_2247
            VStack(alignment: .leading, spacing: 10) {
                // Header Row
                HStack(alignment: .center, spacing: 10) {
                    // Transit Icon & Status
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.22))
                            .frame(width: 38, height: 38)
                        Image(systemName: headerIconName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(headerTitle)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            if session.isRoutePaused {
                                Text("PAUSED")
                                    .font(.system(size: 10, weight: .black))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.yellow.opacity(0.85)))
                                    .foregroundStyle(.black)
                            }
                        }

                        HStack(spacing: 6) {
                            // Line / Mode Badge
                            HStack(spacing: 3) {
                                Image(systemName: session.travelMode.icon)
                                    .font(.system(size: 10, weight: .bold))
                                Text(session.travelMode.title)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.orange))
                            .foregroundStyle(.black)

                            Text(subHeaderDetail)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                    }

                    Spacer()

                    // Quick Collapse / Expand chevron
                    Button {
                        SoundManager.play(.tap)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }

                // Dwell Stop Active Banner (Scheduled Stop, Red Light, or Bus Stop)
                if let stopName = session.activeStopName, let seconds = session.activeStopRemainingSeconds {
                    HStack(spacing: 8) {
                        Image(systemName: session.isTrafficLightStopActive ? "trafficlight.fill" : (session.isBusStopActive ? "bus.fill" : "clock.badge.fill"))
                            .font(.subheadline)
                            .foregroundStyle(Color.orange)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(stopName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                            Text("Dwelling • \(Int(ceil(seconds)))s remaining")
                                .font(.caption2)
                                .foregroundStyle(Color.white.opacity(0.8))
                        }

                        Spacer()

                        Button {
                            SoundManager.play(.toggle)
                            session.skipCurrentStop()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "forward.fill")
                                Text("Skip")
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.orange))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.18)))
                }

                if !isCollapsed {
                    // Apple Maps Transit Progress Track Bar
                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Background Bar
                                Capsule()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(height: 6)

                                // Active Filled Segment
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.orange, LocusTheme.accent],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(8, geo.size.width * CGFloat(session.routeProgress)), height: 6)

                                // Moving Head Dot
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 12, height: 12)
                                    .shadow(color: .orange.opacity(0.8), radius: 4)
                                    .offset(x: max(0, min(geo.size.width - 12, (geo.size.width * CGFloat(session.routeProgress)) - 6)))
                            }
                        }
                        .frame(height: 12)
                    }

                    // Bottom Destination & Duration Line (matching IMG_2247)
                    HStack(alignment: .center) {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.orange)
                            Text("Arrive at \(arrivalTimeString)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        Spacer()

                        Text(remainingDurationString)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Divider()
                        .background(Color.white.opacity(0.15))
                        .padding(.vertical, 2)

                    // Control Buttons: Pause/Resume, Stop Route (with confirmation)
                    HStack(spacing: 12) {
                        Button {
                            SoundManager.play(.toggle)
                            withAnimation {
                                session.togglePauseRoute()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: session.isRoutePaused ? "play.fill" : "pause.fill")
                                Text(session.isRoutePaused ? "Resume" : "Pause")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.15)))
                        }
                        .buttonStyle(.plain)

                        Button {
                            SoundManager.play(.alert)
                            onEndRouteRequest()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "stop.fill")
                                Text("End Route")
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.75)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.16, green: 0.08, blue: 0.04).opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.orange.opacity(0.35), lineWidth: 1.2)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            )
        }
        .padding(.horizontal, 14)
    }

    private var headerIconName: String {
        if session.activeStopName != nil {
            return "clock.badge.fill"
        }
        return "clock.fill"
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
        let speedText = String(format: "%.1f mph", session.currentSpeedMPS * 2.23694)
        let distText = RouteBuilder.formattedDistance(session.remainingRouteDistance)
        return "\(distText) left • \(speedText)"
    }
}
