import SwiftUI
import MapKit
import FiveKit

extension NetworkTab {
    struct TrafficFlowSection: View {
        static var animationDefaultValue: Bool {
            #if os(macOS)
            true
            #else
            false
            #endif
        }
        
        @State private var shouldAnimate: Bool = Self.animationDefaultValue
        @State private var mapStyle: FlowMapStyle = .globe
        
        let stats: DarkbloomStats
        
        var body: some View {
            Section {
                TrafficFlowGraph(shouldAnimate: $shouldAnimate, mapStyle: $mapStyle)
            } header: {
                HStack(alignment: .bottom) {
                    Text("Traffic Flow")
                    Spacer()
                    #if os(macOS)
                    HStack {
                        Picker("Style", selection: $mapStyle) {
                            Text("2D").tag(FlowMapStyle.flat)
                            Text("3D").tag(FlowMapStyle.globe)
                        }
                        .pickerStyle(.segmented)
                        Toggle("Animate", isOn: $shouldAnimate)
                    }
                    .controlSize(.small)
                    #endif
                }
            }
        }
    }
}

extension NetworkTab.TrafficFlowSection {
    enum MapLocation: Hashable {
        case provider(DarkbloomProviderLocation)
        case request(DarkbloomRequestLocation)
    }
    
    enum FlowMapStyle: Hashable {
        case globe
        case flat
        
        var displayName: String {
            switch self {
                case .globe: "3D"
                case .flat: "2D"
            }
        }
        
        var mapStyle: MapStyle {
            switch self {
                case .globe: MapStyle.imagery(elevation: .realistic)
                case .flat: MapStyle.imagery(elevation: .flat)
            }
        }
    }
    
    struct TrafficFlowGraph: View {
        @Environment(APIDataController.self) private var dataController
        
        private static let globeDistance: CLLocationDistance = 30_000_000
        private static let globeSpinDegreesPerSecond: CLLocationDegrees = 8
        
        @State private var globalLatitude: CLLocationDegrees = 45
        @State private var globeLongitude: CLLocationDegrees = 0
        
        @State private var position: MapCameraPosition = .camera(
            MapCamera(
                centerCoordinate: CLLocationCoordinate2D(latitude: 45, longitude: 0),
                distance: Self.globeDistance,
                heading: 0,
                pitch: 0
            )
        )
        
        @State private var selection: MapLocation?
        
        @State private var animationTask: Task<Void, Never>?
        @State private var dashPhase: CGFloat = 0
        
        @Binding var shouldAnimate: Bool
        @Binding var mapStyle: FlowMapStyle
        
