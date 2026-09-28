import SwiftUI

struct JoystickPad: View {
    var onChange: (CGVector) -> Void
    var onClose: (() -> Void)? = nil

    @State private var dragOffset: CGSize = .zero
    private let radius: CGFloat = 26

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .frame(width: radius * 2 + 14, height: radius * 2 + 14)
                    .locusGlass(.clear, in: Circle())

                Circle()
                    .stroke(LocusTheme.accent.opacity(0.4), lineWidth: 1.5)
                    .frame(width: radius * 2, height: radius * 2)

                Circle()
                    .fill(LocusTheme.accent)
                    .frame(width: 22, height: 22)
                    .shadow(color: LocusTheme.accent.opacity(0.5), radius: 5)
                    .offset(dragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let limited = clamp(value.translation, radius: radius)
                                dragOffset = limited
                                onChange(CGVector(dx: limited.width / radius, dy: limited.height / radius))
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    dragOffset = .zero
                                }
                                onChange(.zero)
                            }
                    )
            }
            .frame(width: radius * 2 + 18, height: radius * 2 + 18)

            if let onClose {
                Button {
                    SoundManager.play(.toggle)
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.8), Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .accessibilityLabel("Close Joystick")
            }
        }
        .accessibilityLabel("Movement joystick")
    }

    private func clamp(_ translation: CGSize, radius: CGFloat) -> CGSize {
        let length = sqrt(translation.width * translation.width + translation.height * translation.height)
        guard length > radius else { return translation }
        let scale = radius / length
        return CGSize(width: translation.width * scale, height: translation.height * scale)
    }
}
