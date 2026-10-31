import Foundation

struct BrightnessPeriod: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var brightness: Double
    var useAmbient: Bool = false
    var timeoutMinutes: Int = 0
    var timeoutSeconds: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, name, startHour, startMinute, endHour, endMinute, brightness, useAmbient, timeoutMinutes, timeoutSeconds
    }

    init(
        id: UUID = UUID(),
        name: String,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        brightness: Double,
        useAmbient: Bool = false,
        timeoutMinutes: Int = 0,
        timeoutSeconds: Int = 0
    ) {
        self.id = id
        self.name = name
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.brightness = brightness
        self.useAmbient = useAmbient
        self.timeoutMinutes = timeoutMinutes
        self.timeoutSeconds = timeoutSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        startHour = try container.decode(Int.self, forKey: .startHour)
        startMinute = try container.decode(Int.self, forKey: .startMinute)
        endHour = try container.decode(Int.self, forKey: .endHour)
        endMinute = try container.decode(Int.self, forKey: .endMinute)
        brightness = try container.decode(Double.self, forKey: .brightness)
        useAmbient = try container.decodeIfPresent(Bool.self, forKey: .useAmbient) ?? false
        timeoutMinutes = try container.decodeIfPresent(Int.self, forKey: .timeoutMinutes) ?? 0
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 0
    }

    static func == (lhs: BrightnessPeriod, rhs: BrightnessPeriod) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.startHour == rhs.startHour &&
        lhs.startMinute == rhs.startMinute &&
        lhs.endHour == rhs.endHour &&
        lhs.endMinute == rhs.endMinute &&
        lhs.brightness == rhs.brightness &&
        lhs.useAmbient == rhs.useAmbient &&
        lhs.timeoutMinutes == rhs.timeoutMinutes &&
        lhs.timeoutSeconds == rhs.timeoutSeconds
    }

    var hasValidTimes: Bool {
        (0...23).contains(startHour) && (0...59).contains(startMinute) &&
        (0...23).contains(endHour) && (0...59).contains(endMinute)
    }

    var isValid: Bool {
        hasValidTimes && startMinutes != endMinutes &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 &&
        brightness.isFinite && (0...1).contains(brightness) &&
        (0...59).contains(timeoutMinutes) && (0...59).contains(timeoutSeconds)
    }

    var startMinutes: Int { hasValidTimes ? startHour * 60 + startMinute : -1 }
    var endMinutes: Int { hasValidTimes ? endHour * 60 + endMinute : -1 }

    var intervals: [(Int, Int)] {
        guard hasValidTimes else { return [] }
        let s = startMinutes
        let e = endMinutes
        if s == e { return [] }
        if s < e { return [(s, e)] }
        return [(s, 1440), (0, e)]
    }

    func contains(minuteOfDay m: Int) -> Bool {
        guard (0..<1440).contains(m) else { return false }
        return intervals.contains { m >= $0.0 && m < $0.1 }
    }

    func overlaps(_ other: BrightnessPeriod) -> Bool {
        for a in intervals {
            for b in other.intervals where a.0 < b.1 && b.0 < a.1 {
                return true
            }
        }
        return false
    }
}

enum SolarLocationSource: String {
    case precise
    case approximate
    case manual
}
