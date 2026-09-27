import SwiftUI
import CoreLocation

struct WaypointMarkerView: View {
    let index: Int
    let totalCount: Int
    let coordinate: CLLocationCoordinate2D
    var isSelected: Bool
    var onSelect: () -> Void
    var onRemove: () -> Void

    private var isStart: Bool { index == 0 }
    private var isEnd: Bool { index == totalCount - 1 && totalCount > 1 }

    private var badgeColor: Color {
        if isStart {
            return LocusTheme.statusGood
        } else if isEnd {
            return LocusTheme.accentSecondary
        } else {
            return LocusTheme.accent
        }
    }

    private var labelText: String {
        if isStart {
            return "Start"
        } else if isEnd {
            return "End"
        } else {
            return "\(index + 1)"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            if isSelected {
                Button(action: onRemove) {
                    Label("Remove #\(index + 1)", systemImage: "trash.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(LocusTheme.danger)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .locusGlass(.regular, in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }

            ZStack {
                Circle()
                    .fill(.black.opacity(0.35))
                    .frame(width: 32, height: 32)
                    .blur(radius: 2)

                Circle()
                    .fill(badgeColor)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(.white, lineWidth: 2))

                Text("\(index + 1)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
            }
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}
