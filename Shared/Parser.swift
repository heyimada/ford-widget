import Foundation

private let requiredMetrics = ["fuelLevel", "fuelRange", "odometer", "doorLockStatus"]

private func number(_ value: Any?) -> Double? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n.doubleValue
}

// Int(Double) traps outside the Int range, so a hostile or corrupt value must not reach it.
private func roundedInt(_ value: Any?) -> Int? {
    guard let d = number(value), d.isFinite, abs(d) < 1e15 else { return nil }
    return Int(d.rounded(.toNearestOrEven))
}

private func metricValue(_ metrics: [String: Any], _ key: String) -> Any? {
    (metrics[key] as? [String: Any])?["value"]
}

private func parseISO8601(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
}

// doorLockStatus is an array whose entries each carry their own updateTime.
private func updateTimes(of metric: Any?) -> [Date] {
    let objects: [[String: Any]]
    if let one = metric as? [String: Any] {
        objects = [one]
    } else if let many = metric as? [[String: Any]] {
        objects = many
    } else {
        return []
    }
    return objects.compactMap { ($0["updateTime"] as? String).flatMap(parseISO8601) }
}

private func lockState(_ entries: [[String: Any]]) -> LockState {
    var required = entries.count
    guard required > 0 else { return .unknown }
    var locked = 0
    for entry in entries {
        let value = (entry["value"] as? String)?.uppercased()
        if value == "LOCKED" || value == "DOUBLE_LOCKED" {
            if (entry["vehicleDoor"] as? String)?.uppercased() == "ALL_DOORS" { return .locked }
            locked += 1
        } else if value == "UNKNOWN" || (entry["tags"] as? [String: Any])?["DOOR_LATCH_TYPE"] as? String == "MECHANICAL" {
            required -= 1
        }
    }
    if locked == 0 { return .unlocked }
    return locked >= required ? .locked : .partlyLocked
}

extension VehicleSnapshot {
    static func parse(metrics: [String: Any], vin: String, name: String, fetchedAt: Date) -> VehicleSnapshot {
        let updatedAt = requiredMetrics.flatMap { updateTimes(of: metrics[$0]) }.max()
        return VehicleSnapshot(
            vin: vin, name: name,
            fuelPercent: roundedInt(metricValue(metrics, "fuelLevel")),
            rangeKm: roundedInt(metricValue(metrics, "fuelRange")),
            odometerKm: roundedInt(metricValue(metrics, "odometer")),
            lock: lockState(metrics["doorLockStatus"] as? [[String: Any]] ?? []),
            updatedAt: updatedAt, fetchedAt: fetchedAt)
    }
}

/// `frame` is the `_data` object of a websocket message; later frames win per metric key.
func mergeMetrics(into metrics: inout [String: Any], frame: [String: Any]) {
    guard let incoming = frame["metrics"] as? [String: Any] else { return }
    metrics.merge(incoming) { _, new in new }
}

func isComplete(_ metrics: [String: Any]) -> Bool {
    requiredMetrics.allSatisfy { metrics[$0] != nil }
}

enum WSMessage {
    case data([String: Any])
    case status(Int)
    case error(String)
    case other

    // Same precedence as the integration: _httpStatus, then _error, then _data.
    static func classify(_ json: [String: Any]) -> WSMessage {
        if let raw = json["_httpStatus"] {
            if let n = raw as? NSNumber { return .status(n.intValue) }
            if let s = raw as? String, let n = Int(s) { return .status(n) }
            return .other
        }
        if let err = json["_error"] {
            if let message = (err as? [String: Any])?["message"] as? String { return .error(message) }
            if let text = err as? String { return .error(text) }
            if JSONSerialization.isValidJSONObject(err),
               let d = try? JSONSerialization.data(withJSONObject: err, options: [.sortedKeys]),
               let text = String(data: d, encoding: .utf8) {
                return .error(text)
            }
            return .error("\(err)")
        }
        if let frame = json["_data"] as? [String: Any] { return .data(frame) }
        return .other
    }
}
