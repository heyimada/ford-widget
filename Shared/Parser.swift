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
            updatedAt: updatedAt, fetchedAt: fetchedAt, details: VehicleDetails.parse(metrics: metrics))
    }
}

// MARK: details

private func bool(_ value: Any?) -> Bool? {
    guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
    return n.boolValue
}

private func coordinate(_ value: Any?) -> Double? {
    let d = number(value) ?? (value as? String).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard let d, d.isFinite else { return nil }
    return d
}

/// Metrics such as doorStatus are arrays of entries; a lone object is tolerated.
private func entries(_ metric: Any?) -> [[String: Any]] {
    if let many = metric as? [[String: Any]] { return many }
    if let one = metric as? [String: Any] { return [one] }
    return []
}

private func openState(door value: Any?) -> OpenState {
    switch (value as? String)?.uppercased() {
    case "CLOSED": return .closed
    case "OPEN", "AJAR": return .open
    default: return .unknown
    }
}

private func openState(window entry: [String: Any]) -> OpenState {
    let range = (entry["value"] as? [String: Any])?["doubleRange"] as? [String: Any]
    guard let upper = number(range?["upperBound"]) else { return .unknown }
    return upper > 0 ? .open : .closed
}

private func label(_ key: String?, side: String?) -> String {
    let side = side?.uppercased()
    let sideName = side == "DRIVER" ? "Driver" : side == "PASSENGER" ? "Passenger" : nil
    switch key?.uppercased() {
    case "FRONT_LEFT": return "Front left"
    case "FRONT_RIGHT": return "Front right"
    case "REAR_LEFT": return "Rear left"
    case "REAR_RIGHT": return "Rear right"
    case "TAILGATE": return "Tailgate"
    case "INNER_TAILGATE": return "Inner tailgate"
    case "UNSPECIFIED_FRONT": return sideName ?? "Front"
    case "UNSPECIFIED_REAR": return sideName.map { "Rear \($0.lowercased())" } ?? "Rear"
    case let other?: return other.replacingOccurrences(of: "_", with: " ").capitalized
    case nil: return "Unknown"
    }
}

private func openings(_ metric: Any?, kind: String, state: ([String: Any]) -> OpenState) -> [Opening] {
    entries(metric).map { entry in
        let key = entry[kind] as? String
        let side = entry["vehicleSide"] as? String
        let role = entry["vehicleOccupantRole"] as? String
        return Opening(id: [key, side, role].map { $0 ?? "" }.joined(separator: "/"),
                       position: label(key, side: side), state: state(entry))
    }
}

private func wheel(_ name: Any?) -> Wheel {
    switch (name as? String)?.uppercased() {
    case "FRONT_LEFT": return .frontLeft
    case "FRONT_RIGHT": return .frontRight
    case "REAR_LEFT": return .rearLeft
    case "REAR_RIGHT": return .rearRight
    default: return .other
    }
}

private func parseTires(_ metrics: [String: Any]) -> [Tire] {
    var pressure: [Wheel: [String: Any]] = [:]
    var status: [Wheel: TireStatus] = [:]
    for entry in entries(metrics["tirePressure"]) { pressure[wheel(entry["vehicleWheel"])] = entry }
    for entry in entries(metrics["tirePressureStatus"]) {
        let which = wheel(entry["vehicleWheel"])
        switch (entry["value"] as? String)?.uppercased() {
        case "NORMAL": status[which] = .normal
        case let s? where s.contains("LOW"): status[which] = .low
        default: status[which] = TireStatus.unknown
        }
    }
    return [Wheel.frontLeft, .frontRight, .rearLeft, .rearRight, .other].compactMap { which in
        guard pressure[which] != nil || status[which] != nil else { return nil }
        let entry = pressure[which]
        return Tire(wheel: which, pressureKPa: number(entry?["value"]),
                    placardKPa: number(entry?["wheelPlacardFront"]) ?? number(entry?["wheelPlacardRear"]),
                    status: status[which] ?? .unknown)
    }
}

private func parseLocation(_ metric: Any?) -> CarLocation? {
    guard let position = metric as? [String: Any],
          let point = (position["value"] as? [String: Any])?["location"] as? [String: Any],
          let lat = coordinate(point["lat"]), let lon = coordinate(point["lon"]) else { return nil }
    return CarLocation(latitude: lat, longitude: lon,
                       reportedAt: (position["updateTime"] as? String).flatMap(parseISO8601))
}

extension VehicleDetails {
    static func parse(metrics: [String: Any]) -> VehicleDetails {
        let alarm: AlarmState
        switch (metricValue(metrics, "alarmStatus") as? String)?.uppercased() {
        case "ARMED": alarm = .armed
        case "DISARMED": alarm = .disarmed
        case let s? where s.contains("TRIGGER"): alarm = .triggered
        default: alarm = .unknown
        }

        let ignition: IgnitionState
        switch (metricValue(metrics, "ignitionStatus") as? String)?.uppercased() {
        case "OFF": ignition = .off
        case "RUN", "ON", "START", "ACCESSORY": ignition = .on
        default: ignition = .unknown
        }

        var remoteStartEndsAt: Date?
        if let timer = metrics["remoteStartCountdownTimer"] as? [String: Any],
           let seconds = number(timer["value"]), seconds > 0, seconds < 1e9,
           let updated = (timer["updateTime"] as? String).flatMap(parseISO8601) {
            remoteStartEndsAt = updated.addingTimeInterval(seconds)
        }

        let indicators = metrics["indicators"] as? [String: Any] ?? [:]
        let warnings = indicators.compactMap { key, entry in
            bool((entry as? [String: Any])?["value"]) == true ? key : nil
        }.sorted()

        return VehicleDetails(
            doors: openings(metrics["doorStatus"], kind: "vehicleDoor") { openState(door: $0["value"]) },
            windows: openings(metrics["windowStatus"], kind: "vehicleWindow", state: openState(window:)),
            hood: openState(door: metricValue(metrics, "hoodStatus")),
            alarm: alarm, ignition: ignition, remoteStartEndsAt: remoteStartEndsAt,
            tires: parseTires(metrics),
            oilLifePercent: roundedInt(metricValue(metrics, "oilLifeRemaining")),
            batteryPercent: roundedInt(metricValue(metrics, "batteryStateOfCharge")),
            batteryVoltage: number(metricValue(metrics, "batteryVoltage")),
            outsideTemperatureC: number(metricValue(metrics, "outsideTemperature")),
            coolantTemperatureC: number(metricValue(metrics, "engineCoolantTemp")),
            location: parseLocation(metrics["position"]),
            warnings: warnings)
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
