import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - 2. Main Page View
struct HomePage: View {
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var rideViewModel: RideViewModel
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentPendingRideRequest: PendingRideRequest?

    var body: some View {
        NavigationStack {
            content
        }
        .onAppear {
            let captainId = authViewModel.captainId
            homeViewModel.initializeHome(captainId: captainId)
            homeViewModel.bindWebSocket(rideViewModel.webSocketService)
            rideViewModel.connectSocket(authToken: authViewModel.authToken ?? "")
        }
        .onDisappear {
            rideViewModel.disconnectSocket()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch homeViewModel.state {
        case .loading:
            ProgressView("Loading...")
        case .error(let message):
            Text(message)
        case .ready(
            isOnline: let isOnline,
            currentPosition: let pos,
            pendingRide: let pending,
            someOtherData: _
        ):
            ZStack {
                Map(position: $cameraPosition) {
                     if let coordinate = pos?.coordinate {
                        Marker("Your Location", coordinate: coordinate)
                    }
                }
                .ignoresSafeArea()
                
                VStack {
                    TopBarView(isOnline: isOnline)
                    Spacer()
                    OnlineStatusControlView(isOnline: isOnline)
                }
            }
            .onAppear {
                if let coordinate = pos?.coordinate {
                    cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000))
                }
            }
            .onChange(of: pos) { _, newPos in
                if let coordinate = newPos?.coordinate {
                    withAnimation {
                        cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000))
                    }
                }
            }
            .onChange(of: pending) { _, newValue in
                if let request = newValue {
                    self.currentPendingRideRequest = request
                }
            }
            .sheet(item: $currentPendingRideRequest) { ride in
                RideRequestBottomSheet(
                    rideRequest: ride,
                    onAccept: {
                        rideViewModel.acceptRide(rideId: ride.rideId)
                        homeViewModel.rideRequestDismissed()
                        currentPendingRideRequest = nil
                    },
                    onReject: {
                        homeViewModel.rideRequestDismissed()
                        currentPendingRideRequest = nil
                    }
                )
                .presentationDetents([.fraction(0.6)])
            }
        }
    }
}

// MARK: - 3. Subviews (Fixes "Cannot find TopBarView in scope")

struct TopBarView: View {
    let isOnline: Bool
    var body: some View {
        HStack {
            Text(isOnline ? "ONLINE" : "OFFLINE")
                .font(.caption.bold())
                .padding()
                .background(isOnline ? Color.green : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
        }.padding()
    }
}

struct OnlineStatusControlView: View {
    @EnvironmentObject var homeViewModel: HomeViewModel
    let isOnline: Bool

    private func onToggleTapped() {
        homeViewModel.toggleOnlineStatus()
    }

    var body: some View {
        Button(action: onToggleTapped) {
            Circle()
                .fill(isOnline ? Color.red : Color.blue)
                .frame(width: 60, height: 60)
                .overlay(Image(systemName: "power").foregroundColor(.white))
        }.padding(.bottom, 40)
    }
}

struct RideRequestBottomSheet: View {
    let rideRequest: PendingRideRequest
    var onAccept: () -> Void
    var onReject: () -> Void

    @State private var countdown: Int = 30
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(countdown), total: 30)
                .tint(countdown > 10 ? AppColors.primary : AppColors.error)
                .background(AppColors.inputFill)

            VStack(spacing: 0) {
                HStack {
                    Text("INCOMING REQUEST")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.info)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppColors.info.opacity(0.1))
                        .clipShape(Capsule())

                    Spacer()

                    Text("\(countdown)s")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(countdown > 10 ? AppColors.primary : AppColors.error)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background((countdown > 10 ? AppColors.primary : AppColors.error).opacity(0.1))
                        .clipShape(Capsule())
                }

                HStack(spacing: 12) {
                    Circle()
                        .fill(AppColors.inputFill)
                        .frame(width: 50, height: 50)
                        .overlay(
                            Text(String((rideRequest.customerName ?? "C").prefix(1)).uppercased())
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(AppColors.textPrimary)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(rideRequest.customerName ?? "Customer")
                            .font(.system(size: 18, weight: .bold))

                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 12))
                            Text(String(format: "%.1f", rideRequest.customerRating ?? 4.8))
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("$\(String(format: "%.2f", rideRequest.fare))")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppColors.success)
                        Text("\(String(format: "%.1f", rideRequest.distanceKm ?? 0.0)) km")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.top, 16)

                locationInfo(
                    icon: "smallcircle.filled.circle",
                    color: AppColors.pickupMarker,
                    label: "Pickup",
                    address: rideRequest.pickupLocation
                )
                .padding(.top, 16)

                locationInfo(
                    icon: "mappin.circle.fill",
                    color: AppColors.dropoffMarker,
                    label: "Dropoff",
                    address: rideRequest.dropoffLocation
                )
                .padding(.top, 12)

                Button(action: onAccept) {
                    Text("ACCEPT")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundStyle(.white)
                        .background(AppColors.success)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 24)
            }
            .padding(24)
        }
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onReceive(timer) { _ in
            guard countdown > 0 else { return }
            countdown -= 1
            if countdown == 0 {
                onReject()
            }
        }
    }

    @ViewBuilder
    private func locationInfo(icon: String, color: Color, label: String, address: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                Text(address)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
        }
    }
}
