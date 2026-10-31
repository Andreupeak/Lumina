import Foundation

struct SolarEvents: Equatable {
    enum Condition: Equatable { case normal, polarDay, polarNight }
    let condition: Condition
    let sunrise: Date?
    let sunset: Date?

    func isNight(at date: Date) -> Bool {
        switch condition {
        case .polarDay: return false
        case .polarNight: return true
        case .normal:
            guard let sunrise, let sunset else { return false }
            let elapsed = date.timeIntervalSince(sunrise).truncatingRemainder(dividingBy: 86_400)
            let sinceSunrise = elapsed < 0 ? elapsed + 86_400 : elapsed
            return sinceSunrise >= sunset.timeIntervalSince(sunrise)
        }
    }
}

enum SolarCalculator {
    /// NOAA's general solar equations, evaluated for the requested local calendar day.
    /// https://gml.noaa.gov/grad/solcalc/solareqns.PDF
    /// Approximate civil sunrise/sunset, with a 90.833° zenith for refraction.
    static func calculateSunriseSunset(latitude: Double, longitude: Double,
                                      date: Date = Date(), timeZone: TimeZone = .current) -> SolarEvents? {
        guard LocationCoordinate(latitude: latitude, longitude: longitude) != nil else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let localDay = calendar.dateComponents([.year, .month, .day], from: date)
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date),
              let daysInYear = calendar.range(of: .day, in: .year, for: date)?.count else { return nil }

        let angle = 2 * Double.pi / Double(daysInYear) * Double(dayOfYear - 1)
        let equationOfTime = 229.18 * (0.000075 + 0.001868 * cos(angle) - 0.032077 * sin(angle)
                                      - 0.014615 * cos(2 * angle) - 0.040849 * sin(2 * angle))
        let declination = 0.006918 - 0.399912 * cos(angle) + 0.070257 * sin(angle)
            - 0.006758 * cos(2 * angle) + 0.000907 * sin(2 * angle)
            - 0.002697 * cos(3 * angle) + 0.00148 * sin(3 * angle)
        let latitudeRadians = latitude * .pi / 180
        let cosineHourAngle = (cos(90.833 * .pi / 180) - sin(latitudeRadians) * sin(declination))
            / (cos(latitudeRadians) * cos(declination))

        if cosineHourAngle > 1 { return SolarEvents(condition: .polarNight, sunrise: nil, sunset: nil) }
        if cosineHourAngle < -1 { return SolarEvents(condition: .polarDay, sunrise: nil, sunset: nil) }
        let hourAngle = acos(min(max(cosineHourAngle, -1), 1)) * 180 / .pi
        let solarNoon = 720 - 4 * longitude - equationOfTime

        // Construct absolute instants from UTC midnight, preserving negative/next-day
        // UTC times. Select the solar day whose noon belongs to the user's local day.
        // This handles DST and locations on the other side of the date line.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let midnightUTC = utc.date(from: localDay) else { return nil }
        var noon = midnightUTC.addingTimeInterval(solarNoon * 60)
        let localStart = calendar.startOfDay(for: date)
        guard let localEnd = calendar.date(byAdding: .day, value: 1, to: localStart) else { return nil }
        while noon < localStart { noon = noon.addingTimeInterval(86_400) }
        while noon >= localEnd { noon = noon.addingTimeInterval(-86_400) }
        return SolarEvents(condition: .normal,
                           sunrise: noon.addingTimeInterval(-hourAngle * 4 * 60),
                           sunset: noon.addingTimeInterval(hourAngle * 4 * 60))
    }
}