        private func startAnimations() {
            animationTask?.cancel()
            animationTask = Task {
                var lastFrameTime = Date.now
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(33)) // 30Hz
                    
                    let now = Date.now
                    let deltaTime = now.timeIntervalSince(lastFrameTime)
                    lastFrameTime = now
                    
                    dashPhase += 30.0 * deltaTime
                    
                    guard shouldAnimate else { continue }
                    
                    globeLongitude = Self.normalizedLongitude(globeLongitude + Self.globeSpinDegreesPerSecond * deltaTime)
                    position = .camera(globeCamera(centerLongitude: globeLongitude, deltaTime: deltaTime))
                }
            }
        }
        
        private func stopAnimations() {
            animationTask?.cancel()
            animationTask = nil
        }
        
        var body: some View {
            Map(position: $position, interactionModes: [.pan, .zoom], selection: $selection) {
                if let stats = dataController.stats {
                    ProviderLocationsMapContent(stats: stats)
                    RequestLocationsMapContent(stats: stats)
                    RequestFlowsMapContent(stats: stats, dashPhase: dashPhase)
                }
            }
            .mapStyle(mapStyle.mapStyle)
            .frame(height: 350)
            .clipShape(.rect(cornerRadius: 8))
            .onMapCameraChange(frequency: .continuous) { context in
                globalLatitude = context.camera.centerCoordinate.latitude
                if !shouldAnimate {
                    globeLongitude = Self.normalizedLongitude(context.camera.centerCoordinate.longitude)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        shouldAnimate = false
                    }
            )
            .onAppear {
                startAnimations()
            }
            .onDisappear {
                stopAnimations()
            }
        }

        @inlinable
        func moveToward(
            from current: CLLocationDegrees,
            to target: CLLocationDegrees,
            deltaTime: TimeInterval,
            speed: CLLocationDegrees
        ) -> CLLocationDegrees {
            let maxDelta = speed * deltaTime
            let delta = target - current

            if abs(delta) <= maxDelta {
                return target
            }

            return current + (delta > 0 ? maxDelta : -maxDelta)
        }
        
        private func globeCamera(centerLongitude: CLLocationDegrees, deltaTime: TimeInterval) -> MapCamera {
            let interpLat: CLLocationDegrees = moveToward(
                from: globalLatitude,
                to: 45.0,
                deltaTime: deltaTime,
                speed: 4.5
            )
            return MapCamera(
                centerCoordinate: CLLocationCoordinate2D(latitude: interpLat, longitude: centerLongitude),
                distance: Self.globeDistance,
                heading: 0,
                pitch: 0
            )
        }
        
        private static func normalizedLongitude(_ longitude: CLLocationDegrees) -> CLLocationDegrees {
            var longitude = longitude.truncatingRemainder(dividingBy: 360)
            if longitude > 180 {
                longitude -= 360
            } else if longitude < -180 {
                longitude += 360
            }
            return longitude
        }
    }
    
    private struct ProviderLocationsMapContent: MapContent {
        let stats: DarkbloomStats
        
        var body: some MapContent {
            let minMaxProviders = stats.providerLocations.minmax(byValue: \.providers)
            let minProviders = max(0, minMaxProviders?.min ?? 0)
            let maxProviders = max(1, minMaxProviders?.max ?? 1)
            
            ForEach(stats.providerLocations, id: \.key) { location in
                ProviderLocationAnnotation(
                    minProviders: minProviders,
                    maxProviders: maxProviders,
                    location: location
                )
            }
        }
    }
    
    private struct ProviderLocationAnnotation: MapContent {
        let minProviders: Int
        let maxProviders: Int
        
        let location: DarkbloomProviderLocation
        
        private var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )
        }
        
        private func t() -> CGFloat {
            guard maxProviders > minProviders else { return 0 }
            return CGFloat(location.providers - minProviders) / CGFloat(maxProviders - minProviders)
        }
        
        var body: some MapContent {
            let size: CGFloat = CGFloat.lerp(a: 12, b: 20, t: t().clamp01())
            
            Annotation(
                coordinate: coordinate,
                content: {
                    RoundedRectangle(cornerRadius: 6)
                        .rotation(.degrees(45))
                        .fill(Color.accent)
                        .strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
                        .frame(width: size, height: size)
                        .shadow(color: Color.accent, radius: 8)
                        .shadow(color: Color.accent.opacity(0.5), radius: 32)
                },
                label: {
                    VStack(alignment: .leading) {
                        Text("\(location.city), \(location.regionCode), \(location.countryCode)").bold()
                        Text("\(location.providers) providers")
                    }
                }
            )
            .mapItemDetailSelectionAccessory(.callout(.full))
            .tag(MapLocation.provider(location))
        }
    }
    
    private struct RequestLocationsMapContent: MapContent {
        let stats: DarkbloomStats
        
        var body: some MapContent {
            let minMaxRequests = stats.requestLocations.minmax(byValue: \.providers)
            let minRequests = max(0, minMaxRequests?.min ?? 0)
            let maxRequests = max(1, minMaxRequests?.max ?? 1)
            
            ForEach(stats.requestLocations, id: \.key) { location in
                RequestLocationAnnotation(
                    minRequests: minRequests,
                    maxRequests: maxRequests,
                    location: location
                )
            }
        }
    }
    
    private struct RequestLocationAnnotation: MapContent {
        let minRequests: Int
        let maxRequests: Int
        
        let location: DarkbloomRequestLocation
        
        private var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )
        }
        
        private func t() -> CGFloat {
            guard maxRequests > minRequests else { return 0.5 }
            return CGFloat(location.requests - minRequests) / CGFloat(maxRequests - minRequests)
        }
        
        var body: some MapContent {
            let size: CGFloat = CGFloat.lerp(a: 8, b: 16, t: t().clamp01())
            
            Annotation(
                coordinate: coordinate,
                content: {
                    Circle()
                        .fill(Color.green)
                        .strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
                        .frame(width: size, height: size)
                        .shadow(color: Color.green, radius: 8)
                        .shadow(color: Color.green.opacity(0.5), radius: 32)
                },
                label: {
                    VStack(alignment: .leading) {
                        Text("\(location.city), \(location.regionCode), \(location.countryCode)").bold()
                        Text("\(location.providers) requests")
                    }
                }
            )
            .mapItemDetailSelectionAccessory(.callout(.full))
            .tag(MapLocation.request(location))
        }
    }
    
    private struct RequestFlowsMapContent: MapContent {
        let stats: DarkbloomStats
        let dashPhase: CGFloat
        
        var body: some MapContent {
            ForEach(stats.requestFlows, id: \.key) { flow in
                RequestFlowPolyline(flow: flow, dashPhase: dashPhase)
            }
        }
    }
    
    private struct RequestFlowPolyline: MapContent {
        let flow: DarkbloomRequestFlow
        let dashPhase: CGFloat
        
        private var coordinates: [CLLocationCoordinate2D] {
            [
                CLLocationCoordinate2D(
                    latitude: flow.from.latitude,
                    longitude: flow.from.longitude
                ),
                CLLocationCoordinate2D(
                    latitude: flow.to.latitude,
                    longitude: flow.to.longitude
                ),
            ]
        }
        
        private var directionalColor: Color {
            switch flow.from.kind {
                case .provider: Color.green
                case .consumer: Color.accent
            }
        }
        
        var body: some MapContent {
            MapPolyline(coordinates: coordinates, contourStyle: .geodesic)
                .stroke(
                    directionalColor,
                    style: StrokeStyle(
                        lineWidth: 2,
                        dash: [2, 10],
                        dashPhase: dashPhase
                    )
                )
        }
    }
}

#Preview {
    @Previewable @State var viewModel = APIDataController()
    
    Form {
        if let stats = viewModel.stats {
            NetworkTab.TrafficFlowSection(stats: stats)
        }
    }
    .formStyle(.grouped)
    .environment(viewModel)
}
