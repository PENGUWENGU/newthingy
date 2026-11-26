import CoreLocation
import Foundation

final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var _lastKnownCoordinate: CLLocationCoordinate2D?

    var lastKnownCoordinate: CLLocationCoordinate2D? {
        lock.lock()
        defer { lock.unlock() }
        return _lastKnownCoordinate
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
    }

    func start() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last,
              latest.horizontalAccuracy >= 0,
              RouteSimulationEngine.isValidCoordinate(latest.coordinate) else { return }
        lock.lock()
        _lastKnownCoordinate = latest.coordinate
        lock.unlock()
    }
}
