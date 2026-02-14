import SwiftUI
import Foundation

struct CaptainProfileData {
    var fullName: String = "Captain"
    var rating: Double = 0
    var isVerified: Bool = false
    var totalTrips: Int = 0
    var experienceText: String = "-"
    var acceptanceRateText: String = "-"
    var vehicleInfo: String = "Not available"
}

@MainActor
final class CaptainProfileViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var profile = CaptainProfileData()

    func load(authToken: String?, captainId: Int?) {
        guard let captainId else {
            errorMessage = "Missing captain id"
            return
        }
        guard let url = ApiConstants.captainProfileUrl(captainId: captainId) else {
            errorMessage = "Invalid profile endpoint"
            return
        }

        isLoading = true
        errorMessage = nil

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeoutMs / 1000)
        if let token = authToken, !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false

                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.errorMessage = "Invalid profile response"
                    return
                }

                let payload = Self.extractPayload(from: json)
                self.profile = Self.parseProfile(payload)
            }
        }.resume()
    }

    private static func extractPayload(from json: [String: Any]) -> [String: Any] {
        if let data = json["data"] as? [String: Any] { return data }
        if let profile = json["profile"] as? [String: Any] { return profile }
        if let driver = json["driver"] as? [String: Any] { return driver }
        return json
    }

    private static func parseProfile(_ payload: [String: Any]) -> CaptainProfileData {
        var result = CaptainProfileData()

        let firstName = asString(payload["firstName"]) ?? asString(payload["FirstName"]) ?? asString(payload["first_name"]) ?? ""
        let familyName = asString(payload["familyName"]) ?? asString(payload["FamilyName"]) ?? asString(payload["family_name"]) ?? ""
        let combined = "\(firstName) \(familyName)".trimmingCharacters(in: .whitespaces)
        result.fullName = combined.isEmpty ? (asString(payload["UserName"]) ?? asString(payload["name"]) ?? asString(payload["fullName"]) ?? "Captain") : combined

        result.rating = asDouble(payload["Rating"]) ?? asDouble(payload["rating"]) ?? asDouble(payload["averageRating"]) ?? asDouble(payload["average_rating"]) ?? 0
        result.isVerified = asBool(payload["IsVerified"]) ?? asBool(payload["isVerified"]) ?? asBool(payload["verified"]) ?? false

        result.totalTrips = asInt(payload["TotalRides"]) ?? asInt(payload["totalTrips"]) ?? asInt(payload["total_trips"]) ?? asInt(payload["completedTrips"]) ?? 0

        if let experienceYears = asDouble(payload["experienceYears"]) ?? asDouble(payload["experience_years"]) {
            result.experienceText = String(format: "%.1f yrs", experienceYears)
        } else {
            result.experienceText = asString(payload["experience"]) ?? "-"
        }

        if let acceptance = asDouble(payload["acceptanceRate"]) ?? asDouble(payload["acceptance_rate"]) {
            result.acceptanceRateText = "\(Int(acceptance.rounded()))%"
        } else {
            result.acceptanceRateText = asString(payload["acceptance"]) ?? "-"
        }

        if let vehicle = payload["vehicle"] as? [String: Any] {
            let make = asString(vehicle["make"]) ?? ""
            let model = asString(vehicle["model"]) ?? ""
            let plate = asString(vehicle["plateNumber"]) ?? asString(vehicle["plate_number"]) ?? ""
            let vehicleTitle = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
            let text = [vehicleTitle, plate].filter { !$0.isEmpty }.joined(separator: " • ")
            result.vehicleInfo = text.isEmpty ? "Not available" : text
        } else {
            let make = asString(payload["VehicleMake"]) ?? asString(payload["vehicleMake"]) ?? ""
            let model = asString(payload["VehicleModel"]) ?? asString(payload["vehicleModel"]) ?? ""
            let plate = asString(payload["PlateNumber"]) ?? asString(payload["plateNumber"]) ?? asString(payload["plate_number"]) ?? ""
            let vehicleTitle = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
            let text = [vehicleTitle, plate].filter { !$0.isEmpty }.joined(separator: " • ")
            result.vehicleInfo = text.isEmpty ? (asString(payload["vehicleInfo"]) ?? asString(payload["vehicle_info"]) ?? "Not available") : text
        }

        return result
    }
}

struct ProfilePage: View {
    enum PassengerPreference: String, CaseIterable, Identifiable {
        case any
        case female
        case male

        var id: String { rawValue }

        var title: String {
            switch self {
            case .any: return "Any"
            case .female: return "Female"
            case .male: return "Male"
            }
        }

        var icon: String {
            switch self {
            case .any: return "person.fill"
            case .female: return "figure.stand.dress.line.vertical.figure"
            case .male: return "figure.stand"
            }
        }
    }

    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = CaptainProfileViewModel()

