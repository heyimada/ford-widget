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
