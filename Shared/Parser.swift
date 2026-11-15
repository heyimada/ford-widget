import Foundation

extension VehicleSnapshot {
    static func parse(metrics: [String: Any], vin: String, name: String, fetchedAt: Date) -> VehicleSnapshot {
        VehicleSnapshot(vin: vin, name: name, fuelPercent: nil, rangeKm: nil, odometerKm: nil,
                        lock: .unknown, updatedAt: nil, fetchedAt: fetchedAt)
    }
}

func mergeMetrics(into metrics: inout [String: Any], frame: [String: Any]) {}

func isComplete(_ metrics: [String: Any]) -> Bool { false }

enum WSMessage {
    case data([String: Any])
    case status(Int)
    case error(String)
    case other

    static func classify(_ json: [String: Any]) -> WSMessage { .other }
}
