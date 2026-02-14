import Foundation
import Combine
import CoreLocation

class HomeViewModel: ObservableObject {
    @Published var state: HomeState = .loading
    @Published var currentPendingRideRequest: PendingRideRequest?
    
    private var cancellables = Set<AnyCancellable>()
    private var hasBoundWebSocket = false
    private weak var webSocketService: WebSocketService?
    private var captainId: Int?
    
    func initializeHome(captainId: Int?) {
        self.captainId = captainId
        // Basic default state so the home page can render.
        if case .loading = state {
            state = .ready(isOnline: false, currentPosition: nil, pendingRide: nil, someOtherData: nil)
        }
    }
    
    func rideRequestDismissed() {
        currentPendingRideRequest = nil
        setPendingRide(nil)
    }
    
    func bindWebSocket(_ service: WebSocketService) {
        webSocketService = service
        guard !hasBoundWebSocket else { return }
        hasBoundWebSocket = true

        service.rideRequestSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ride in
                self?.currentPendingRideRequest = ride
                self?.setPendingRide(ride)
            }
            .store(in: &cancellables)
    }

    func toggleOnlineStatus() {
        switch state {
        case .ready(let isOnline, let currentPosition, let pendingRide, let someOtherData):
            let nextIsOnline = !isOnline
            state = .ready(
                isOnline: nextIsOnline,
                currentPosition: currentPosition,
                pendingRide: pendingRide,
                someOtherData: someOtherData
            )
            sendOnlineStatusChange(isOnline: nextIsOnline)
        case .loading:
            state = .ready(isOnline: true, currentPosition: nil, pendingRide: nil, someOtherData: nil)
            sendOnlineStatusChange(isOnline: true)
        case .error:
            break
        }
    }

    private func setPendingRide(_ ride: PendingRideRequest?) {
        switch state {
        case .ready(let isOnline, let currentPosition, _, let someOtherData):
            state = .ready(
                isOnline: isOnline,
                currentPosition: currentPosition,
                pendingRide: ride,
                someOtherData: someOtherData
            )
        case .loading:
            state = .ready(isOnline: false, currentPosition: nil, pendingRide: ride, someOtherData: nil)
        case .error:
            break
        }
    }

    private func sendOnlineStatusChange(isOnline: Bool) {
        guard let webSocketService else { return }
        guard let captainId else {
            print("HomeViewModel: captainId missing, skipping online status event")
            return
        }

        let driverId = String(captainId)
        if isOnline {
            webSocketService.sendGoOnline(driverId: driverId)
        } else {
            webSocketService.sendGoOffline(driverId: driverId)
        }
    }
}
