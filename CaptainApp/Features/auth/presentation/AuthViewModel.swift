import SwiftUI
import Foundation

// This file is the SINGLE SOURCE OF TRUTH for all Authentication-related models and the ViewModel.
// It should not be redeclared in any other file.

// MARK: - Shared Local User Model
struct User: Codable, Identifiable {
    let id: Int
    let captainId: Int?
    let email: String
    let firstName: String
    let familyName: String
}

// MARK: - API Request/Response Models
struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct RegisterCaptainRequest: Codable {
    let firstName: String
    let familyName: String
    let phoneNumber: String
    let email: String
    let gender: String
    let birthDate: Date
    let password: String
    let licenseNumber: String
    let licenseExpiryDate: Date
    let vehicleMake: String
    let vehicleModel: String
    let vehicleYear: Int
    let vehicleColor: String
    let plateNumber: String
}

struct AuthResponse: Codable {
    let success: Bool
    let message: String
    let token: String?
    let user: UserResponse?
}

struct UserResponse: Codable {
    let id: Int
    let firstName: String
    let familyName: String
    let email: String
    let phoneNumber: String
    let gender: String
    let isCaptain: Bool
    let captainId: Int?
}

// MARK: - Centralized Auth View Model
@MainActor
class AuthViewModel: ObservableObject {
    enum AuthState: Equatable {
        case initial
        case loading
        case authenticated
        case error(String)
    }

    @Published var authState: AuthState = .initial
    @Published var currentUser: User?



    var isAuthenticated: Bool {
        if case .authenticated = authState {
            return true
        }
        return false
    }

    func login(email: String, password: String) {
        authState = .loading
        
        let loginRequest = LoginRequest(email: email, password: password)
        
        guard let url = ApiConstants.loginUrl else {
            self.authState = .error("Invalid API URL for login.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(ApiConstants.applicationJson, forHTTPHeaderField: ApiConstants.contentType)
        request.httpBody = try? JSONEncoder().encode(loginRequest)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.authState = .error("Network Error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    self.authState = .error("No data from server."); return
                }
                
                do {
                    let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
                    if authResponse.success, let userResponse = authResponse.user {
                        self.currentUser = User(
                            id: userResponse.id, captainId: userResponse.captainId,
                            email: userResponse.email, firstName: userResponse.firstName,
                            familyName: userResponse.familyName
                        )
                        self.authState = .authenticated
                    } else {
                        self.authState = .error(authResponse.message)
                    }
                } catch {
                    self.authState = .error("Failed to decode login response: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    func registerCaptain(
        firstName: String, familyName: String, phoneNumber: String,
        email: String, gender: String, birthDate: Date, password: String,
        licenseNumber: String, licenseExpiryDate: Date, vehicleMake: String,
        vehicleModel: String, vehicleYear: Int, vehicleColor: String, plateNumber: String
    ) {
        authState = .loading

        let requestModel = RegisterCaptainRequest(
            firstName: firstName, familyName: familyName, phoneNumber: phoneNumber,
            email: email, gender: gender, birthDate: birthDate, password: password,
            licenseNumber: licenseNumber, licenseExpiryDate: licenseExpiryDate,
            vehicleMake: vehicleMake, vehicleModel: vehicleModel, vehicleYear: vehicleYear,
            vehicleColor: vehicleColor, plateNumber: plateNumber
        )
        
        guard let url = ApiConstants.registerCaptainUrl else {
            self.authState = .error("Invalid API URL for registration.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(ApiConstants.applicationJson, forHTTPHeaderField: ApiConstants.contentType)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        request.httpBody = try? encoder.encode(requestModel)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.authState = .error("Network Error: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    self.authState = .error("Registration failed. Please check your details and try again.")
                    return
                }
                
                // For simplicity, we'll just mark as authenticated after registration.
                self.authState = .authenticated
            }
        }.resume()
    }
}