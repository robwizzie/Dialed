//
//  Weather.swift
//  Dialed
//
//  The day's weather for the Home banner, and what to wear for it. A
//  forecast is now + the hours ahead (from Open-Meteo, see
//  WeatherService); the outfit reads how it will *feel* across the hours
//  you're likely out (7 AM–10 PM, from now on), so a cold morning and a
//  warm afternoon become "shorts, bring a layer". Pure Foundation, tested.
//

import Foundation

enum Weather {

    struct Hour: Equatable, Codable {
        var time: Date
        var temp: Double
        var feels: Double
        var precipChance: Int
        var code: Int
        var wind: Double
        var uv: Double
    }

    struct Day: Equatable, Codable {
        var date: Date
        var high: Double
        var low: Double
        var code: Int
        var precipChance: Int
    }

    struct Forecast: Equatable, Codable {
        var fetchedAt: Date
        /// °F when true, °C otherwise; wind in mph / km/h to match.
        var fahrenheit: Bool
        var nowTemp: Double?
        var nowFeels: Double?
        var nowCode: Int?
        var nowIsDay: Bool
        var hours: [Hour]
        var days: [Day]

        func day(_ date: Date, calendar: Calendar = .current) -> Day? {
            days.first { calendar.isDate($0.date, inSameDayAs: date) }
        }

        func hours(on date: Date, calendar: Calendar = .current) -> [Hour] {
            hours.filter { calendar.isDate($0.time, inSameDayAs: date) }
        }
    }

    // MARK: - Conditions (WMO weather codes)

    struct Condition: Equatable {
        let text: String
        let symbol: String
        let wet: Bool
        let snowy: Bool
    }

