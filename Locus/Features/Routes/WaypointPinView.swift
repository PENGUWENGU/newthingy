import CoreLocation
import SwiftUI

struct WaypointPinView: View {
    let index: Int
    let total: Int
    var stopDuration: TimeInterval = 0
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    var onToggleStop: (() -> Void)? = nil

    private var badgeColor: Color {
        if stopDuration > 0 {
            return Color.orange
        } else if index == 0 {
            return LocusTheme.statusGood
        } else if index == total - 1 && total > 1 {
            return LocusTheme.accentSecondary
        } else {
            return LocusTheme.accent
        }
    }

    private var labelText: String {
        if index == 0 {
            return "1"
        } else {
            return "\(index + 1)"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            if isSelected {
                HStack(spacing: 6) {
                    if let onToggleStop {
                        Button(action: onToggleStop) {
                            HStack(spacing: 3) {
                                Image(systemName: stopDuration > 0 ? "stop.circle.fill" : "clock.arrow.circlepath")
                                Text(stopDuration > 0 ? "\(Int(stopDuration))s Stop" : "+ Stop")
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(stopDuration > 0 ? Color.orange : Color.blue))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onRemove) {
                        Image(systemName: "trash.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(LocusTheme.danger))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.scale.combined(with: .opacity))
            }

            ZStack {
                Circle()
                    .fill(badgeColor)
                    .frame(width: isSelected ? 34 : 28, height: isSelected ? 34 : 28)
                    .shadow(color: badgeColor.opacity(0.6), radius: isSelected ? 6 : 3, y: 1)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))

                Text(labelText)
                    .font(.system(size: isSelected ? 14 : 12, weight: .black))
                    .foregroundStyle(.black)

                if stopDuration > 0 {
                    Image(systemName: "clock.badge.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.orange)
                        .background(Circle().fill(Color.black).frame(width: 14, height: 14))
                        .offset(x: 12, y: -12)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                onSelect()
            }
        }
        .accessibilityLabel("Waypoint \(index + 1)\(stopDuration > 0 ? ", \(Int(stopDuration)) seconds stop" : "")")
    }
}
