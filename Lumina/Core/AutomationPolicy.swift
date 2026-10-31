import Foundation

struct AutomationSettings {
    var periodic = false
    var tab = 0
    var manualBrightness = 0.0
    var manualAmbient = false
    var nightBrightness = 0.5
    var nightAmbient = false
    var inactivityEnabled = false
    var inactivityMinutes = 0
    var inactivitySeconds = 30
    var periods: [BrightnessPeriod] = []
}

struct BacklightDecision: Equatable {
    var brightness: Double
    var ambient = false
    var label: String
    var periodName: String?
    var night = false
    var statusOverride: String?

    var status: String {
        if let statusOverride { return statusOverride }
        let detail = ambient ? "Auto" : (brightness == 0 ? "Off" : "\(Int((brightness * 100).rounded()))%")
        return "\(label) • \(detail)"
    }
}

enum AutomationPolicy {
    static func clampBrightness(_ value: Double, fallback: Double = 0) -> Double {
        value.isFinite ? min(max(value, 0), 1) : fallback
    }

    static func decision(settings: AutomationSettings, minute: Int, isNight: Bool?) -> BacklightDecision {
        guard settings.periodic else {
            return BacklightDecision(brightness: clampBrightness(settings.manualBrightness),
                                     ambient: settings.manualAmbient, label: "System")
        }
        if settings.tab == 0 {
            guard let isNight else {
                return BacklightDecision(brightness: 0, label: "Sun Cycle", statusOverride: "Choose a location")
            }
            return BacklightDecision(brightness: isNight ? clampBrightness(settings.nightBrightness) : 0,
                                     ambient: isNight && settings.nightAmbient,
                                     label: isNight ? "Night" : "Day",
                                     periodName: isNight ? "Night" : nil, night: isNight)
        }
        if let period = matchingPeriod(settings: settings, minute: minute) {
            return BacklightDecision(brightness: clampBrightness(period.brightness), ambient: period.useAmbient,
                                     label: period.name, periodName: period.name, night: isNight ?? false)
        }
        return BacklightDecision(brightness: 0, label: "Off", statusOverride: "Off • Outside schedule")
    }

    static func idleTimeout(settings: AutomationSettings, minute: Int) -> TimeInterval? {
        if let period = matchingPeriod(settings: settings, minute: minute),
           let timeout = duration(minutes: period.timeoutMinutes, seconds: period.timeoutSeconds) {
            return timeout
        }
        return settings.inactivityEnabled
            ? duration(minutes: settings.inactivityMinutes, seconds: settings.inactivitySeconds) : nil
    }

    static func duration(minutes: Int, seconds: Int) -> TimeInterval? {
        guard (0...59).contains(minutes), (0...59).contains(seconds) else { return nil }
        let total = minutes * 60 + seconds
        return total > 0 ? TimeInterval(total) : nil
    }

    private static func matchingPeriod(settings: AutomationSettings, minute: Int) -> BrightnessPeriod? {
        guard settings.periodic, settings.tab == 1 else { return nil }
        return settings.periods.first { $0.isValid && $0.contains(minuteOfDay: minute) }
    }
}

struct InactivityState {
    private(set) var isOff = false

    mutating func update(idleSeconds: TimeInterval, timeout: TimeInterval?, withinGracePeriod: Bool) {
        guard idleSeconds.isFinite, idleSeconds >= 0 else { return }
        if let timeout, idleSeconds >= timeout, !withinGracePeriod {
            isOff = true
        } else if isOff, idleSeconds < 1, !withinGracePeriod {
            // Removing a timeout or ending a slot must not wake an unattended keyboard.
            isOff = false
        }
    }
}