    static func condition(_ code: Int, isDay: Bool = true) -> Condition {
        switch code {
        case 0:        return Condition(text: "Clear", symbol: isDay ? "sun.max.fill" : "moon.stars.fill", wet: false, snowy: false)
        case 1:        return Condition(text: "Mostly clear", symbol: isDay ? "sun.max.fill" : "moon.fill", wet: false, snowy: false)
        case 2:        return Condition(text: "Partly cloudy", symbol: isDay ? "cloud.sun.fill" : "cloud.moon.fill", wet: false, snowy: false)
        case 3:        return Condition(text: "Cloudy", symbol: "cloud.fill", wet: false, snowy: false)
        case 45, 48:   return Condition(text: "Foggy", symbol: "cloud.fog.fill", wet: false, snowy: false)
        case 51...57:  return Condition(text: "Drizzle", symbol: "cloud.drizzle.fill", wet: true, snowy: false)
        case 61...67:  return Condition(text: code >= 65 ? "Heavy rain" : "Rain", symbol: code >= 65 ? "cloud.heavyrain.fill" : "cloud.rain.fill", wet: true, snowy: false)
        case 71...77:  return Condition(text: "Snow", symbol: "cloud.snow.fill", wet: true, snowy: true)
        case 80...82:  return Condition(text: "Showers", symbol: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill", wet: true, snowy: false)
        case 85, 86:   return Condition(text: "Snow showers", symbol: "cloud.snow.fill", wet: true, snowy: true)
        case 95...99:  return Condition(text: "Thunderstorms", symbol: "cloud.bolt.rain.fill", wet: true, snowy: false)
        default:       return Condition(text: "—", symbol: "cloud.fill", wet: false, snowy: false)
        }
    }

    // MARK: - What to wear

    struct Outfit: Equatable {
        /// "T-shirt & shorts".
        var main: String
        /// "Light jacket after 7 PM · umbrella".
        var extras: [String]
        var emoji: String

        var line: String { ([main] + extras).joined(separator: " · ") }
    }

    /// What to wear across `hours` (the ones you'll be out in). Feels-like
    /// temps in °F or °C per `fahrenheit`.
    static func outfit(for hours: [Hour], fahrenheit: Bool, calendar: Calendar = .current) -> Outfit? {
        guard !hours.isEmpty else { return nil }
        // Rules are written in °F.
        func f(_ v: Double) -> Double { fahrenheit ? v : v * 9 / 5 + 32 }
        let feels = hours.map { f($0.feels) }
        guard let hi = feels.max(), let lo = feels.min() else { return nil }

        let top: String, emoji: String
        switch hi {
        case 75...:   top = "T-shirt";            emoji = "👕"
        case 66..<75: top = "Short sleeve";       emoji = "👕"
        case 57..<66: top = "Long sleeve";        emoji = "👔"
        case 47..<57: top = "Sweatshirt";         emoji = "🧶"
        case 36..<47: top = "Jacket";             emoji = "🧥"
        default:      top = "Warm coat";          emoji = "🧥"
        }
        let bottom = hi >= 70 ? "shorts" : "pants"
        var extras: [String] = []

        // A layer for the cool end of the day, said with when it's needed.
        if hi - lo >= 12, lo < 60, hi >= 47 {
            let layer = lo < 45 ? "Jacket" : lo < 52 ? "Sweatshirt" : "Light layer"
            let peak = hours.firstIndex { f($0.feels) == hi } ?? 0
            let coldAfter = hours[peak...].first { f($0.feels) <= lo + 3 }
            let coldBefore = hours[..<peak].first { f($0.feels) <= lo + 3 }
            if let late = coldAfter, coldBefore == nil || peak == 0 {
                extras.append("\(layer) after \(hourText(late.time, calendar: calendar))")
            } else if coldBefore != nil {
                extras.append("\(layer) for the morning")
            } else {
                extras.append(layer.lowercased() == "light layer" ? "Light layer" : layer)
            }
        }
        if lo < 32 { extras.append("Hat & gloves") }

        let rain = hours.map(\.precipChance).max() ?? 0
        let snowy = hours.contains { condition($0.code).snowy && $0.precipChance >= 40 }
        if snowy {
            extras.append("Boots")
        } else if rain >= 50 {
            let start = hours.first { $0.precipChance >= 50 }
            extras.append("Umbrella" + (start.map { " from \(hourText($0.time, calendar: calendar))" } ?? ""))
        } else if rain >= 30 {
            extras.append("Maybe a rain shell")
        }
        let wind = hours.map(\.wind).max() ?? 0
        if (fahrenheit ? wind : wind / 1.609) >= 20, !extras.contains(where: { $0.contains("Jacket") }) {
            extras.append("Windbreaker")
        }
        if (hours.map(\.uv).max() ?? 0) >= 7 { extras.append("Sunscreen") }

        return Outfit(main: "\(top) & \(bottom)", extras: Array(extras.prefix(2)), emoji: emoji)
    }

    /// The hours worth dressing for: from now (or 7 AM) to 10 PM that day.
    static func outHours(_ forecast: Forecast, on day: Date, now: Date = Date(), calendar: Calendar = .current) -> [Hour] {
        let start = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day) ?? day
        let end = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: day) ?? day
        let from = max(start, calendar.isDate(now, inSameDayAs: day) ? now.addingTimeInterval(-3600) : start)
        return forecast.hours.filter { $0.time >= from && $0.time <= end }
    }

    /// One short line about what's coming: rain, a big swing, or the peak.
    static func outlook(_ hours: [Hour], fahrenheit: Bool, calendar: Calendar = .current) -> String? {
        guard let first = hours.first else { return nil }
        if let wet = hours.first(where: { $0.precipChance >= 50 && condition($0.code).wet }) {
            let c = condition(wet.code)
            return wet.time <= first.time ? "\(c.text) now" : "\(c.text) likely from \(hourText(wet.time, calendar: calendar))"
        }
        guard let peak = hours.max(by: { $0.temp < $1.temp }) else { return nil }
        if peak.temp - first.temp >= 6 {
            return "Up to \(Int(peak.temp.rounded()))° by \(hourText(peak.time, calendar: calendar))"
        }
        if let low = hours.min(by: { $0.temp < $1.temp }), first.temp - low.temp >= 6 {
            return "Down to \(Int(low.temp.rounded()))° by \(hourText(low.time, calendar: calendar))"
        }
        return "Steady all day"
    }

    static func hourText(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("j")
        return f.string(from: date).replacingOccurrences(of: ":00", with: "")
    }

    // MARK: - Open-Meteo

    /// Decodes an Open-Meteo forecast response. Times arrive as local wall
    /// clock strings plus the location's UTC offset.
    static func decode(_ data: Data, fahrenheit: Bool, now: Date = Date()) throws -> Forecast {
        struct Response: Decodable {
            struct Current: Decodable {
                var temperature_2m: Double?
                var apparent_temperature: Double?
                var weather_code: Int?
                var is_day: Int?
            }
            struct Hourly: Decodable {
                var time: [String]
                var temperature_2m: [Double?]
                var apparent_temperature: [Double?]
                var precipitation_probability: [Int?]?
                var weather_code: [Int?]
                var wind_speed_10m: [Double?]?
                var uv_index: [Double?]?
            }
            struct Daily: Decodable {
                var time: [String]
                var temperature_2m_max: [Double?]
                var temperature_2m_min: [Double?]
                var weather_code: [Int?]
                var precipitation_probability_max: [Int?]?
            }
            var utc_offset_seconds: Int
            var current: Current?
            var hourly: Hourly?
            var daily: Daily?
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        let zone = TimeZone(secondsFromGMT: r.utc_offset_seconds) ?? .current
        let hourFormat = DateFormatter()
        hourFormat.locale = Locale(identifier: "en_US_POSIX")
        hourFormat.timeZone = zone
        hourFormat.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.timeZone = .current
        dayFormat.dateFormat = "yyyy-MM-dd"

        var hours: [Hour] = []
        if let h = r.hourly {
            for i in h.time.indices {
                guard let time = hourFormat.date(from: h.time[i]),
                      let temp = h.temperature_2m[safe: i] ?? nil else { continue }
                hours.append(Hour(time: time, temp: temp,
                                  feels: (h.apparent_temperature[safe: i] ?? nil) ?? temp,
                                  precipChance: (h.precipitation_probability?[safe: i] ?? nil) ?? 0,
                                  code: (h.weather_code[safe: i] ?? nil) ?? 0,
                                  wind: (h.wind_speed_10m?[safe: i] ?? nil) ?? 0,
                                  uv: (h.uv_index?[safe: i] ?? nil) ?? 0))
            }
        }
        var days: [Day] = []
        if let d = r.daily {
            for i in d.time.indices {
                guard let date = dayFormat.date(from: d.time[i]),
                      let hi = d.temperature_2m_max[safe: i] ?? nil,
                      let lo = d.temperature_2m_min[safe: i] ?? nil else { continue }
                days.append(Day(date: date, high: hi, low: lo, code: (d.weather_code[safe: i] ?? nil) ?? 0,
                                precipChance: (d.precipitation_probability_max?[safe: i] ?? nil) ?? 0))
            }
        }
        return Forecast(fetchedAt: now, fahrenheit: fahrenheit,
                        nowTemp: r.current?.temperature_2m, nowFeels: r.current?.apparent_temperature,
                        nowCode: r.current?.weather_code, nowIsDay: (r.current?.is_day ?? 1) == 1,
                        hours: hours, days: days)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
