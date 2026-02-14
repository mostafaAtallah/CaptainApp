import Foundation
import Combine

struct WebSocketConfiguration {
    let endpointPath: String
    let pingInterval: TimeInterval
    let reconnectBaseDelay: TimeInterval
    let reconnectMaxDelay: TimeInterval

    static let `default` = WebSocketConfiguration(
        endpointPath: "/ws",
        pingInterval: 20,
        reconnectBaseDelay: 1,
        reconnectMaxDelay: 20
    )
}

struct PendingRideRequest: Identifiable, Equatable, Codable {
    let id = UUID()
    let rideId: String
    let pickupLocation: String
    let dropoffLocation: String
    let fare: Double
    let customerName: String?
    let customerRating: Double?
    let distanceKm: Double?
    let pickupLat: Double?
    let pickupLng: Double?
}

class WebSocketService: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private let configuration: WebSocketConfiguration
    private var authToken: String?
    private var reconnectAttempt = 0
    private var isManuallyDisconnected = false
    private var pingTimer: Timer?
    @Published private(set) var isConnected = false
    
    let rideRequestSubject = PassthroughSubject<PendingRideRequest, Never>()

    init(
        configuration: WebSocketConfiguration = .default,
        session: URLSession? = nil
    ) {
        self.configuration = configuration
        self.session = session ?? URLSession(
            configuration: .default,
            delegate: nil,
            delegateQueue: OperationQueue()
        )
    }

    func connect(authToken: String) {
        let trimmedToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            print("WebSocketService: empty auth token; skipping websocket connect")
            return
        }

        isManuallyDisconnected = false
        self.authToken = trimmedToken
        openSocket()
    }

    func connectIfNeeded(authToken: String) {
        guard !isConnected else { return }
        connect(authToken: authToken)
    }

    func disconnect() {
        isManuallyDisconnected = true
        authToken = nil
        reconnectAttempt = 0
        stopPing()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        print("WebSocket disconnected")
    }

    private func openSocket() {
        guard let token = authToken, let url = buildSocketURL(token: token) else {
            print("WebSocketService: invalid websocket URL configuration")
            return
        }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        reconnectAttempt = 0
        startPing()
        print("WebSocket connected")
        listenForMessages()
    }

    private func buildSocketURL(token: String) -> URL? {
        guard var components = URLComponents(string: ApiConstants.socketUrl) else {
            return nil
        }

        if components.scheme == "https" {
            components.scheme = "wss"
        } else if components.scheme == "http" {
            components.scheme = "ws"
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = configuration.endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if basePath.isEmpty {
            components.path = "/\(endpointPath)"
        } else {
            components.path = "/\(basePath)/\(endpointPath)"
        }

        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                self?.isConnected = false
                self?.stopPing()
                print("WebSocket receive error: \(error.localizedDescription)")
                self?.scheduleReconnectIfNeeded()
                return
            case .success(let message):
                self?.handleMessage(message)
                self?.listenForMessages()
            }
        }
    }

    private func scheduleReconnectIfNeeded() {
        guard !isManuallyDisconnected else { return }
        guard let token = authToken else { return }

        let delay = min(
            configuration.reconnectMaxDelay,
            configuration.reconnectBaseDelay * pow(2.0, Double(reconnectAttempt))
        )
        reconnectAttempt += 1

        print("WebSocket reconnect scheduled in \(delay)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard !self.isConnected else { return }
            guard !self.isManuallyDisconnected else { return }
            self.connect(authToken: token)
        }
    }

    private func startPing() {
        stopPing()
        guard configuration.pingInterval > 0 else { return }

        pingTimer = Timer.scheduledTimer(withTimeInterval: configuration.pingInterval, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if let error {
                print("WebSocket ping failed: \(error.localizedDescription)")
                self?.isConnected = false
                self?.stopPing()
                self?.scheduleReconnectIfNeeded()
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
                    distanceKm: eventData["distance_km"] as? Double,
                    pickupLat: extractPickupLatitude(from: eventData),
                    pickupLng: extractPickupLongitude(from: eventData)
                )

                print("WebSocket pickup coords parsed: lat=\(pendingRequest.pickupLat?.description ?? "nil"), lng=\(pendingRequest.pickupLng?.description ?? "nil")")

                DispatchQueue.main.async {
                    self.rideRequestSubject.send(pendingRequest)
                }
            }
        } catch {
            print("WebSocket JSON decoding error: \(error.localizedDescription)")
        }
    }

    private func parseDouble(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private func extractPickupLatitude(from eventData: [String: Any]) -> Double? {
        let directKeys = [
            "pickup_lat",
            "pickupLat",
            "pickup_latitude",
            "pickupLatitude",
            "lat",
            "latitude"
        ]

        for key in directKeys {
            if let value = parseDouble(eventData[key]) {
                return value
            }
        }

        if let pickup = eventData["pickup"] as? [String: Any] {
            for key in ["lat", "latitude", "pickup_lat", "pickup_latitude"] {
                if let value = parseDouble(pickup[key]) {
                    return value
                }
            }

            if let coordinates = pickup["coordinates"] as? [Any], coordinates.count >= 2 {
                // GeoJSON coordinate order is [longitude, latitude].
                if let latitude = parseDouble(coordinates[1]) {
                    return latitude
                }
            }
        }

        if let location = eventData["pickup_location"] as? [String: Any] {
            for key in ["lat", "latitude"] {
                if let value = parseDouble(location[key]) {
                    return value
                }
            }

            if let coordinates = location["coordinates"] as? [Any], coordinates.count >= 2 {
                if let latitude = parseDouble(coordinates[1]) {
                    return latitude
                }
            }
        }

        if let coordinates = eventData["pickup_coordinates"] as? [Any], coordinates.count >= 2 {
            if let latitude = parseDouble(coordinates[1]) {
                return latitude
            }
        }

        return nil
    }

    private func extractPickupLongitude(from eventData: [String: Any]) -> Double? {
        let directKeys = [
            "pickup_lng",
            "pickupLng",
            "pickup_longitude",
            "pickupLongitude",
            "lng",
            "lon",
            "longitude"
        ]

        for key in directKeys {
            if let value = parseDouble(eventData[key]) {
                return value
            }
        }

        if let pickup = eventData["pickup"] as? [String: Any] {
            for key in ["lng", "lon", "longitude", "pickup_lng", "pickup_longitude"] {
                if let value = parseDouble(pickup[key]) {
                    return value
                }
            }

            if let coordinates = pickup["coordinates"] as? [Any], coordinates.count >= 2 {
                if let longitude = parseDouble(coordinates[0]) {
                    return longitude
                }
            }
        }

        if let location = eventData["pickup_location"] as? [String: Any] {
            for key in ["lng", "lon", "longitude"] {
                if let value = parseDouble(location[key]) {
                    return value
                }
            }

            if let coordinates = location["coordinates"] as? [Any], coordinates.count >= 2 {
                if let longitude = parseDouble(coordinates[0]) {
                    return longitude
                }
            }
        }

        if let coordinates = eventData["pickup_coordinates"] as? [Any], coordinates.count >= 2 {
            if let longitude = parseDouble(coordinates[0]) {
                return longitude
            }
        }

        return nil
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
        guard isConnected else {
            print("WebSocket send skipped: socket is not connected")
            return
        }
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
