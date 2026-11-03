import CoreLocation
import SwiftUI

// MARK: - Crash Recovery Floating Banner

public struct CrashRecoveryBannerView: View {
    @ObservedObject var recoveryManager = CrashRecoveryManager.shared
    @ObservedObject var session: SpoofSession
    var pairing: PairingStore

    public init(session: SpoofSession, pairing: PairingStore) {
        self.session = session
        self.pairing = pairing
    }

    public var body: some View {
        if recoveryManager.showRecoveryPrompt, let snapshot = recoveryManager.pendingRecoverySnapshot {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Image(systemName: snapshot.sessionType == .route ? "point.topleft.down.to.point.bottomright.curvepath" : "mappin.and.ellipse")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(snapshot.sessionType == .route ? "Resume Interrupted Route?" : "Restore Last Spoofed Location?")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.primary)

                            Text("Recovered")
                                .font(.system(size: 9, weight: .black))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange))
                                .foregroundStyle(.black)
                        }

                        if snapshot.sessionType == .route {
                            let percent = Int(round((snapshot.routeProgress ?? 0.0) * 100.0))
                            Text("The previous route (\(snapshot.routeName ?? "Route"), \(percent)% complete) stopped unexpectedly. Tap to continue right where it was.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else {
                            Text("You were spoofed at \(snapshot.locationName) (\(String(format: "%.4f, %.4f", snapshot.lastCoordinate.latitude, snapshot.lastCoordinate.longitude))). Tap to restore.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 4)

                    Button {
                        SoundManager.play(.tap)
                        withAnimation(.spring()) {
                            recoveryManager.dismissRecovery()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Button {
                        SoundManager.play(.success)
                        withAnimation(.spring()) {
                            session.resumeFromCrash(snapshot: snapshot, pairing: pairing)
                            recoveryManager.dismissRecovery()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                            Text(snapshot.sessionType == .route ? "Resume Route from Here" : "Restore Location")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(session.primaryAccentColor)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        SoundManager.play(.tap)
                        withAnimation(.spring()) {
                            recoveryManager.dismissRecovery()
                        }
                    } label: {
                        Text("Dismiss")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.12, blue: 0.18).opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.orange.opacity(0.4), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 10, y: 5)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
