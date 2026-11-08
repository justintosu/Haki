//
//  PlacesLocator.swift
//  Haki
//
//  The person's location for "Eat nearby": asks for when-in-use permission
//  and one location fix at a time (no continuous tracking). Main-actor like
//  the rest of the app; Core Location calls the delegate on the main thread
//  because the manager is created there.
//
//  The location manager is created on `start()`, not in `init`, because
//  SwiftUI may build (and throw away) the owning view's state more than once.
//

import CoreLocation
import Foundation
import Observation

@Observable
final class PlacesLocator: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var location: CLLocation?
    /// User-facing; nil once a location arrives.
    private(set) var errorMessage: String?
    private(set) var isLocating = false

    @ObservationIgnored private var manager: CLLocationManager?
    private let desiredAccuracy: CLLocationAccuracy

    init(desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters) {
        self.desiredAccuracy = desiredAccuracy
        super.init()
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// Location access was turned off (or isn't allowed on this device).
    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Asks for permission the first time; afterwards gets a location if
    /// there isn't one yet.
    func start() {
        let manager = activeManager()
        authorization = manager.authorizationStatus
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized, location == nil, !isLocating {
            requestLocation()
        }
    }

    /// One location fix (also used for "Try again").
    func requestLocation() {
        guard isAuthorized else { return }
        errorMessage = nil
        isLocating = true
        activeManager().requestLocation()
    }

    private func activeManager() -> CLLocationManager {
        if let manager { return manager }
        let created = CLLocationManager()
        created.desiredAccuracy = desiredAccuracy
        created.delegate = self
        manager = created
        return created
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if isAuthorized {
            if location == nil, !isLocating {
                requestLocation()
            }
        } else {
            isLocating = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        isLocating = false
        guard let latest = locations.last else { return }
        location = latest
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        isLocating = false
        authorization = manager.authorizationStatus
        // Denied access shows its own banner; anything else is worth a retry.
        guard !isDenied else { return }
        if location == nil {
            errorMessage = "Couldn't find your location. Search for a place or an area instead."
        }
    }
}
