//
//  NearbyPlaces.swift
//  Dialed
//
//  "Where am I eating?" One precise location fix, then Apple Maps' points
//  of interest within a few hundred meters: restaurants, cafés, bakeries,
//  bars, breweries and wineries, closest first. Runs on demand only; the
//  location isn't saved and nothing leaves Apple's services.
//

import Foundation
import CoreLocation
import MapKit

@MainActor
final class NearbyPlaces: NSObject, ObservableObject {

    struct Place: Identifiable, Equatable {
        enum Kind: Equatable { case restaurant, cafe, bar }

        let name: String
        let kind: Kind
        /// Meters from you.
        let distance: Double

        var id: String { name + String(Int(distance)) }

        var emoji: String {
            switch kind {
            case .restaurant: return "🍽️"
            case .cafe:       return "☕️"
            case .bar:        return "🍻"
            }
        }

        var kindText: String {
            switch kind {
            case .restaurant: return "Restaurant"
            case .cafe:       return "Café"
            case .bar:        return "Bar"
            }
        }

        var distanceText: String {
            Measurement(value: distance, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road))
        }
    }

    enum Status: Equatable {
        case idle, locating, ready, denied, none, failed
    }

    @Published private(set) var places: [Place] = []
    @Published private(set) var status: Status = .idle

    private let manager = CLLocationManager()
    private var locationWaiters: [CheckedContinuation<CLLocation?, Never>] = []
    private var authWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Location's already allowed, so looking can start without asking.
    var canLookQuietly: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    /// Finds what's around you, asking for location the first time.
    func find() async {
        status = .locating
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { c in
                authWaiters.append(c)
                manager.requestWhenInUseAuthorization()
            }
        }
        guard canLookQuietly else { status = .denied; return }
        guard let here = await location() else { status = .failed; return }

        var found = await search(around: here, radius: 300)
        if found.isEmpty { found = await search(around: here, radius: 900) }
        places = found
        status = found.isEmpty ? .none : .ready
    }

    private func search(around here: CLLocation, radius: CLLocationDistance) async -> [Place] {
        let request = MKLocalPointsOfInterestRequest(center: here.coordinate, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery, .brewery, .winery, .nightlife
        ])
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        var seen = Set<String>()
        return response.mapItems
            .compactMap { item -> Place? in
                guard let name = item.name, !name.isEmpty, seen.insert(name.lowercased()).inserted else { return nil }
                let spot = Self.location(of: item)
                return Place(name: name, kind: Self.kind(item.pointOfInterestCategory),
                             distance: spot.map { here.distance(from: $0) } ?? radius)
            }
            .sorted { $0.distance < $1.distance }
            .prefix(12)
            .map { $0 }
    }

    private static func location(of item: MKMapItem) -> CLLocation? {
        if #available(iOS 26.0, *) { return item.location }
        return item.placemark.location
    }

    static func kind(_ category: MKPointOfInterestCategory?) -> Place.Kind {
        switch category {
        case .brewery?, .winery?, .nightlife?: return .bar
        case .cafe?, .bakery?:                 return .cafe
        default:                               return .restaurant
        }
    }

    private func location() async -> CLLocation? {
        if let recent = manager.location, Date().timeIntervalSince(recent.timestamp) < 60,
           recent.horizontalAccuracy <= 80 {
            return recent
        }
        return await withCheckedContinuation { (c: CheckedContinuation<CLLocation?, Never>) in
            locationWaiters.append(c)
            if locationWaiters.count == 1 { manager.requestLocation() }
        }
    }

    private func finish(_ location: CLLocation?) {
        let waiters = locationWaiters
        locationWaiters = []
        waiters.forEach { $0.resume(returning: location) }
    }
}

extension NearbyPlaces: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
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
