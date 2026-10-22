//
//  WeatherService.swift
//  Dialed
//
//  Today's weather (and a past day's, for Home's recap) from Open-Meteo:
//  free, no account or key. Off until you turn it on from the banner; then
//  it asks for your location once, keeps it only to ~1 km (two decimals)
//  and re-reads it every few hours. The last forecast is saved so Home
//  shows weather straight away on launch while a fresh one loads.
//

import Foundation
import CoreLocation

@MainActor
final class WeatherService: NSObject, ObservableObject {
    static let shared = WeatherService()

    enum Status: Equatable {
        /// Not turned on yet; the banner offers it.
        case off
        /// Turned on, but location access was declined.
        case denied
        case loading
        case ready
        case failed
    }

    @Published private(set) var forecast: Weather.Forecast?
    @Published private(set) var status: Status = .off

    private let manager = CLLocationManager()
    private var locationWaiters: [CheckedContinuation<CLLocation?, Never>] = []
    private var authWaiters: [CheckedContinuation<Void, Never>] = []
    private var pastDays: [String: Weather.Forecast] = [:]
    private var running: Task<Void, Never>?

    private static let enabledKey = "weather.enabled"
    private static let coordKey = "weather.coord"
    private static let coordAtKey = "weather.coordAt"
    private static let forecastKey = "weather.forecast.v1"
    private static let freshFor: TimeInterval = 30 * 60
    private static let locationFreshFor: TimeInterval = 6 * 3600

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }
    private var fahrenheit: Bool { Locale.current.measurementSystem == .us }

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if let data = UserDefaults.standard.data(forKey: Self.forecastKey),
           let saved = try? JSONDecoder().decode(Weather.Forecast.self, from: data),
           Date().timeIntervalSince(saved.fetchedAt) < 3 * 3600 {
            forecast = saved
        }
        status = isEnabled ? (forecast == nil ? .loading : .ready) : .off
    }

    // MARK: - Turning it on

    /// From the banner's "Turn on": asks for location, then loads.
    func enable() async {
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        status = .loading
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { c in
                authWaiters.append(c)
                manager.requestWhenInUseAuthorization()
            }
        }
        await refresh(force: true)
    }

    // MARK: - Today

    /// Loads today's forecast unless a fresh one is on hand. Joins a load
    /// already running.
    func refresh(force: Bool = false) async {
        guard isEnabled else { status = .off; return }
        if !force, let f = forecast, Date().timeIntervalSince(f.fetchedAt) < Self.freshFor { status = .ready; return }
        if let running { await running.value; return }
        let task = Task { await self.load() }
        running = task
        await task.value
        running = nil
    }

    private func load() async {
        guard let coord = await coordinate() else {
            status = isDenied ? .denied : (forecast == nil ? .failed : .ready)
            return
        }
        if forecast == nil { status = .loading }
        do {
            let f = try await fetch(coord, query: [
                URLQueryItem(name: "forecast_days", value: "2"),
                URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day")
            ])
            forecast = f
            status = .ready
            if let data = try? JSONEncoder().encode(f) { UserDefaults.standard.set(data, forKey: Self.forecastKey) }
        } catch {
            status = forecast == nil ? .failed : .ready
        }
    }

    // MARK: - A past day

    /// That day's hours and high/low, cached for the session. nil when
    /// weather is off or it couldn't load.
    func forecast(for day: Date) async -> Weather.Forecast? {
        guard isEnabled else { return nil }
        let key = DayLoadKit.key(day)
        if let cached = pastDays[key] { return cached }
        guard let coord = await coordinate() else { return nil }
        let back = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: day),
                                                   to: Calendar.current.startOfDay(for: Date())).day ?? 0
        // The forecast API keeps ~3 months; older days come from the archive.
        let host = back <= 90 ? "api.open-meteo.com/v1/forecast" : "archive-api.open-meteo.com/v1/archive"
        let f = try? await fetch(coord, host: host, query: [
            URLQueryItem(name: "start_date", value: key),
            URLQueryItem(name: "end_date", value: key)
        ])
        if let f { pastDays[key] = f }
        return f
    }

    // MARK: - Fetching

    private func fetch(_ coord: CLLocationCoordinate2D, host: String = "api.open-meteo.com/v1/forecast",
                       query: [URLQueryItem]) async throws -> Weather.Forecast {
        var c = URLComponents(string: "https://\(host)")!
        let f = fahrenheit
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", coord.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", coord.longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,apparent_temperature,precipitation_probability,weather_code,wind_speed_10m,uv_index"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max"),
            URLQueryItem(name: "temperature_unit", value: f ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: f ? "mph" : "kmh"),
            URLQueryItem(name: "timezone", value: "auto")
        ] + query
        var request = URLRequest(url: c.url!)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Weather.decode(data, fahrenheit: f)
    }

    // MARK: - Location

    private var isDenied: Bool {
        [.denied, .restricted].contains(manager.authorizationStatus)
    }

    /// A recent coordinate (kept to two decimals), or a fresh fix.
    private func coordinate() async -> CLLocationCoordinate2D? {
        let d = UserDefaults.standard
        if let saved = d.array(forKey: Self.coordKey) as? [Double], saved.count == 2,
           let at = d.object(forKey: Self.coordAtKey) as? Date,
           Date().timeIntervalSince(at) < Self.locationFreshFor {
            return CLLocationCoordinate2D(latitude: saved[0], longitude: saved[1])
        }
        guard !isDenied, manager.authorizationStatus != .notDetermined else {
            // Fall back to the last place we knew, however old.
            if let saved = d.array(forKey: Self.coordKey) as? [Double], saved.count == 2 {
                return CLLocationCoordinate2D(latitude: saved[0], longitude: saved[1])
            }
            return nil
        }
        let location = await withCheckedContinuation { (c: CheckedContinuation<CLLocation?, Never>) in
            locationWaiters.append(c)
            if locationWaiters.count == 1 { manager.requestLocation() }
        }
        guard let location else {
            if let saved = d.array(forKey: Self.coordKey) as? [Double], saved.count == 2 {
                return CLLocationCoordinate2D(latitude: saved[0], longitude: saved[1])
            }
            return nil
        }
        let lat = (location.coordinate.latitude * 100).rounded() / 100
        let lon = (location.coordinate.longitude * 100).rounded() / 100
        d.set([lat, lon], forKey: Self.coordKey)
        d.set(Date(), forKey: Self.coordAtKey)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func finishLocation(_ location: CLLocation?) {
        let waiters = locationWaiters
        locationWaiters = []
        waiters.forEach { $0.resume(returning: location) }
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finishLocation(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishLocation(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard manager.authorizationStatus != .notDetermined else { return }
            let waiters = self.authWaiters
            self.authWaiters = []
            waiters.forEach { $0.resume() }
        }
    }
}
