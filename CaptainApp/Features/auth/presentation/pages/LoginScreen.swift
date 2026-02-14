import SwiftUI

struct LoginScreen: View {
    @StateObject private var authViewModel = AuthViewModel()
    
    @State private var email = ""
    @State private var password = ""
    @State private var obscurePassword = true
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showHomePage = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Spacer().frame(height: 60)

                    Text("Welcome\nCaptain!")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Login to start accepting rides")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Spacer().frame(height: 32)

                    // Email Text Field
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                    // Password Text Field
                    passwordField(
                        title: "Password",
                        text: $password,
                        isSecure: $obscurePassword
                    )
                    
                    Spacer().frame(height: 16)

                    // Login Button
                    Button(action: {
                        if validateForm() {
                            authViewModel.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                        }
                    }) {
                        if authViewModel.state == .loading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Login")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(authViewModel.state == .loading)
                    
                    Spacer().frame(height: 16)

                    // Register Row
                    HStack {
                        Text("Don't have an account?")
                        
                        NavigationLink("Register") {
                            RegisterScreen()
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
            }
            .navigationBarHidden(true)
            .alert("Login Error", isPresented: $showingAlert) {
                Button("OK") {}
            } message: {
                Text(alertMessage)
            }
            .onChange(of: authViewModel.state) { newState in
                if case .error(let message) = newState {
                    alertMessage = message
                    showingAlert = true
                } else if case .authenticated = newState {
                    showHomePage = true
                }
            }
            .navigationDestination(isPresented: $showHomePage) {
                HomePage()
                    .environmentObject(authViewModel)
                    .environmentObject(HomeViewModel())
                    .environmentObject(RideViewModel(webSocketService: WebSocketService()))
            }
        }
    }
    
    @ViewBuilder
    func passwordField(title: String, text: Binding<String>, isSecure: Binding<Bool>) -> some View {
        HStack {
            Group {
                if isSecure.wrappedValue {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)

            Button(action: { isSecure.wrappedValue.toggle() }) {
                Image(systemName: isSecure.wrappedValue ? "eye.slash" : "eye")
                    .foregroundColor(.secondary)
            }
            .padding(.trailing, 8)
        }
    }

    private func validateForm() -> Bool {
        if email.isEmpty || !email.contains("@") {
            alertMessage = "Please enter a valid email."
            showingAlert = true
            return false
        }
        if password.count < 6 {
            alertMessage = "Password must be at least 6 characters."
            showingAlert = true
            return false
        }
        return true
    }
}

struct LoginScreen_Previews: PreviewProvider {
    static var previews: some View {
        LoginScreen()
    }
}