    @State private var currentPassengerPreference: PassengerPreference = .any
    @State private var selectedPassengerPreference: PassengerPreference = .any
    @State private var showPassengerPreferenceSheet = false
    @State private var showLogoutDialog = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                    Color.clear.frame(height: 16)

                    menuItem(icon: "car.fill", title: "Vehicle Information", subtitle: viewModel.profile.vehicleInfo)
                    menuItem(icon: "doc.text.fill", title: "Documents", subtitle: "License, Insurance, Registration")
                    menuItem(icon: "wallet.pass.fill", title: "Payment Methods", subtitle: "Bank account for payouts")
                    menuItem(icon: "clock.fill", title: "Ride History", subtitle: "View all your past rides")
                    menuItem(icon: "bell.fill", title: "Notifications", subtitle: "Manage notification preferences")
                    menuItem(icon: "figure.2", title: "Passenger Preferences", subtitle: "Choose preferred passenger gender") {
                        selectedPassengerPreference = currentPassengerPreference
                        showPassengerPreferenceSheet = true
                    }
                    menuItem(icon: "questionmark.circle.fill", title: "Help & Support", subtitle: "FAQs, Contact support")
                    menuItem(icon: "gearshape.fill", title: "Settings", subtitle: "App preferences")

                    VStack(spacing: 16) {
                        Button("Logout") {
                            showLogoutDialog = true
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(AppColors.error)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.error, lineWidth: 1)
                        )

                        Text("Version 1.0.0")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(16)
                    Color.clear.frame(height: 24)
                }
            }
        }
        .background(AppColors.background)
        .sheet(isPresented: $showPassengerPreferenceSheet) {
            passengerPreferenceSheet
        }
        .alert("Logout", isPresented: $showLogoutDialog) {
            Button("Cancel", role: .cancel) {}
            Button("Logout", role: .destructive) {
                // Hook logout flow here.
            }
        } message: {
            Text("Are you sure you want to logout?")
        }
        .task {
            viewModel.load(authToken: authViewModel.authToken, captainId: authViewModel.captainId)
        }
    }

    private var topBar: some View {
        HStack {
            Text("Profile")
                .font(.title3.bold())
            Spacer()
            Button(action: {}) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.surface)
    }

    private var profileHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppColors.inputFill)
                    .frame(width: 100, height: 100)
                Image(systemName: "person.fill")
                    .font(.system(size: 48))
                    .foregroundColor(AppColors.textSecondary)
            }

            if viewModel.isLoading {
                ProgressView()
            }

            Text(viewModel.profile.fullName)
                .font(.system(size: 24, weight: .bold))

            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text(String(format: "%.2f", viewModel.profile.rating))
                    .font(.system(size: 16, weight: .medium))
                if viewModel.profile.isVerified {
                    Text("Verified")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.success.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            HStack {
                statColumn(value: "\(viewModel.profile.totalTrips)", label: "Trips")
                Spacer()
                statColumn(value: viewModel.profile.experienceText, label: "Experience")
                Spacer()
                statColumn(value: viewModel.profile.acceptanceRateText, label: "Acceptance")
            }
            .padding(.top, 8)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(AppColors.error)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
            Text(label)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func menuItem(
        icon: String,
        title: String,
        subtitle: String,
        onTap: (() -> Void)? = nil
    ) -> some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.inputFill)
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .foregroundColor(AppColors.primary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppColors.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppColors.surface)
        }
        .buttonStyle(.plain)
    }

    private var passengerPreferenceSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose your preferred passenger gender")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)

                ForEach(PassengerPreference.allCases) { option in
                    Button {
                        selectedPassengerPreference = option
                    } label: {
                        HStack {
                            Image(systemName: option.icon)
                                .frame(width: 22)
                            Text(option.title)
                            Spacer()
                            Image(systemName: selectedPassengerPreference == option ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(selectedPassengerPreference == option ? AppColors.primary : AppColors.textSecondary)
                        }
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.vertical, 4)
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Passenger Preference")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showPassengerPreferenceSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        currentPassengerPreference = selectedPassengerPreference
                        showPassengerPreferenceSheet = false
                    }
                }
            }
        }
    }
}

private func asString(_ value: Any?) -> String? {
    if let text = value as? String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return nil
}

private func asDouble(_ value: Any?) -> Double? {
    if let number = value as? Double { return number }
    if let number = value as? NSNumber { return number.doubleValue }
    if let text = value as? String { return Double(text) }
    return nil
}

private func asInt(_ value: Any?) -> Int? {
    if let number = value as? Int { return number }
    if let number = value as? NSNumber { return number.intValue }
    if let text = value as? String { return Int(text) }
    return nil
}

private func asBool(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    if let number = value as? NSNumber { return number.intValue != 0 }
    if let text = value as? String {
        switch text.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }
    return nil
}
