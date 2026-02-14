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
    
    /// Accepts a ride via HTTP so backend can broadcast full captain info from DB.
    /// Falls back to WebSocket event if HTTP fails.
    func acceptRide(rideId: String, authToken: String?) {
        guard let url = ApiConstants.acceptRideUrl(id: rideId) else {
            sendAcceptRideViaSocketOnly(rideId: rideId)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeoutMs / 1000)

        if let token = authToken, !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)
        }

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error {
                print("Ride accept HTTP failed: \(error.localizedDescription). Falling back to WebSocket.")
                self?.sendAcceptRideViaSocketOnly(rideId: rideId)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("Ride accept HTTP failed: no HTTP response. Falling back to WebSocket.")
                self?.sendAcceptRideViaSocketOnly(rideId: rideId)
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                print("Ride accepted via HTTP: \(rideId)")
            } else {
                print("Ride accept HTTP status \(httpResponse.statusCode). Falling back to WebSocket.")
                self?.sendAcceptRideViaSocketOnly(rideId: rideId)
            }
        }.resume()
    }

    /// WebSocket fallback (kept for compatibility).
    private func sendAcceptRideViaSocketOnly(rideId: String) {
        let message: [String: Any] = [
            "event": "accept_ride",
            "data": ["ride_id": rideId]
        ]
        socketService.send(message)
        print("Ride accepted via WebSocket fallback: \(rideId)")
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
