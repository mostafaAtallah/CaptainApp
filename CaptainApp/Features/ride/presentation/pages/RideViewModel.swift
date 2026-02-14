import Foundation
import Combine

class RideViewModel: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    
    private let socketService: WebSocketService

    init(webSocketService: WebSocketService) {
        self.socketService = webSocketService
    }

    var webSocketService: WebSocketService {
        socketService
    }
    
    /// Accepts a ride by rideId
    func acceptRide(rideId: String) {
        // Send "go_online" or "accept_ride" event via WebSocket
        // Adjust event name according to your backend
        let message: [String: Any] = [
            "event": "accept_ride",
            "data": ["ride_id": rideId]
        ]
        
        socketService.send(message)
        
        print("Ride accepted: \(rideId)")
        
        // You can also trigger local state updates if needed
        // e.g., mark as active ride in the app
    }
    
    /// Rejects a ride (optional, if needed)
    func rejectRide(rideId: String) {
        let message: [String: Any] = [
            "event": "reject_ride",
            "data": ["ride_id": rideId]
        ]
        
        socketService.send(message)
        
        print("Ride rejected: \(rideId)")
    }

    func connectSocket(authToken: String) {
        socketService.connectIfNeeded(authToken: authToken)
    }

    func disconnectSocket() {
        socketService.disconnect()
    }
}
