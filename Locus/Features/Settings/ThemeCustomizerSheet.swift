import SwiftUI

struct ThemeCustomizerSheet: View {
    @ObservedObject var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Accent Color
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(AccentColorTheme.allCases) { theme in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        session.setAccentTheme(theme)
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        ZStack {
                                            Circle()
                                                .fill(theme.primaryColor)
                                                .frame(width: 44, height: 44)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.white, lineWidth: session.accentTheme == theme ? 3 : 0)
                                                )
                                                .shadow(color: theme.primaryColor.opacity(0.4), radius: 6, y: 2)

                                            if session.accentTheme == theme {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 16, weight: .black))
                                                    .foregroundStyle(.black)
                                            }
                                        }

                                        Text(theme.rawValue.components(separatedBy: " ").first ?? theme.rawValue)
                                            .font(.caption2.weight(session.accentTheme == theme ? .bold : .regular))
                                            .foregroundStyle(session.accentTheme == theme ? .primary : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                } header: {
                    Text("Accent Theme")
                } footer: {
                    Text("Select your primary vibrant accent color for routes, controls, and active UI elements.")
                }

                // MARK: - Path Line Thickness
                Section {
                    Picker("Path Thickness", selection: Binding(
                        get: { session.pathWidth },
                        set: { session.setPathWidth($0) }
                    )) {
                        ForEach(PathWidthPreference.allCases) { width in
                            Text(width.rawValue).tag(width)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Live Line Preview
                    HStack {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Capsule()
                            .fill(session.accentTheme.primaryColor)
                            .frame(width: 100, height: session.pathWidth.width)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Route Line Thickness")
                } footer: {
                    Text("Controls the stroke width of planned and active navigation paths on the map.")
                }

                // MARK: - UI Glass & Material Style
                Section {
                    Picker("Appearance Style", selection: Binding(
                        get: { session.uiAppearance },
                        set: { session.setUIAppearance($0) }
                    )) {
                        ForEach(UIAppearanceStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Interface Style")
                } footer: {
                    Text("Liquid Glass uses Apple's native glass shaders; High Contrast uses solid opaque backing for maximum outdoor visibility.")
                }

                // MARK: - Map Waypoint Badges
                Section {
                    Toggle("Show Waypoint Numbers", isOn: Binding(
                        get: { session.showWaypointLabels },
                        set: { session.setShowWaypointLabels($0) }
                    ))
                } header: {
                    Text("Map Overlays")
                } footer: {
                    Text("Display sequential numbered badges on route waypoints on the map.")
                }
            }
            .navigationTitle("Customize UI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }
}
