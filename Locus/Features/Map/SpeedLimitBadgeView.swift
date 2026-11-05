import SwiftUI

// MARK: - Road Speed Limit Sign Badge

struct SpeedLimitBadgeView: View {
    @ObservedObject var speedService = RoadSpeedLimitService.shared
    @ObservedObject var session: SpoofSession

    init(session: SpoofSession) {
        self.session = session
    }

    private func speedText(for info: RoadSpeedInfo) -> String {
        let value: Double = (session.speedUnit == .kmh) ? info.speedLimitKMH : info.speedLimitMPH
        return "\(Int(round(value)))"
    }

    private var badgeBackgroundColor: Color {
        session.adhereToSpeedLimits ? Color.green.opacity(0.18) : Color(white: 0.12).opacity(0.90)
    }

    private var badgeBorderColor: Color {
        session.adhereToSpeedLimits ? Color.green.opacity(0.6) : Color.white.opacity(0.15)
    }

    @ViewBuilder
    private func signPlate(for info: RoadSpeedInfo) -> some View {
        VStack(spacing: 0) {
            Text("SPEED")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.black)
            Text("LIMIT")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(.black)
            Text(speedText(for: info))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
        }
        .frame(width: 44, height: 48)
        .background(Color.white)
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.black, lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 3, y: 2)
    }

    @ViewBuilder
    private func labelInfo(for info: RoadSpeedInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(info.roadName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if info.isExplicit {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                }
            }

            HStack(spacing: 4) {
                Text(session.adhereToSpeedLimits ? "Matching limit" : "Tap to match speed")
                    .font(.system(size: 10, weight: session.adhereToSpeedLimits ? .bold : .medium))
                    .foregroundStyle(session.adhereToSpeedLimits ? Color.green : Color.secondary)

                if session.adhereToSpeedLimits {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                }
            }
        }
    }

    var body: some View {
        if let info = speedService.currentRoadSpeed {
            Button {
                SoundManager.play(.toggle)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    session.adhereToSpeedLimits.toggle()
                    if session.adhereToSpeedLimits {
                        session.setCustomSpeed(info.speedLimitMPS)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    signPlate(for: info)
                    labelInfo(for: info)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(badgeBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(badgeBorderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        }
    }
}
