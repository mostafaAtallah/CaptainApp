import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - 2. Main Page View
struct HomePage: View {
    private enum BottomTab {
        case home
        case rideHistory
        case profile
    }

    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var rideViewModel: RideViewModel
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentPendingRideRequest: PendingRideRequest?
    @State private var activePickupRide: PendingRideRequest?
    @State private var routeToPickup: MKRoute?
    @State private var fallbackRouteLine: MKPolyline?
    @State private var resolvedPickupCoordinate: CLLocationCoordinate2D?
    @State private var lastCaptainCoordinate: CLLocationCoordinate2D?
    @State private var pickupLineSourceCoordinate: CLLocationCoordinate2D?
    @State private var lineDebugText: String = "line: idle"
    @State private var selectedTab: BottomTab = .home
    @StateObject private var locationProvider = LocationProvider()
    private let minLineDistanceMeters: CLLocationDistance = 2
    private let maxLineDistanceMeters: CLLocationDistance = 200_000

    var body: some View {
        NavigationStack {
            content
        }
        .onAppear {
            let captainId = authViewModel.captainId
            homeViewModel.initializeHome(captainId: captainId)
            homeViewModel.bindWebSocket(rideViewModel.webSocketService)
            if let token = authViewModel.authToken, !token.isEmpty {
                rideViewModel.connectSocket(authToken: token)
            } else {
                print("HomePage: missing auth token, websocket connection skipped")
            }
            locationProvider.start()
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
            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case .home:
                        homeTabContent(isOnline: isOnline, pos: pos, pending: pending)
                    case .rideHistory:
                        RideHistoryPage()
                    case .profile:
                        ProfilePage()
                    }
                }
                bottomTabBar
            }
        }
    }

    private func homeTabContent(
        isOnline: Bool,
        pos: CLLocation?,
        pending: PendingRideRequest?
    ) -> some View {
        ZStack {
            Map(position: $cameraPosition) {
                 if let coordinate = captainDisplayCoordinate ?? pos?.coordinate {
                    Marker("Your Location", coordinate: coordinate)
                }
                if let pickup = pickupCoordinate {
                    Marker("Pickup", coordinate: pickup)
                        .tint(AppColors.pickupMarker)
                }
                if let fallbackRouteLine {
                    MapPolyline(fallbackRouteLine)
                        .stroke(AppColors.routeLine, lineWidth: 6)
                } else if let routeToPickup {
                    MapPolyline(routeToPickup.polyline)
                        .stroke(AppColors.routeLine, lineWidth: 5)
                }
            }
            .ignoresSafeArea()

            VStack {
                TopBarView(isOnline: isOnline)
                #if DEBUG
                Text(lineDebugText)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12)
                #endif
                if let activePickupRide {
                    pickupGuidanceCard(for: activePickupRide)
                }
                Spacer()
                OnlineStatusControlView(isOnline: isOnline)
            }
        }
        .onAppear {
            if let coordinate = captainDisplayCoordinate ?? pos?.coordinate {
                lastCaptainCoordinate = coordinate
                cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000))
            }
        }
        .onChange(of: pos) { _, newPos in
            if let coordinate = captainDisplayCoordinate ?? newPos?.coordinate {
                let hadNoCaptainLocation = (lastCaptainCoordinate == nil)
                lastCaptainCoordinate = coordinate

                if hadNoCaptainLocation && activePickupRide == nil {
                    withAnimation {
                        cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000))
                    }
                }
            }
        }
        .onReceive(locationProvider.$currentLocation) { _ in
            if let coordinate = captainDisplayCoordinate {
                lastCaptainCoordinate = coordinate
                if activePickupRide != nil {
                    pickupLineSourceCoordinate = coordinate
                }
            }
            refreshRouteToPickup()
        }
        .onChange(of: activePickupRide?.id) { _, _ in
            if activePickupRide == nil {
                pickupLineSourceCoordinate = nil
                fallbackRouteLine = nil
                routeToPickup = nil
            }
            resolvePickupCoordinateIfNeeded()
            refreshRouteToPickup()
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
                    pickupLineSourceCoordinate = captainDisplayCoordinate ?? pos?.coordinate ?? lastCaptainCoordinate
                    rideViewModel.acceptRide(rideId: ride.rideId, authToken: authViewModel.authToken)
                    activePickupRide = ride
                    resolvePickupCoordinateIfNeeded()
                    refreshRouteToPickup()
                    focusOnPickup()
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

    private var bottomTabBar: some View {
        HStack {
            tabButton(tab: .home, title: "Home", systemImage: "house.fill")
            tabButton(tab: .rideHistory, title: "Ride History", systemImage: "clock.fill")
            tabButton(tab: .profile, title: "Profile", systemImage: "person.crop.circle.fill")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(AppColors.surface)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func tabButton(tab: BottomTab, title: String, systemImage: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(isSelected ? AppColors.primary : AppColors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    private func placeholderTabContent(title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    private var pickupCoordinate: CLLocationCoordinate2D? {
        if let lat = activePickupRide?.pickupLat, let lng = activePickupRide?.pickupLng {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return resolvedPickupCoordinate
    }

    private func resolvePickupCoordinateIfNeeded() {
        guard let ride = activePickupRide else {
            resolvedPickupCoordinate = nil
            return
        }

        if let lat = ride.pickupLat, let lng = ride.pickupLng {
            resolvedPickupCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            focusOnPickup()
            return
        }

        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(ride.pickupLocation) { placemarks, error in
            guard error == nil, let coordinate = placemarks?.first?.location?.coordinate else { return }
            DispatchQueue.main.async {
                resolvedPickupCoordinate = coordinate
                focusOnPickup()
                refreshRouteToPickup()
            }
        }
    }

    private func refreshRouteToPickup() {
        let sourceForDebug = pickupLineSourceCoordinate ?? captainDisplayCoordinate ?? lineSourceCoordinate
        let destinationForDebug = pickupCoordinate
        lineDebugText = "line: src=\(coordText(sourceForDebug)) dst=\(coordText(destinationForDebug))"

        guard let destination = pickupCoordinate else {
            routeToPickup = nil
            fallbackRouteLine = nil
            lineDebugText = "line: no destination"
            return
        }
        guard let sourceCoordinate = pickupLineSourceCoordinate ?? captainDisplayCoordinate ?? lineSourceCoordinate else {
            routeToPickup = nil
            fallbackRouteLine = nil
            lineDebugText = "line: no source"
            return
        }
        guard sourceCoordinate.isValidCoordinate, destination.isValidCoordinate else {
            routeToPickup = nil
            fallbackRouteLine = nil
            lineDebugText = "line: invalid coords"
            return
        }
        guard sourceCoordinate.latitude != destination.latitude || sourceCoordinate.longitude != destination.longitude else {
            fallbackRouteLine = nil
            routeToPickup = nil
            lineDebugText = "line: same point"
            return
        }

        let sourcePoint = MKMapPoint(sourceCoordinate)
        let destinationPoint = MKMapPoint(destination)
        let straightLineDistanceMeters = sourcePoint.distance(to: destinationPoint)
        guard straightLineDistanceMeters.isFinite,
              straightLineDistanceMeters > minLineDistanceMeters else {
            // Defensive guard against broken coordinates creating off-map/infinite-looking lines.
            routeToPickup = nil
            fallbackRouteLine = nil
            lineDebugText = "line: distance invalid \(Int(straightLineDistanceMeters))m"
            return
        }
        guard straightLineDistanceMeters <= maxLineDistanceMeters else {
            routeToPickup = nil
            fallbackRouteLine = nil
            lineDebugText = "line: source too far \(Int(straightLineDistanceMeters))m"
            return
        }

        // Always draw a direct straight line between captain and pickup.
        fallbackRouteLine = MKPolyline(
            coordinates: [sourceCoordinate, destination],
            count: 2
        )
        lineDebugText = "line: drawn \(Int(straightLineDistanceMeters))m"

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: sourceCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile

        MKDirections(request: request).calculate { response, error in
            guard error == nil, let route = response?.routes.first else { return }
            DispatchQueue.main.async {
                routeToPickup = route
            }
        }
    }

    private func focusOnPickup() {
        guard let pickup = pickupCoordinate else { return }
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: pickup,
                    latitudinalMeters: 900,
                    longitudinalMeters: 900
                )
            )
        }
    }

    private var preferredCaptainCoordinate: CLLocationCoordinate2D? {
        if let currentLocation = locationProvider.currentLocation {
            let coordinate = currentLocation.coordinate
            if coordinate.isUsableForRouting {
                return coordinate
            }
        }

        if let lastCaptainCoordinate, lastCaptainCoordinate.isUsableForRouting {
            return lastCaptainCoordinate
        }

        return nil
    }

    private var lineSourceCoordinate: CLLocationCoordinate2D? {
        if let preferredCaptainCoordinate {
            return preferredCaptainCoordinate
        }

        if let fallbackFromState = homeCurrentPositionCoordinate, fallbackFromState.isValidCoordinate {
            return fallbackFromState
        }

        return nil
    }

    private var captainDisplayCoordinate: CLLocationCoordinate2D? {
        if let preferredCaptainCoordinate {
            return preferredCaptainCoordinate
        }
        if let fromState = homeCurrentPositionCoordinate, fromState.isUsableForRouting {
            return fromState
        }
        return nil
    }

    private var homeCurrentPositionCoordinate: CLLocationCoordinate2D? {
        switch homeViewModel.state {
        case .ready(_, let currentPosition, _, _):
            return currentPosition?.coordinate
        default:
            return nil
        }
    }

    private func coordText(_ coordinate: CLLocationCoordinate2D?) -> String {
        guard let coordinate else { return "nil" }
        return String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }

    @ViewBuilder
    private func pickupGuidanceCard(for ride: PendingRideRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Heading to Pickup")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
            Text(ride.pickupLocation)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
            if let routeToPickup {
                Text("\(Int(routeToPickup.expectedTravelTime / 60)) min • \(String(format: "%.1f", routeToPickup.distance / 1000)) km")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(.horizontal, 16)
    }
}

private extension CLLocationCoordinate2D {
    var isValidCoordinate: Bool {
        CLLocationCoordinate2DIsValid(self)
            && latitude >= -90
            && latitude <= 90
            && longitude >= -180
            && longitude <= 180
    }

    var isUsableForRouting: Bool {
        guard isValidCoordinate else { return false }
        // Reject the common invalid origin coordinate.
        if abs(latitude) < 0.0001 && abs(longitude) < 0.0001 {
            return false
        }
        return true
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

final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentLocation: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
}
