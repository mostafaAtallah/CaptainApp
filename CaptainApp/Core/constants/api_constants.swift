//
//  api_constants.swift
//  CaptainApp
//
//  Created by user on 10/02/2026.
//

import Foundation

struct ApiConstants {
    // Base URLs
    // IMPORTANT: Replace with your actual backend URL for local development or production
    static let baseUrl = "https://ladytaxi20251225225008-chhmhgf4e8h4fbdn.canadacentral-01.azurewebsites.net"
    static let socketUrl = "https://ladytaxi20251225225008-chhmhgf4e8h4fbdn.canadacentral-01.azurewebsites.net"

    // Auth Endpoints
    static let loginPath = "/api/auth/login"
    static let registerCaptainPath = "/api/auth/register/captain"
    static let registerUserPath = "/api/auth/register/user"

    // Driver Endpoints
    static let driverProfilePath = "/api/driver/profile"
    static let driverDocumentsPath = "/api/driver/documents"
    static let driverStatusPath = "/api/driver/status"
    static let driverEarningsPath = "/api/driver/earnings"
    static let driverRideHistoryPath = "/api/driver/rides/history"
    static func captainRideHistoryPath(captainId: Int) -> String {
        return "/api/trips/captain/\(captainId)"
    }
    static func updatePassengerPreferencePath(id: String) -> String {
        return "/api/captains/\(id)/passenger-preference"
    }

    // Ride Endpoints
    static func acceptRidePath(id: String) -> String {
        return "/api/trips/driver/rides/\(id)/accept"
    }
    static func rejectRidePath(id: String) -> String {
        return "/api/trips/driver/rides/\(id)/reject"
    }
    static func updateRideStatusPath(id: String) -> String {
        return "/api/trips/driver/rides/\(id)/status"
    }
    static func rideDetailsPath(id: String) -> String {
        return "/api/trips/\(id)"
    }

    // Location Endpoints
    static let updateLocationPath = "/api/location/update"
    static let getRoutePath = "/api/location/route"

    // Headers
    static let authHeader = "Authorization"
    static let contentType = "Content-Type"
    static let applicationJson = "application/json"

    // Timeouts (in milliseconds, convert to seconds for URLSession)
    static let connectionTimeoutMs = 30000 // 30 seconds
    static let receiveTimeoutMs = 30000    // 30 seconds

    // MARK: - Full URLs for convenience

    static var loginUrl: URL? { URL(string: baseUrl + loginPath) }
    static var registerCaptainUrl: URL? { URL(string: baseUrl + registerCaptainPath) }
    static var registerUserUrl: URL? { URL(string: baseUrl + registerUserPath) }
    static var driverProfileUrl: URL? { URL(string: baseUrl + driverProfilePath) }
    static func captainProfilePath(captainId: Int) -> String {
        return "/api/captains/\(captainId)"
    }
    static func captainProfileUrl(captainId: Int) -> URL? {
        URL(string: baseUrl + captainProfilePath(captainId: captainId))
    }
    static var driverDocumentsUrl: URL? { URL(string: baseUrl + driverDocumentsPath) }
    static var driverStatusUrl: URL? { URL(string: baseUrl + driverStatusPath) }
    static var driverEarningsUrl: URL? { URL(string: baseUrl + driverEarningsPath) }
    static var driverRideHistoryUrl: URL? { URL(string: baseUrl + driverRideHistoryPath) }
    static func captainRideHistoryUrl(captainId: Int) -> URL? {
        URL(string: baseUrl + captainRideHistoryPath(captainId: captainId))
    }

    static func updatePassengerPreferenceUrl(id: String) -> URL? {
        URL(string: baseUrl + updatePassengerPreferencePath(id: id))
    }
    static func acceptRideUrl(id: String) -> URL? {
        URL(string: baseUrl + acceptRidePath(id: id))
    }
    static func rejectRideUrl(id: String) -> URL? {
        URL(string: baseUrl + rejectRidePath(id: id))
    }
    static func updateRideStatusUrl(id: String) -> URL? {
        URL(string: baseUrl + updateRideStatusPath(id: id))
    }
    static func rideDetailsUrl(id: String) -> URL? {
        URL(string: baseUrl + rideDetailsPath(id: id))
    }
    static var updateLocationUrl: URL? { URL(string: baseUrl + updateLocationPath) }
    static var getRouteUrl: URL? { URL(string: baseUrl + getRoutePath) }
}
