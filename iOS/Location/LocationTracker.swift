import CoreLocation

struct Place {
    let name: String
    let latitude: Double
    let longitude: Double
}

@MainActor
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    static let shared = LocationTracker()

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []
    private var lastPlace: (location: CLLocation, place: Place)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func currentLocation() async -> CLLocation? {
        guard isAuthorized else { return nil }
        if let location = manager.location, location.timestamp.timeIntervalSinceNow > -300 {
            return location
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            if waiters.count == 1 { manager.requestLocation() }
        }
    }

    /// Reverse-geocoded place name, cached while the user stays within ~150 m.
    func currentPlace() async -> Place? {
        guard let location = await currentLocation() else { return nil }
        if let cached = lastPlace, cached.location.distance(from: location) < 150 {
            return cached.place
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = placemark?.name ?? placemark?.locality ?? String(
            format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude
        )
        let place = Place(name: name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        lastPlace = (location, place)
        return place
    }

    private func resume(with location: CLLocation?) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.resume(with: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resume(with: nil) }
    }
}
