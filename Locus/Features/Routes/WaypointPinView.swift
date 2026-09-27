import CoreLocation
import SwiftUI

struct WaypointPinView: View {
    let index: Int
    let total: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    private var badgeColor: Color {
        if index == 0 {
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
                Button(action: onRemove) {
                    Label("Remove", systemImage: "trash.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(LocusTheme.danger))
                }
                .buttonStyle(.plain)
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
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                onSelect()
            }
        }
        .accessibilityLabel("Waypoint \(index + 1)")
    }
}
