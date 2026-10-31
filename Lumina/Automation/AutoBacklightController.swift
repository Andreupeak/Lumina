import AppKit
import Combine

@MainActor
final class AutoBacklightController: ObservableObject {
    static let shared = AutoBacklightController()

    private let keyboard = KeyboardBacklightManager.shared
    private let sun = SunScheduleManager.shared
    private let prefs = Preferences.shared
    private var timer: Timer?
    private var previewReset: DispatchWorkItem?
    private var previewUntil: Date?
    private var cancellables = Set<AnyCancellable>()
    private var inactivity = InactivityState()
    private var launchTime = Date()
    private var lastAppliedDecision: BacklightDecision?
    private var originalBrightness: Float?
    private var originalAmbient: Bool?
    private var didCaptureHardware = false

    @Published private(set) var currentStatus = "Starting…"
    @Published private(set) var isNightMode = false
    @Published private(set) var keyboardAvailable = false
    @Published private(set) var activePeriodName: String?

    private init() {
        prefs.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateAndApply() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemClockDidChange))
            .sink { [weak self] _ in
                self?.sun.refreshSolarTimesIfNeeded(force: true)
                self?.lastAppliedDecision = nil
                self?.evaluateAndApply()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.suspendMonitoring() }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.startMonitoring() }
            .store(in: &cancellables)
    }

    func startMonitoring() {
        keyboardAvailable = AppRuntime.isUITesting || keyboard.load()
        guard keyboardAvailable else {
            currentStatus = "No keyboard backlight"
            return
        }
        if !didCaptureHardware, !AppRuntime.isUITesting {
            originalBrightness = keyboard.currentBrightness
            originalAmbient = keyboard.isAutoBrightnessEnabled
            didCaptureHardware = true
            launchTime = Date()
        }
        lastAppliedDecision = nil
        timer?.invalidate()
        // Two checks per second keep idle wake-up responsive, with 80% fewer polls
        // than the former 100 ms loop. Never install event taps or read key content.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.evaluateAndApply() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sun.refreshSolarTimesIfNeeded(force: true)
        evaluateAndApply()
    }

    private func suspendMonitoring() {
        timer?.invalidate()
        timer = nil
        previewReset?.cancel()
        previewReset = nil
        previewUntil = nil
        lastAppliedDecision = nil
    }

    func stopMonitoring() {
        suspendMonitoring()
        sun.cancelPendingRequests()
        // Restore the state captured before Lumina took control, on a normal quit.
        if let originalBrightness {
            keyboard.setAutoBrightnessEnabled(false)
            keyboard.setBrightness(originalBrightness)
        }
        if let originalAmbient { keyboard.setAutoBrightnessEnabled(originalAmbient) }
    }

    func evaluateAndApply() {
        guard keyboardAvailable else { return }
        sun.refreshSolarTimesIfNeeded()
        let now = Date()
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let settings = prefs.automationSettings
        let timeout = AutomationPolicy.idleTimeout(settings: settings, minute: minute)
        if timeout != nil || inactivity.isOff {
            // kCGAnyInputEventType is documented as ~0; no event contents are inspected.
            let idle = AppRuntime.isUITesting ? 0
                : CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .init(rawValue: ~0)!)
            inactivity.update(idleSeconds: idle, timeout: timeout,
                              withinGracePeriod: now.timeIntervalSince(launchTime) < 10)
        }
        if let previewUntil, previewUntil > now, !inactivity.isOff { return }
        var decision = AutomationPolicy.decision(settings: settings, minute: minute, isNight: sun.isNighttime)
        if inactivity.isOff {
            let intendedStatus = decision.status
            decision.brightness = 0
            decision.ambient = false
            decision.statusOverride = "Idle Timeout • " + intendedStatus
        }
        apply(decision)
    }

    func previewBrightness(_ value: Double) {
        guard keyboardAvailable else { return }
        let brightness = AutomationPolicy.clampBrightness(value)
        lastAppliedDecision = nil
        previewUntil = Date().addingTimeInterval(3)
        previewReset?.cancel()
        let disabledAmbient = AppRuntime.isUITesting || keyboard.setAutoBrightnessEnabled(false)
        let appliedBrightness = AppRuntime.isUITesting || keyboard.setBrightness(Float(brightness))
        currentStatus = disabledAmbient && appliedBrightness
            ? BacklightDecision(brightness: brightness, label: "Preview").status : "Keyboard control failed"
        let reset = DispatchWorkItem { [weak self] in
            self?.previewUntil = nil
            self?.evaluateAndApply()
        }
        previewReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: reset)
    }

    private func apply(_ decision: BacklightDecision) {
        if decision != lastAppliedDecision, !AppRuntime.isUITesting {
            let disabledAmbient = keyboard.setAutoBrightnessEnabled(false)
            // Seed visible brightness before returning control to the ambient sensor.
            let seed = decision.ambient ? max(decision.brightness, 0.08) : decision.brightness
            let appliedBrightness = keyboard.setBrightness(Float(seed))
            let appliedAmbient = decision.ambient ? keyboard.setAutoBrightnessEnabled(true) : true
            guard disabledAmbient && appliedBrightness && appliedAmbient else {
                if currentStatus != "Keyboard control failed" { currentStatus = "Keyboard control failed" }
                return
            }
            lastAppliedDecision = decision
        }
        if activePeriodName != decision.periodName { activePeriodName = decision.periodName }
        if isNightMode != decision.night { isNightMode = decision.night }
        if currentStatus != decision.status { currentStatus = decision.status }
    }
}
