import SwiftUI
import AppKit

enum LuminaText {
    static let muted = Color.secondary
    static let soft = Color.secondary.opacity(0.85)
    static let faint = Color.secondary.opacity(0.65)
}

struct ContentView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var controller = AutoBacklightController.shared
    @ObservedObject private var sun = SunScheduleManager.shared

    // Onboarding Wizard Navigation
    @State private var onboardingPage = 0

    // Custom-period editing state
    @State private var editingID: UUID? = nil
    @State private var draft: BrightnessPeriod? = nil
    @State private var isAddingNew = false
    @State private var overlapWarning = false
    @State private var showManualLocationEditor = false
    @State private var showLocationControls = false

    @State private var showApproximateLocationConsent = false
    @State private var manualLatitude = ""
    @State private var manualLongitude = ""
    @State private var demoMinutes = 0
    @State private var demoSeconds = 30

    private var availableContentHeight: CGFloat {
        max(180, (NSScreen.main?.visibleFrame.height ?? 800) - 180)
    }

    private var mainContentHeight: CGFloat {
        min(customActive ? 520 : (prefs.inactivityTimeoutEnabled ? 370 : 310), availableContentHeight)
    }

    private var manualCoordinate: LocationCoordinate? {
        guard let latitude = Double(manualLatitude.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              let longitude = Double(manualLongitude.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) else { return nil }
        return LocationCoordinate(latitude: latitude, longitude: longitude)
    }

    private var systemActive: Bool { !prefs.overrideEnabled }
    private var customActive: Bool { prefs.overrideEnabled }

    private var versionLabel: String {
        Bundle.main.object(forInfoDictionaryKey: "LuminaReleaseVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        ZStack {
            if !prefs.hasCompletedOnboarding {
                onboardingPanel
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .bottom).combined(with: .opacity)))
            } else {
                mainPanel
                    .transition(.opacity)
            }
        }
        .frame(width: 380)
        .background(BackdropGradient(isNight: controller.isNightMode))
        .alert("Look up location by IP?", isPresented: $showApproximateLocationConsent) {
            Button("Look Up Location") { sun.requestApproximateLocationFromInternet() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This contacts ipapi.co, which receives your public IP address and may retain request logs. Lumina saves rounded coordinates on this Mac. This lookup runs only when you request it. You can use Mac location or manual coordinates instead.")
        }
        .animation(Motion.smooth, value: prefs.hasCompletedOnboarding)
        .onChange(of: draft) { _, _ in overlapWarning = false }
        .onDisappear(perform: collapseLocationControls)
    }

    private func collapseLocationControls() {
        guard showLocationControls || showManualLocationEditor else { return }
        withAnimation(Motion.smooth) {
            showLocationControls = false
            showManualLocationEditor = false
        }
    }

    // MARK: - Main Panel Layout
    private var mainPanel: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical) {
                VStack(spacing: 14) {
                    if controller.keyboardAvailable {
                        if systemActive { systemCard } else { customCard }
                        inactivityCard
                    } else {
                        unavailableView
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.visible)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: controller.keyboardAvailable ? mainContentHeight : 160)
            .accessibilityIdentifier("Main settings scroll area")
            Divider()
            footer
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill((controller.isNightMode ? Color.indigo : Color.orange)
                        .opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: controller.isNightMode ? "moon.stars.fill" : "sun.max.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle((controller.isNightMode ? Color.indigo : Color.orange).gradient)
                    .symbolRenderingMode(.hierarchical)
                    .transition(.scale.combined(with: .opacity))
                    .id(controller.isNightMode)
            }
            .animation(Motion.bouncy, value: controller.isNightMode)

            VStack(alignment: .leading, spacing: 2) {
                Text("Lumina").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(controller.currentStatus)
                        .font(.caption2).foregroundStyle(LuminaText.muted)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Motion.snappy, value: controller.currentStatus)
                }
            }

            Spacer()
            ModeSwitch(isAuto: $prefs.overrideEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusColor: Color {
        if !controller.keyboardAvailable { return .gray }
        if controller.activePeriodName != nil { return .indigo }
        return .orange
    }

    private var locationPillTint: Color {
        controller.isNightMode ? .indigo : .orange
    }

    private var locationPillIcon: String {
        return controller.isNightMode ? "moon.stars.fill" : "sun.max.fill"
    }

    // MARK: - Compact System Control View
    private var systemCard: some View {
        Card {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "laptopcomputer")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .frame(width: 20)
                    Text("System Control").font(.callout.weight(.semibold))
                    Spacer()
                }

                VStack(spacing: 14) {
                    BrightnessRow(
                        title: "Brightness",
                        value: $prefs.manualBrightness,
                        tint: .orange,
                        subtitle: prefs.manualAutoBrightness ? "Overridden by ambient sensor" : "Fixed level in 2% steps",
                        onEditing: { controller.previewBrightness($0) }
                    )
                    .disabled(prefs.manualAutoBrightness)
                    .opacity(prefs.manualAutoBrightness ? 0.45 : 1)

                    ToggleRow(
                        systemImage: "rays",
                        title: "Auto-Brightness",
                        subtitle: "Adjust to room lighting",
                        isOn: $prefs.manualAutoBrightness,
                        tint: .orange
                    )
                }
            }
        }
    }

    // MARK: - Expanded Custom Automations View
    private var customCard: some View {
        Card {
            VStack(spacing: 14) {
                SegmentedTabs(
                    selection: $prefs.automationTab,
                    items: [
                        (value: 0, label: "Sun Cycle", icon: "sun.horizon.fill"),
                        (value: 1, label: "Time Slots", icon: "clock.fill")
                    ],
                    tint: .indigo
                )

                Divider().opacity(0.5)

                if prefs.automationTab == 0 {
                    solarSection
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    customSection
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .animation(Motion.smooth, value: prefs.automationTab)
        }
    }

    // MARK: - Inactivity Timer Card
    private var inactivityCard: some View {
        Card {
            VStack(spacing: 10) {
                ToggleRow(
                    systemImage: "timer",
                    title: "Inactivity Timeout",
                    subtitle: "Turn off backlight when idle",
                    isOn: $prefs.inactivityTimeoutEnabled,
                    tint: .red
                )

                if prefs.inactivityTimeoutEnabled {
                    Divider().opacity(0.5)

                    HStack {
                        Text("Timeout duration")
                            .font(.callout)
                            .foregroundColor(LuminaText.muted)
                        Spacer()
                        
                        DurationPicker(
                            minutes: $prefs.inactivityTimeoutMinutes,
                            seconds: $prefs.inactivityTimeoutSeconds
                        )
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    Text("00:00 disables idle dimming. Slot timeouts take priority.")
                        .font(.caption2).foregroundStyle(LuminaText.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .animation(Motion.smooth, value: prefs.inactivityTimeoutEnabled)
        }
    }

    // MARK: - Sun Cycle Panel
    private var solarSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active window").font(.caption2).foregroundStyle(LuminaText.muted)
                    Text(sun.activeWindowLabel)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text("On from sunset to sunrise; off during daylight.")
                        .font(.caption2).foregroundStyle(LuminaText.soft)
                }
                Spacer(minLength: 4)
                Image(systemName: locationPillIcon)
                    .font(.title2).foregroundStyle(locationPillTint)
            }

            DisclosureGroup(isExpanded: $showLocationControls) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Button("Mac Location", systemImage: "location.fill") {
                            showManualLocationEditor = false
                            sun.requestMacLocation()
                        }
                        .help("Use macOS Location Services")
                        Button("IP Estimate", systemImage: "network") {
                            showManualLocationEditor = false
                            showApproximateLocationConsent = true
                        }
                        .help("Look up your public IP address with ipapi.co")
                        Button("Manual", systemImage: "pencil") {
                            sun.beginManualEntry()
                            manualLatitude = prefs.hasSavedLocation ? String(format: "%.1f", prefs.latitude) : ""
                            manualLongitude = prefs.hasSavedLocation ? String(format: "%.1f", prefs.longitude) : ""
                            showManualLocationEditor = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text("IP Estimate contacts ipapi.co only after confirmation. Mac Location uses Apple's Location Services.")
                        .font(.caption2).foregroundStyle(LuminaText.muted)
                    Link("IP provider privacy policy", destination: URL(string: "https://ipapi.co/privacy/")!)
                        .font(.caption2)

                    if showManualLocationEditor {
                        HStack(spacing: 10) {
                            CoordinateField(title: "Latitude", text: $manualLatitude)
                            CoordinateField(title: "Longitude", text: $manualLongitude)
                        }
                        Text("Latitude −90…90; longitude −180…180.")
                            .font(.caption2).foregroundStyle(LuminaText.muted)
                        Button("Save Manual Location") {
                            if let coordinate = manualCoordinate,
                               sun.useManualCoordinates(latitude: coordinate.latitude, longitude: coordinate.longitude) {
                                showManualLocationEditor = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualCoordinate == nil)
                    }

                    if sun.needsSettings, prefs.solarLocationSource == .precise {
                        Button("Open Location Settings") { sun.openLocationSettings() }
                    }
                    if prefs.hasSavedLocation {
                        Text("Saved region: \(String(format: "%.1f, %.1f", prefs.latitude, prefs.longitude)). Rounded to 0.1° and stored on this Mac.")
                            .font(.caption2).foregroundStyle(LuminaText.muted)
                        Button("Forget Saved Location", role: .destructive) {
                            sun.clearSavedLocation()
                            showManualLocationEditor = false
                        }
                        .font(.caption)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(sun.locationLabel).font(.caption.weight(.medium))
            }
            .tint(.indigo)

            if let lastError = sun.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(lastError)
                        .font(.caption2)
                        .foregroundColor(LuminaText.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sunrise.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading) {
                        Text("Sunrise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(LuminaText.muted)
                        Text(sun.sunriseLabel)
                            .font(.subheadline)
                            .bold()
                            .opacity(sun.isLocating ? 0.55 : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                HStack(spacing: 6) {
                    Image(systemName: "sunset.fill")
                        .foregroundColor(.indigo)
                    VStack(alignment: .leading) {
                        Text("Sunset")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(LuminaText.muted)
                        Text(sun.sunsetLabel)
                            .font(.subheadline)
                            .bold()
                            .opacity(sun.isLocating ? 0.55 : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.04),
                                Color.white.opacity(0.015)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("NIGHTTIME BRIGHTNESS")
                    .font(.caption2)
                    .fontWeight(.black)
                    .foregroundColor(LuminaText.muted)

                BrightnessRow(
                    title: "Brightness",
                    value: $prefs.solarNightBrightness,
                    tint: .indigo,
                    subtitle: prefs.solarAutoBrightness ? "Overridden by ambient sensor" : "Applied from sunset to sunrise",
                    onEditing: { controller.previewBrightness($0) }
                )
                .disabled(prefs.solarAutoBrightness)
                .opacity(prefs.solarAutoBrightness ? 0.45 : 1)

                ToggleRow(
                    systemImage: "rays",
                    title: "Auto-Brightness",
                    subtitle: "Auto brightness at night",
                    isOn: $prefs.solarAutoBrightness,
                    tint: .indigo
                )
            }
        }
    }

    // MARK: - Custom Slots Panel
    private var customSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.callout).foregroundStyle(.indigo).frame(width: 22)
                Text("Time slots").font(.callout.weight(.semibold))
                Spacer()
                if !prefs.customPeriods.isEmpty {
                    Text("\(prefs.customPeriods.count)/3")
                        .font(.caption2.weight(.bold)).foregroundStyle(LuminaText.muted)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }

            if !prefs.customPeriods.isEmpty || isAddingNew {
                VStack(spacing: 10) {
                    ForEach(prefs.customPeriods) { period in
                        if editingID == period.id, draft != nil {
                            periodEditor(isNew: false)
                                .transition(.scale(scale: 0.96).combined(with: .opacity))
                        } else {
                            periodRow(period)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }

                    if isAddingNew, draft != nil {
                        periodEditor(isNew: true)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if !isAddingNew && editingID == nil && prefs.customPeriods.count < 3 {
                Button(action: beginAdd) {
                    ZStack {
                        Circle()
                            .fill(Color.indigo.gradient)
                            .frame(width: 38, height: 38)
                            .shadow(color: .indigo.opacity(0.4), radius: 5, x: 0, y: 2)
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.85))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .help("Add a time slot")
                .accessibilityLabel("Add a time slot")
            }
        }
        .animation(Motion.smooth, value: prefs.customPeriods)
        .animation(Motion.smooth, value: editingID)
        .animation(Motion.smooth, value: isAddingNew)
    }

    // MARK: - Row Layout
    private func periodRow(_ period: BrightnessPeriod) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.indigo.opacity(0.18)).frame(width: 34, height: 34)
                Image(systemName: period.useAmbient ? "rays" : "moon.fill")
                    .font(.caption).foregroundStyle(Color.indigo.opacity(0.95))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(period.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(timeStr(period.startHour, period.startMinute))
                    Image(systemName: "arrow.right").font(.system(size: 8))
                    Text(timeStr(period.endHour, period.endMinute))
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(LuminaText.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text(period.useAmbient ? "Auto" : "\(Int((period.brightness * 100).rounded()))%")
                .font(.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.indigo.opacity(period.useAmbient ? 0.34 : 0.22))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7))
                )

            Button { beginEdit(period) } label: {
                Image(systemName: "pencil").font(.caption).foregroundStyle(LuminaText.muted)
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Edit \(period.name)")

            Button { delete(period) } label: {
                Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                    .frame(width: 26, height: 26)
                    .background(Color.red.opacity(0.1), in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Delete \(period.name)")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.055), lineWidth: 0.7)
                )
        )
    }

    // MARK: - Custom Period Editor View
    private func periodEditor(isNew: Bool) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(isNew ? "New slot" : "Edit slot")
                    .font(.caption.weight(.semibold)).foregroundStyle(LuminaText.muted)
                Spacer()
                TextField("Name", text: Binding(
                    get: { draft?.name ?? "" },
                    set: { draft?.name = $0 }
                ))
                .textFieldStyle(.plain)
                .accessibilityLabel("Time slot name")
                .multilineTextAlignment(.trailing)
                .font(.callout.weight(.medium))
                .frame(width: 150)
            }

            Divider().opacity(0.5)

            HStack(spacing: 6) {
                timeColumn(title: "Start",
                           hour: Binding(get: { draft?.startHour ?? 0 }, set: { draft?.startHour = $0 }),
                           minute: Binding(get: { draft?.startMinute ?? 0 }, set: { draft?.startMinute = $0 }))
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(LuminaText.faint)
                timeColumn(title: "End",
                           hour: Binding(get: { draft?.endHour ?? 0 }, set: { draft?.endHour = $0 }),
                           minute: Binding(get: { draft?.endMinute ?? 0 }, set: { draft?.endMinute = $0 }))
            }

            BrightnessRow(
                title: "Brightness",
                value: Binding(get: { draft?.brightness ?? 0 }, set: { draft?.brightness = $0 }),
                tint: .indigo,
                onEditing: { controller.previewBrightness($0) }
            )
            .disabled(draft?.useAmbient ?? false)
            .opacity((draft?.useAmbient ?? false) ? 0.45 : 1)

            ToggleRow(
                systemImage: "rays",
                title: "Auto-Brightness",
                subtitle: "Auto brightness in this slot",
                isOn: Binding(get: { draft?.useAmbient ?? false }, set: { draft?.useAmbient = $0 }),
                tint: .indigo
            )

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Idle Timeout")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("00:00 uses the global inactivity setting")
                        .font(.caption2)
                        .foregroundStyle(LuminaText.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                DurationPicker(
                    minutes: Binding(get: { draft?.timeoutMinutes ?? 0 }, set: { draft?.timeoutMinutes = $0 }),
                    seconds: Binding(get: { draft?.timeoutSeconds ?? 0 }, set: { draft?.timeoutSeconds = $0 })
                )
            }

            if overlapWarning {
                Label(editingLimitReached ? "You can add up to 3 slots" : (draft?.isValid == false ? "Use a name and different start/end times" : "This time range overlaps another slot"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 10) {
                Button("Cancel", action: cancelEdit)
                    .buttonStyle(PressableStyle())
                Spacer()
                Button(action: saveEdit) {
                    Text("Save")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 6)
                        .background(Color.indigo.gradient, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.indigo.opacity(0.4), lineWidth: 1)
        )
    }

    private func timeColumn(title: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(LuminaText.muted)
            HStack(spacing: 2) {
                NumberMenuPicker(title: "\(title) hour", selection: hour, range: 0...23, width: 54)
                Text(":").foregroundStyle(LuminaText.muted)
                NumberMenuPicker(title: "\(title) minute", selection: minute, range: 0...59, width: 54)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions
    private func beginAdd() {
        guard prefs.customPeriods.count < 3 else {
            withAnimation(Motion.snappy) { overlapWarning = true }
            return
        }
        let candidate = suggestedNewPeriod()
        draft = candidate
        overlapWarning = false
        withAnimation(Motion.smooth) {
            editingID = nil
            isAddingNew = true
        }
    }

    private func beginEdit(_ period: BrightnessPeriod) {
        draft = period
        overlapWarning = false
        withAnimation(Motion.smooth) {
            isAddingNew = false
            editingID = period.id
        }
    }

    private func saveEdit() {
        guard let d = draft else { return }
        let success: Bool = isAddingNew ? prefs.addPeriod(d) : prefs.updatePeriod(d)
        if success {
            withAnimation(Motion.smooth) {
                editingID = nil
                isAddingNew = false
                draft = nil
                overlapWarning = false
            }
        } else {
            withAnimation(Motion.snappy) { overlapWarning = true }
        }
    }

    private func cancelEdit() {
        withAnimation(Motion.smooth) {
            editingID = nil
            isAddingNew = false
            draft = nil
            overlapWarning = false
        }
    }

    private func delete(_ period: BrightnessPeriod) {
        withAnimation(Motion.smooth) { prefs.removePeriod(id: period.id) }
    }

    private var editingLimitReached: Bool {
        isAddingNew && prefs.customPeriods.count >= 3
    }

    private func suggestedNewPeriod() -> BrightnessPeriod {
        let candidates = [(9, 11), (12, 14), (15, 17), (8, 9), (13, 14), (16, 17)]
        for (s, e) in candidates {
            let p = BrightnessPeriod(name: "Period", startHour: s, startMinute: 0,
                                     endHour: e, endMinute: 0, brightness: 0.5,
                                     timeoutMinutes: 0, timeoutSeconds: 0)
            if prefs.overlappingPeriod(with: p) == nil { return p }
        }
        return BrightnessPeriod(name: "Period", startHour: 9, startMinute: 0,
                                endHour: 11, endMinute: 0, brightness: 0.5,
                                timeoutMinutes: 0, timeoutSeconds: 0)
    }

    private var unavailableView: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard.badge.exclamationmark")
                .font(.largeTitle).foregroundStyle(LuminaText.muted)
            Text("No keyboard backlight detected")
                .font(.callout.weight(.medium))
            Text("This Mac has no controllable keyboard backlight.")
                .font(.caption).foregroundStyle(LuminaText.muted)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }

    private var footer: some View {
        HStack {
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit", systemImage: "power")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.red.opacity(0.12), in: Capsule())
                    .foregroundStyle(.red)
            }
            .buttonStyle(PressableStyle())
            Spacer()
            
            HStack(spacing: 8) {
                // Tutorial Re-open Book Trigger
                Button(action: {
                    withAnimation(Motion.smooth) {
                        onboardingPage = 0
                        prefs.hasCompletedOnboarding = false
                    }
                }) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(LuminaText.muted)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(PressableStyle())
                .help("Reopen Setup Onboarding")
                .accessibilityLabel("Reopen setup")
                
                Text("v" + versionLabel).font(.caption2).foregroundStyle(LuminaText.faint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func timeStr(_ h: Int, _ m: Int) -> String { String(format: "%02d:%02d", h, m) }

    // MARK: - 6.2 ONBOARDING INTERACTIVE WIZARD
    private var onboardingPanel: some View {
        VStack(spacing: 16) {
            // Header Branding
            HStack(spacing: 8) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Lumina Setup")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(onboardingPage + 1) / 5")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(LuminaText.muted)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            Divider()

            ScrollView(.vertical) {
            ZStack {
                if onboardingPage == 0 {
                    onboardingWelcomeStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else if onboardingPage == 1 {
                    onboardingLocationStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else if onboardingPage == 2 {
                    onboardingStartupBrightnessStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else if onboardingPage == 3 {
                    onboardingHardwareStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    onboardingPowerStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            }
            .frame(height: min(270, availableContentHeight))
            .animation(Motion.smooth, value: onboardingPage)

            Divider()

            // Bottom Navigation Footer
            HStack {
                if onboardingPage > 0 {
                    Button("Back") {
                        withAnimation(Motion.smooth) { onboardingPage -= 1 }
                    }
                    .buttonStyle(PressableStyle())
                }
                
                Spacer()

                Button(action: nextOnboardingStep) {
                    Text(onboardingPage == 4 ? "Complete Setup" : "Next")
                        .fontWeight(.bold)
                        .padding(.horizontal, 18).padding(.vertical, 6)
                        .background(Color.indigo.gradient, in: Capsule())
                        .foregroundColor(.white)
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    private func nextOnboardingStep() {
        if onboardingPage < 4 {
            withAnimation(Motion.smooth) {
                onboardingPage += 1
            }
        } else {
            // Write completed state to Preferences/UserDefaults
            withAnimation(Motion.smooth) {
                prefs.hasCompletedOnboarding = true
                controller.startMonitoring() // Recalibrate with fresh defaults
            }
        }
    }

    // Onboarding Step 1: Welcome
    private var onboardingWelcomeStep: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
                .symbolRenderingMode(.hierarchical)
                .padding(.top, 10)

            Text("Welcome to Lumina")
                .font(.title3.weight(.bold))

            Text("Set your MacBook keyboard brightness, follow the sun, or create up to three daily time slots. Add an inactivity timeout to turn the backlight off while you are away.")
                .font(.caption)
                .foregroundColor(LuminaText.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }

    // Onboarding Step 2: Location Configuration
    private var onboardingLocationStep: some View {
        VStack(spacing: 10) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 38))
                .foregroundColor(.indigo)

            Text("Sun Cycle Calibration")
                .font(.callout.weight(.bold))

            Text("Solar calculations run on your Mac. Mac Location asks macOS for a location; coordinates are rounded and saved locally. You can skip this and enter a location later, or use Time Slots without a location.")
                .font(.caption2)
                .foregroundColor(LuminaText.muted)
                .multilineTextAlignment(.center)

            Button(action: {
                sun.requestMacLocation()
            }) {
                Label(sun.isLocating ? "Finding Mac Location…" : "Use Mac Location",
                      systemImage: "location.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(sun.isAuthorized ? .green : .white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(sun.isAuthorized ? Color.green.opacity(0.12) : Color.indigo, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 4)

            if let error = sun.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // Onboarding Step 3: Default Startup Brightness
    private var onboardingStartupBrightnessStep: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 38))
                .foregroundColor(.orange)
                .padding(.top, 10)

            Text("System Brightness")
                .font(.callout.weight(.bold))

            Text("Choose the brightness for System Control. Lumina remembers this level. Periodic mode uses your Sun Cycle or Time Slots settings instead.")
                .font(.caption2)
                .foregroundColor(LuminaText.muted)
                .multilineTextAlignment(.center)

            BrightnessRow(
                title: "Brightness",
                value: $prefs.manualBrightness,
                tint: .orange,
                onEditing: { controller.previewBrightness($0) }
            )
            .padding(.top, 8)
        }
    }

    // Onboarding Step 4: Hardware Link Verification
    private var onboardingHardwareStep: some View {
        VStack(spacing: 12) {
            Image(systemName: controller.keyboardAvailable ? "keyboard.fill" : "keyboard.badge.exclamationmark")
                .font(.system(size: 38))
                .foregroundColor(controller.keyboardAvailable ? .green : .orange)

            Text("Private Hardware Interface")
                .font(.callout.weight(.bold))

            Text("Lumina uses the private CoreBrightness framework to control supported keyboards. Availability can change with macOS updates. The app runs without App Sandbox and needs no administrator access.")
                .font(.caption2)
                .foregroundColor(LuminaText.muted)
                .multilineTextAlignment(.center)

            // Diagnostic Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(controller.keyboardAvailable ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(controller.keyboardAvailable ? "Hardware Detected Successfully" : "No supported backlight detected")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(controller.keyboardAvailable ? .green : .orange)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill((controller.keyboardAvailable ? Color.green : Color.orange).opacity(0.1)))
        }
    }

    // Onboarding Step 5: Power Saving Tutorial
    private var onboardingPowerStep: some View {
        VStack(spacing: 10) {
            Image(systemName: "hourglass.badge.plus")
                .font(.system(size: 38))
                .foregroundColor(.red)

            Text("Inactivity Power Saver")
                .font(.callout.weight(.bold))

            Text("Click the minutes or seconds menu to choose a timeout. Mouse, trackpad, and keyboard use the same controls. A global timeout of 00:00 disables idle dimming; a slot timeout of 00:00 uses the global setting.")
                .font(.caption2)
                .foregroundColor(LuminaText.muted)
                .multilineTextAlignment(.center)

            // Mini Interactive Demo
            HStack(spacing: 8) {
                Text("Timeout:")
                    .font(.caption2)
                    .foregroundColor(LuminaText.muted)
                DurationPicker(
                    minutes: $demoMinutes,
                    seconds: $demoSeconds
                )
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        }
    }
}
