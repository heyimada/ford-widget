import CoreLocation
import MapKit
import SwiftUI

struct LocationView: View {
    @Bindable var model: AppModel
    @Environment(\.locale) private var locale
    @State private var position = MapCameraPosition.automatic
    @State private var address: String?

    private var location: CarLocation? { model.snapshot?.details?.location }

    var body: some View {
        Group {
            if let location {
                map(location)
            } else {
                ContentUnavailableView("No location", systemImage: "location.slash",
                                       description: Text("The car has not reported a position yet."))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CarToolbar(model: model) }
    }

    private func map(_ location: CarLocation) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        return GeometryReader { geo in
            mapContent(location, coordinate: coordinate, fold: geo.reservedRegions(kind: .division).first(where: \.isActive)?.frame)
        }
    }

    /// When the device is partially folded, the card stays left of the fold so its button never sits on the hinge.
    private func mapContent(_ location: CarLocation, coordinate: CLLocationCoordinate2D, fold: CGRect?) -> some View {
        Map(position: $position) {
            Annotation(model.snapshot?.name ?? "Car", coordinate: coordinate) {
                Image(systemName: "car.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.tint, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(radius: 3)
            }
        }
        .mapStyle(.standard)
        .safeAreaInset(edge: .bottom) {
            infoCard(location, coordinate: coordinate, maxWidth: min(560, (fold?.minX ?? .infinity) - 32))
                .frame(maxWidth: .infinity, alignment: fold == nil ? .center : .leading)
        }
        .task(id: coordinate.hashValueKey) {
            position = .camera(MapCamera(centerCoordinate: coordinate, distance: 1200))
            address = await Self.address(for: coordinate)
        }
    }

    private func infoCard(_ location: CarLocation, coordinate: CLLocationCoordinate2D, maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(address ?? String(localized: "Looking up address…")).font(.headline)
                if let reported = location.reportedAt {
                    Text("Reported \(Format.ago(reported, locale: locale))").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Button { Self.openDirections(to: coordinate, name: model.snapshot?.name) } label: {
                Label("Directions", systemImage: "figure.walk").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private static func address(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return nil }
        return item.address?.shortAddress ?? item.address?.fullAddress
    }

    private static func openDirections(to coordinate: CLLocationCoordinate2D, name: String?) {
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

private extension CLLocationCoordinate2D {
    /// `task(id:)` needs Equatable; a coordinate is not.
    var hashValueKey: String { "\(latitude),\(longitude)" }
}
