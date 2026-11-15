import SwiftUI
import WidgetKit

struct VehicleEntry: TimelineEntry {
    let date: Date
    let snapshot: VehicleSnapshot?
    let carImage: Image?
    let isStale: Bool
}

struct VehicleProvider: TimelineProvider {
    private static let reloadInterval: TimeInterval = 30 * 60
    private static let fetchDeadline: Duration = .seconds(25)

    func placeholder(in context: Context) -> VehicleEntry { sample() }

    func getSnapshot(in context: Context, completion: @escaping (VehicleEntry) -> Void) {
        if context.isPreview {
            completion(sample())
        } else {
            completion(VehicleEntry(date: Date(), snapshot: SnapshotStore.latest(), carImage: CarImage.load(), isStale: false))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<VehicleEntry>) -> Void) {
        Task {
            let now = Date()
            let entry = await Self.liveEntry(now: now)
            // Extra entries keep the "… ago" text advancing when WidgetKit postpones the reload.
            let entries = (0..<24).map { step in
                VehicleEntry(date: now.addingTimeInterval(TimeInterval(step) * 15 * 60), snapshot: entry.snapshot,
                             carImage: entry.carImage, isStale: entry.isStale)
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.reloadInterval))))
        }
    }

    private func sample() -> VehicleEntry {
        let now = Date()
        return VehicleEntry(date: now, snapshot: .sample(now: now), carImage: CarImage.load(), isStale: false)
    }

    /// The widget only reads the Keychain session; any failure falls back to the cached snapshot.
    private static func liveEntry(now: Date) async -> VehicleEntry {
        let image = CarImage.load()
        let session: FordSession
        switch SessionStore.read() {
        case .found(let found): session = found
        case .signedOut: return VehicleEntry(date: now, snapshot: nil, carImage: nil, isStale: false)
        case .unreadable: return VehicleEntry(date: now, snapshot: SnapshotStore.latest(), carImage: image, isStale: true)
        }
        do {
            let live = try await withThrowingTaskGroup(of: VehicleSnapshot.self) { group in
                group.addTask { try await FordAPI.snapshot(for: session, now: now) }
                group.addTask {
                    try await Task.sleep(for: fetchDeadline)
                    throw CancellationError()
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            if case .found = SessionStore.read() { SnapshotStore.save(live, as: .widget) }
            return VehicleEntry(date: now, snapshot: live, carImage: image, isStale: false)
        } catch {
            return VehicleEntry(date: now, snapshot: SnapshotStore.latest(), carImage: image, isStale: true)
        }
    }
}

struct FordWidgetView: View {
    let entry: VehicleEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VehicleCardView(snapshot: snapshot, carImage: entry.carImage, now: entry.date)
                .overlay(alignment: .topLeading) {
                    if entry.isStale {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange)
                            .padding(.top, 38)
                            .padding(.leading, 34)
                            .accessibilityLabel("Could not refresh")
                    }
                }
        } else {
            Text("Open the app to sign in")
                .font(.headline)
                .foregroundStyle(CardStyle.gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@main
struct FordCarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FordCarWidget", provider: VehicleProvider()) { entry in
            FordWidgetView(entry: entry)
                .containerBackground(for: .widget) { CardStyle.background }
        }
        .configurationDisplayName("My Ford")
        .description("Fuel level, range and mileage of your Ford.")
        .supportedFamilies([.systemMedium])
    }
}
