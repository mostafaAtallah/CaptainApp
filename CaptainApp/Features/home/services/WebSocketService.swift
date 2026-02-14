import Foundation
import Combine

struct PendingRideRequest: Identifiable, Equatable, Codable {
    let id = UUID()
    let rideId: String
    let pickupLocation: String
    let dropoffLocation: String
    let fare: Double
    let customerName: String?
    let customerRating: Double?
    let distanceKm: Double?
}

class WebSocketService: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    @Published private(set) var isConnected = false
    
    let rideRequestSubject = PassthroughSubject<PendingRideRequest, Never>()

    init() {
        self.session = URLSession(configuration: .default, delegate: nil, delegateQueue: OperationQueue())
    }

    func connect(authToken: String) {
        let socketBase = ApiConstants.socketUrl
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
        let safeToken = authToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? authToken

        guard let url = URL(string: "\(socketBase)/ws?token=\(safeToken)") else {
            print("Error: Invalid WebSocket URL")
            return
        }
        
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        
        print("WebSocket connected")
        listenForMessages()
    }

    func connectIfNeeded(authToken: String) {
        guard !isConnected else { return }
        if authToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("WebSocketService: empty auth token, server may reject websocket connection")
        }
        connect(authToken: authToken)
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        print("WebSocket disconnected")
    }

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                self?.isConnected = false
                print("WebSocket receive error: \(error.localizedDescription)")
                return
            case .success(let message):
                self?.handleMessage(message)
                self?.listenForMessages()
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message else {
            print("Received non-string message")
            return
        }
        
        print("Received raw message: \(text)")
        
        guard let data = text.data(using: .utf8) else { return }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                return
            }

            // Backend may send either "event" or "@event".
            let event = (json["event"] as? String) ?? (json["@event"] as? String)
            guard let event else { return }

            print("Handling event: \(event)")

            if event == "new_ride_request" {
                guard let eventData = json["data"] as? [String: Any] else {
                    print("WebSocket: new_ride_request missing data payload")
                    return
                }

                let rideId = String(describing: eventData["ride_id"] ?? "")
                let pickupAddress = String(describing: eventData["pickup_address"] ?? "Pickup")
                let dropoffAddress = String(describing: eventData["dropoff_address"] ?? "Dropoff")
                let estimatedFare = eventData["estimated_fare"] as? Double ?? 0.0

                if rideId.isEmpty {
                    print("WebSocket: new_ride_request has empty ride_id")
                    return
                }

                let pendingRequest = PendingRideRequest(
                    rideId: rideId,
                    pickupLocation: pickupAddress,
                    dropoffLocation: dropoffAddress,
                    fare: estimatedFare,
                    customerName: eventData["customer_name"] as? String,
                    customerRating: eventData["customer_rating"] as? Double,
                    distanceKm: eventData["distance_km"] as? Double
                )

                DispatchQueue.main.async {
                    self.rideRequestSubject.send(pendingRequest)
                }
            }
        } catch {
            print("WebSocket JSON decoding error: \(error.localizedDescription)")
        }
    }

    func sendGoOnline(driverId: String) {
        let message: [String: Any] = ["event": "go_online", "data": ["driver_id": driverId]]
        send(message)
    }

    func sendGoOffline(driverId: String) {
        let message: [String: Any] = ["event": "go_offline", "data": ["driver_id": driverId]]
        send(message)
    }
    
    func send(_ message: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: message, options: [])
            if let jsonString = String(data: data, encoding: .utf8) {
                webSocketTask?.send(.string(jsonString)) { error in
                    if let error = error {
                        print("WebSocket send error: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            print("Error serializing JSON for WebSocket: \(error.localizedDescription)")
        }
    }
}
