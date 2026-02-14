import SwiftUI

struct RegisterScreen: View {
    
    @StateObject private var authVM = AuthViewModel()
    @State private var currentStep = 0
    
    // Personal Info
    @State private var firstName = ""
    @State private var familyName = ""
    @State private var phoneNumber = ""
    @State private var gender = "Female"
    @State private var birthDate: Date?

    // Account Info
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    // Vehicle Info
    @State private var licenseNumber = ""
    @State private var licenseExpiryDate: Date?
    @State private var vehicleMake = ""
    @State private var vehicleModel = ""
    @State private var vehicleYear = ""
    @State private var vehicleColor = ""
    @State private var plateNumber = ""

    // General State
    @State private var errorMessage: String?
    @State private var didRegister = false
    
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            // Step Indicator
            HStack {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentStep ? Color.blue : Color.gray.opacity(0.5))
                        .frame(height: 6)
                }
            }
            .padding()

            TabView(selection: $currentStep) {
                PersonalInfoStep(
                    firstName: $firstName, familyName: $familyName,
                    phoneNumber: $phoneNumber, gender: $gender,
                    birthDate: $birthDate
                ).tag(0)
                
                AccountStep(
                    email: $email, password: $password,
                    confirmPassword: $confirmPassword
                ).tag(1)
                
                VehicleStep(
                    licenseNumber: $licenseNumber, licenseExpiryDate: $licenseExpiryDate,
                    vehicleMake: $vehicleMake, vehicleModel: $vehicleModel,
                    vehicleYear: $vehicleYear, vehicleColor: $vehicleColor,
                    plateNumber: $plateNumber
                ).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Error Message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            // Buttons
            HStack {
                if authVM.state == .loading {
                    ProgressView()
                } else if currentStep < 2 {
                    Button("Continue") {
                        if validateStep() {
                            withAnimation { currentStep += 1 }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Register") {
                        if validateStep() {
                            submitRegistration()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Step \(currentStep + 1) of 3")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: prevStep) {
                    Image(systemName: "arrow.backward")
                }
            }
        }
        .onChange(of: authVM.state) { newValue in
            if case .authenticated = newValue {
                didRegister = true
            } else if case .error(let msg) = newValue {
                errorMessage = msg
            }
        }
        .navigationDestination(isPresented: $didRegister) {
            HomePage()
                .environmentObject(authVM)
                .environmentObject(HomeViewModel())
                .environmentObject(RideViewModel(webSocketService: WebSocketService()))
        }
    }
    
    private func prevStep() {
        if currentStep > 0 {
            withAnimation { currentStep -= 1 }
        } else {
            dismiss()
        }
    }
    
    private func validateStep() -> Bool {
        errorMessage = nil
        switch currentStep {
        case 0: // Personal Info
            if firstName.isEmpty || familyName.isEmpty || phoneNumber.isEmpty {
                errorMessage = "All personal info fields are required."
                return false
            }
            if birthDate == nil {
                errorMessage = "Please select your birth date."
                return false
            }
        case 1: // Account Info
            if !email.contains("@") {
                errorMessage = "Invalid email format."
                return false
            }
            if password.count < 6 {
                errorMessage = "Password must be at least 6 characters."
                return false
            }
            if password != confirmPassword {
                errorMessage = "Passwords do not match."
                return false
            }
        case 2: // Vehicle Info
            if licenseNumber.isEmpty || vehicleMake.isEmpty || vehicleModel.isEmpty || vehicleYear.isEmpty || vehicleColor.isEmpty || plateNumber.isEmpty {
                errorMessage = "All vehicle fields are required."
                return false
            }
            if licenseExpiryDate == nil {
                errorMessage = "Please select your license expiry date."
                return false
            }
            if Int(vehicleYear) == nil {
                errorMessage = "Vehicle year must be a number."
                return false
            }
        default:
            break
        }
        return true
    }

    private func submitRegistration() {
        guard let birthDate = birthDate,
              let licenseExpiryDate = licenseExpiryDate,
              let vehicleYearInt = Int(vehicleYear) else {
            errorMessage = "Please ensure all fields are filled correctly."
            return
        }

        authVM.registerCaptain(
            firstName: firstName, familyName: familyName, phone: phoneNumber,
            email: email, gender: gender, birthDate: birthDate, password: password,
            licenseNumber: licenseNumber, licenseExpiryDate: licenseExpiryDate,
            vehicleMake: vehicleMake, vehicleModel: vehicleModel, vehicleYear: vehicleYearInt,
            vehicleColor: vehicleColor, plateNumber: plateNumber
        )
    }
}


// MARK: - Registration Step Sub-Views
struct PersonalInfoStep: View {
    @Binding var firstName: String
    @Binding var familyName: String
    @Binding var phoneNumber: String
    @Binding var gender: String
    @Binding var birthDate: Date?

    var body: some View {
        Form {
            Section(header: Text("Personal Information")) {
                TextField("First Name", text: $firstName)
                TextField("Family Name", text: $familyName)
                TextField("Phone Number", text: $phoneNumber)
                    .keyboardType(.phonePad)
                
                Picker("Gender", selection: $gender) {
                    Text("Female").tag("Female")
                    Text("Male").tag("Male")
                }
                
                DatePicker(
                    "Birth Date",
                    selection: Binding(
                        get: { birthDate ?? Date() },
                        set: { birthDate = $0 }
                    ),
                    in: ...Date().addingTimeInterval(-18 * 365 * 24 * 3600), // Must be 18+
                    displayedComponents: .date
                )
            }
        }
    }
}

struct AccountStep: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var confirmPassword: String

    var body: some View {
        Form {
            Section(header: Text("Account Details")) {
                TextField("Email Address", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                
                SecureField("Password", text: $password)
                SecureField("Confirm Password", text: $confirmPassword)
            }
        }
    }
}

struct VehicleStep: View {
    @Binding var licenseNumber: String
    @Binding var licenseExpiryDate: Date?
    @Binding var vehicleMake: String
    @Binding var vehicleModel: String
    @Binding var vehicleYear: String
    @Binding var vehicleColor: String
    @Binding var plateNumber: String

    var body: some View {
        Form {
            Section(header: Text("Vehicle Information")) {
                TextField("License Number", text: $licenseNumber)
                DatePicker(
                    "License Expiry Date",
                    selection: Binding(
                        get: { licenseExpiryDate ?? Date() },
                        set: { licenseExpiryDate = $0 }
                    ),
                    in: Date()...,
                    displayedComponents: .date
                )
                
                TextField("Vehicle Make (e.g., Toyota)", text: $vehicleMake)
                TextField("Vehicle Model (e.g., Camry)", text: $vehicleModel)
                TextField("Vehicle Year (e.g., 2022)", text: $vehicleYear)
                    .keyboardType(.numberPad)
                TextField("Vehicle Color", text: $vehicleColor)
                TextField("Plate Number", text: $plateNumber)
                    .autocapitalization(.allCharacters)
            }
        }
    }
}

struct RegisterScreen_Previews: PreviewProvider {
    static var previews: some View {
        RegisterScreen()
    }
}
