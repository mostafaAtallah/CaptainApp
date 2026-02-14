import Foundation
import CoreLocation

enum HomeState {
    case loading
    case ready(
        isOnline: Bool,
        currentPosition: CLLocation?,
        // Add other properties your ready state needs
        pendingRide: PendingRideRequest? = nil,
        someOtherData: String? = nil
    )
    case error(String)
}
