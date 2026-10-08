import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var showNameEasterEgg = false
    @State private var showThemeCustomizer = false
    @State private var tunnelIP = TunnelConfig.targetIP
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @Environment(\.scenePhase) private var scenePhase

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(pairing.hasPairingFile ? "RPPairing file installed" : "No pairing file")
                    } icon: {
                        Image(systemName: pairing.hasPairingFile ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pairing.hasPairingFile ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }

                    if supportsOnDevicePairing {
                        Button {
                            showPairOnDevice = true
                        } label: {
                            Label("Pair on this iPhone", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }

                    Button("Import RPPairing file…") { showImporter = true }
                    Button("Paste RPPairing from clipboard") {
                        do {
                            try pairing.importPairingFromClipboard()
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    }
                    if pairing.hasPairingFile {
                        Button("Remove pairing file", role: .destructive) {
                            try? pairing.removePairing()
                        }
                    }
                } header: {
                    Text("Developer pairing")
                } footer: {
                    Text(supportsOnDevicePairing
                         ? "On iOS 27, use Pair on this iPhone — no computer. Locus advertises a pairable host; confirm the 6-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host. On older iOS, import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). LiveContainer: enable Fix File Picker on Locus, or use Paste / Share → LiveContainer → Locus."
                         : "Import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). If the file picker fails (common in LiveContainer), enable Fix File Picker on the app, share the file into LiveContainer → Locus, or copy the plist and use Paste.")
                }

                Section {
                    TextField("Device tunnel IP", text: $tunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            TunnelConfig.setTargetIP(tunnelIP)
                        }
                    LabeledContent("Status") {
                        Text(LocalDevVPN.isConnected ? "Connected" : "Not connected")
                            .foregroundStyle(LocalDevVPN.isConnected ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }
                    Button("Save tunnel IP") {
                        TunnelConfig.setTargetIP(tunnelIP)
                    }
                    Button {
                        if localDevVPNInstalled {
                            LocalDevVPN.openInstalled()
                        } else {
                            LocalDevVPN.openAppStore()
                        }
                    } label: {
                        Label(
                            localDevVPNInstalled ? "Open LocalDevVPN" : "Get LocalDevVPN (App Store)",
                            systemImage: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill"
                        )
                    }
                } header: {
                    Text("Tunnel")
                } footer: {
                    Text("Connect LocalDevVPN before teleporting. Default tunnel IP is 10.7.0.1. Start a spoof on Wi‑Fi first; it can keep working on cellular afterward.")
                }

                Section {
                    Button {
                        SoundManager.play(.tap)
                        showThemeCustomizer = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [session.primaryAccentColor, session.secondaryAccentColor],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 38, height: 38)
                                Image(systemName: "paintpalette.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.black)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open Interactive Theme Studio")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text("\(session.accentTheme.rawValue) • \(session.pathWidth.rawValue) • \(session.uiAppearance.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    Toggle("Button Audio Feedback", isOn: Binding(
                        get: { SoundManager.shared.isSoundEnabled },
                        set: { SoundManager.shared.isSoundEnabled = $0 }
                    ))
                } header: {
                    Text("Appearance & Feedback")
                } footer: {
                    Text("Preview custom colors, route line geometry, glass materials, and completion flash effects in an interactive live sandbox before saving.")
                }

                Section {
                    Toggle("Live Activities", isOn: Binding(
                        get: { session.liveActivitiesEnabled },
                        set: {
                            session.liveActivitiesEnabled = $0
                            UserDefaults.standard.set($0, forKey: "locus.liveActivitiesEnabled")
                        }
                    ))
                    Toggle("Route Completion Notification", isOn: $session.routeNotificationsEnabled)

                    HStack {
                        Label("Traveler / Device Name", systemImage: "person.crop.circle")
                        Spacer()
                        TextField("e.g. Alex or Eddie", text: Binding(
                            get: { session.travelerName },
                            set: { session.setTravelerName($0) }
                        ))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.primary)
                    }

                    Button {
                        session.testArrivalNotification()
                    } label: {
                        HStack {
                            Label("Send Test Arrival Notification", systemImage: "paperplane.fill")
                                .foregroundStyle(session.primaryAccentColor)
                            Spacer()
                        }
                    }
                } header: {
                    Text("Live Activities & Alerts")
                } footer: {
                    Text("Show live departure countdown, progress, and speed on your Lock Screen and Dynamic Island for active routes and stationary spoofing. Enter your traveler name to personalize arrival notifications (e.g. 'Alex arrived at Home!').")
                }

                Section {
                    Picker("Speed Unit", selection: Binding(
                        get: { session.speedUnit },
                        set: {
                            SoundManager.play(.toggle)
                            session.setSpeedUnit($0)
                        }
                    )) {
                        ForEach(SpeedUnit.allCases) { u in
                            Text(u.label).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Smart Traffic Lights", isOn: $session.smartTrafficLights)
                    Toggle("Smart Transit Bus Stops", isOn: $session.busModeSmartStops)
                    Toggle("Life360 & Continuous GPS Realism", isOn: Binding(
                        get: { session.life360RealismEnabled },
                        set: {
                            session.life360RealismEnabled = $0
                            UserDefaults.standard.set($0, forKey: "locus.life360Realism")
                        }
                    ))
                    Toggle("Stationary Micro-Drift", isOn: Binding(
                        get: { session.stationaryDriftEnabled },
                        set: {
                            session.stationaryDriftEnabled = $0
                            UserDefaults.standard.set($0, forKey: "locus.stationaryDrift")
                        }
                    ))

                    Toggle("Random Speed Fluctuations (Life360)", isOn: Binding(
                        get: { session.speedRandomnessEnabled },
                        set: { session.setSpeedRandomnessEnabled($0) }
                    ))

                    if session.speedRandomnessEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Speed Variance Range")
                                Spacer()
                                Text("±\(String(format: "%.0f", session.speedVarianceMPH)) mph")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(session.primaryAccentColor)
                            }
                            Picker("Variance Range", selection: Binding(
                                get: { session.speedVarianceMPH },
                                set: { session.setSpeedVariance($0) }
                            )) {
                                Text("±1 mph").tag(1.0)
                                Text("±2 mph").tag(2.0)
                                Text("±3 mph").tag(3.0)
                                Text("±4 mph").tag(4.0)
                                Text("±5 mph").tag(5.0)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Movement & Spoof Realism")
                } footer: {
                    Text("Continuous 1.0 Hz Great Circle traversal, dynamic 1–5 mph throttle variance, corner slowdowns, and Gauss-Markov drift prevent constant-speed bot detection on Life360 & Find My so movement correctly tracks in vehicle.")
                }

                Section {
                    Picker("Default Connection Mode", selection: Binding(
                        get: { session.defaultConnectionType },
                        set: { session.setDefaultConnectionType($0) }
                    )) {
                        ForEach(RouteConnectionType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                } header: {
                    Text("Routing Defaults")
                } footer: {
                    Text("Choose the default connection mode for Points routes. 'Roads' calculates street routes with Apple Maps; 'Straight' connects waypoints with direct straight lines.")
                }

                Section("Privacy") {
                    Text("Fully on-device. Favorites, recents, and saved routes stay in UserDefaults on your device. No analytics, no accounts, nothing uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Engine", value: "idevice DVT location simulation")
                    Text("Locus is free and open source (MIT). Location injection uses the MIT-licensed idevice FFI.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showNameEasterEgg = true
                    } label: {
                        Text("locus, n. — a place. From the Latin for where you are.")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        TunnelConfig.setTargetIP(tunnelIP)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
            .sheet(isPresented: $showPairOnDevice) {
                PairOnDeviceView()
                    .environmentObject(pairing)
            }
            .sheet(isPresented: $showThemeCustomizer) {
                ThemeCustomizerSheet(session: session)
            }
            .fullScreenCover(isPresented: $showNameEasterEgg) {
                LocusEasterEggView()
            }
            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
        }
    }
}

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Favorites") {
                    if session.favorites.isEmpty {
                        Text("Star a pin from the map to save it.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.favorites) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeFavorite(place)
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                                Button {
                                    placeToRename = place
                                    renameText = place.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                    }
                }

                Section("Recents") {
                    if session.recents.isEmpty {
                        Text("Teleports show up here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.recents) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeRecent(place)
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Places")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Favorite", isPresented: Binding(
                get: { placeToRename != nil },
                set: { if !$0 { placeToRename = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {
                    placeToRename = nil
                }
                Button("Save") {
                    if let place = placeToRename {
                        session.renameFavorite(place, to: renameText)
                    }
                    placeToRename = nil
                }
            } message: {
                Text("Choose a name you’ll recognize later.")
            }
        }
    }

    private func placeButton(_ place: SavedPlace) -> some View {
        Button {
            session.teleport(to: place.coordinate, pairing: pairing)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
