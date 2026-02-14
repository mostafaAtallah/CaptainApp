import Foundation
import SwiftUI

enum AuthState: Equatable {
    case idle
    case loading
    case authenticated
    case error(String)
}

@MainActor
class AuthViewModel: ObservableObject {
    @Published var state: AuthState = .idle
    @State var isAuthenticated = false
    @Published var authToken: String?
    @Published var captainId: Int?
    public func registerCaptain(firstName: String, familyName: String, phone: String, email: String, gender: String, birthDate: Date, password: String, licenseNumber: String, licenseExpiryDate: Date, vehicleMake: String, vehicleModel: String, vehicleYear: Int, vehicleColor: String, plateNumber: String) {
        state = .loading
        authToken = nil
        captainId = nil
        
        guard let url = URL(string: ApiConstants.baseUrl + ApiConstants.registerCaptainPath) else {
            state = .error("Invalid API URL.")
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let body: [String: String] = [
            "firstName": firstName,
            "FamilyName": familyName,
            "phoneNumber": phone,
            "email": email,
            "password": password,
            "gender": gender,
            "dateOfBirth": dateFormatter.string(from: birthDate),
            "licenseNumber": licenseNumber,
            "licenseExpiryDate": dateFormatter.string(from: licenseExpiryDate),
            "vehicleMake": vehicleMake,
            "vehicleModel": vehicleModel,
            "vehicleYear": String(vehicleYear),
            "vehicleColor": vehicleColor,
            "plateNumber": plateNumber
        ]

        guard let finalBody = try? JSONSerialization.data(withJSONObject: body) else {
            state = .error("Failed to create request body.")
            return
        }
        
        // DEBUG: Print the request body
        if let jsonString = String(data: finalBody, encoding: .utf8) {
            print("DEBUG: Registration Request Body: \(jsonString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = finalBody
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeoutMs / 1000)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { [weak self] in
                // DEBUG: Print response details
                print("DEBUG: Registration Response: \(response.debugDescription)")
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("DEBUG: Registration Response Data: \(responseString)")
                }
                
                if let error = error {
                    if let urlError = error as? URLError, urlError.code == .timedOut {
                        self?.state = .error("The request timed out. Please check your network connection and try again.")
                    } else {
                        self?.state = .error("Registration failed: \(error.localizedDescription)")
                    }
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    if let httpResponse = response as? HTTPURLResponse {
                        self?.state = .error("Registration failed with status code: \(httpResponse.statusCode). Please check your details and try again.")
                    } else {
                        self?.state = .error("Registration failed. Please check your details and try again.")
                    }
                    return
                }
                if let data {
                    self?.extractAuthData(from: data)
                }
                self?.state = .authenticated
            }
        }.resume()
    }

    public func login(email: String, password: String) {
        state = .loading
        authToken = nil
        captainId = nil
        
        guard let url = URL(string: ApiConstants.baseUrl + ApiConstants.loginPath) else {
            state = .error("Invalid API URL.")
            return
        }

        let body: [String: String] = ["email": email, "password": password]
        
        guard let finalBody = try? JSONSerialization.data(withJSONObject: body) else {
            state = .error("Failed to create request body.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = finalBody
        request.addValue(ApiConstants.applicationJson, forHTTPHeaderField: ApiConstants.contentType)
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeoutMs / 1000)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { [weak self] in
                if let error = error {
                    if let urlError = error as? URLError, urlError.code == .timedOut {
                        self?.state = .error("The request timed out. Please check your network connection and try again.")
                    } else {
                        self?.state = .error("Login failed: \(error.localizedDescription)")
                    }
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    self?.state = .error("Invalid credentials.")
                    return
                }
                
                if let data {
                    self?.extractAuthData(from: data)
                }
                self?.state = .authenticated
            }
        }.resume()
    }

    private func extractAuthData(from data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return
        }

        if let token = (json["token"] as? String), !token.isEmpty {
            authToken = token
        }

        if let nested = json["data"] as? [String: Any], let token = (nested["token"] as? String), !token.isEmpty {
            authToken = token
        }

        if let id = extractCaptainId(from: json) {
            captainId = id
        } else if let nested = json["data"] as? [String: Any], let id = extractCaptainId(from: nested) {
            captainId = id
        }
    }

    private func extractCaptainId(from json: [String: Any]) -> Int? {
        if let user = json["user"] as? [String: Any] {
            if let id = user["captainId"] as? Int { return id }
            if let id = user["captain_id"] as? Int { return id }
        }
        if let captain = json["captain"] as? [String: Any] {
            if let id = captain["id"] as? Int { return id }
            if let id = captain["captainId"] as? Int { return id }
            if let id = captain["captain_id"] as? Int { return id }
        }
        if let id = json["captainId"] as? Int { return id }
        if let id = json["captain_id"] as? Int { return id }
        return nil
    }
}
