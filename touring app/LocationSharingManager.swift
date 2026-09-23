import Combine
import CoreLocation
import Foundation

final class LocationSharingManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocation, Error>) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestCurrentLocation(completion: @escaping (Result<CLLocation, Error>) -> Void) {
        self.completion = completion
        errorMessage = nil
        isLoading = true

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: .failure(LocationSharingError.permissionDenied))
        @unknown default:
            finish(with: .failure(LocationSharingError.unavailable))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: .failure(LocationSharingError.permissionDenied))
        case .notDetermined:
            break
        @unknown default:
            finish(with: .failure(LocationSharingError.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(with: .failure(LocationSharingError.unavailable))
            return
        }

        finish(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<CLLocation, Error>) {
        isLoading = false
        if case .failure = result {
            errorMessage = "現在地を取得できませんでした。"
        }
        completion?(result)
        completion = nil
    }
}

enum LocationSharingError: LocalizedError {
    case permissionDenied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "位置情報の許可が必要です。"
        case .unavailable:
            return "現在地を取得できませんでした。"
        }
    }
}
