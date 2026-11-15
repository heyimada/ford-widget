import Foundation

enum LockState: String, Codable {
    case locked, partlyLocked, unlocked, unknown
}

struct VehicleSnapshot: Codable, Equatable {
    var vin: String
    var name: String
    var fuelPercent: Int?
    var rangeKm: Int?
    var odometerKm: Int?
    var lock: LockState
    var updatedAt: Date?
    var fetchedAt: Date
    /// Optional so snapshot files written before the app grew its detail screens still decode; the widget ignores it.
    var details: VehicleDetails? = nil
}

enum OpenState: String, Codable, Equatable {
    case open, closed, unknown
}

struct Opening: Codable, Equatable {
    /// Door/window name + side + occupant role: the data has two `UNSPECIFIED_FRONT` doors told apart only by those.
    var id: String
    var position: String
    var state: OpenState
}

enum AlarmState: String, Codable, Equatable {
    case armed, disarmed, triggered, unknown
}

enum IgnitionState: String, Codable, Equatable {
    case off, on, unknown
}

enum Wheel: String, Codable, Equatable {
    case frontLeft, frontRight, rearLeft, rearRight, other
}

enum TireStatus: String, Codable, Equatable {
    case normal, low, unknown
}

struct Tire: Codable, Equatable {
    var wheel: Wheel
    var pressureKPa: Double?
    var placardKPa: Double?
    var status: TireStatus
}

struct CarLocation: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var reportedAt: Date?
}

/// Everything the detail screens show. Absent data is nil, empty or unknown, never "closed" or "normal".
struct VehicleDetails: Codable, Equatable {
    var doors: [Opening]
    var windows: [Opening]
    var hood: OpenState
    var alarm: AlarmState
    var ignition: IgnitionState
    var remoteStartEndsAt: Date?
    var tires: [Tire]
    var oilLifePercent: Int?
    var batteryPercent: Int?
    var batteryVoltage: Double?
    var outsideTemperatureC: Double?
    var coolantTemperatureC: Double?
    var location: CarLocation?
    /// Keys of the `indicators` that are lit, sorted.
    var warnings: [String]
}

struct VehicleProfile: Codable, Equatable {
    var vin: String
    var name: String
    var model: String?
    var year: Int?
    var color: String?
    var licensePlate: String?
    var imageURL: URL?
    /// Capability keys the garage marks "Display".
    var capabilities: Set<String>
}

enum CarCommand: String, CaseIterable, Sendable {
    case lock, unlock, remoteStart, cancelRemoteStart, statusRefresh
}

enum CommandPhase: Equatable, Sendable {
    case sending, waiting, succeeded, failed(String), expired
}

struct FordSession: Codable {
    var regionId: String
    var accessToken: String
    var refreshToken: String
    var accessExpiresAt: Date
    var vin: String?
    var vehicleName: String?
}

struct TokenResponse: Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int?
}

enum FordError: Error, CustomStringConvertible, LocalizedError {
    case reauthRequired(String)
    case http(Int, String)
    case noVehicle
    case decoding(String)

    var description: String {
        switch self {
        case .reauthRequired(let detail): return detail
        case .http(let status, let body): return "HTTP \(status): \(body)"
        case .noVehicle: return "No vehicle found in your Ford account."
        case .decoding(let detail): return "Unexpected response: \(detail)"
        }
    }

    var errorDescription: String? { description }
}
