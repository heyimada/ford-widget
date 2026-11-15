import Foundation
import CryptoKit

private func bodyText(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Ford answers token calls with varying HTTP statuses, so success is decided by `access_token`, not the status.
func parseTokenResponse(data: Data, status: Int) throws -> TokenResponse {
    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    if let access = object?["access_token"] as? String, !access.isEmpty {
        return TokenResponse(accessToken: access,
                             refreshToken: object?["refresh_token"] as? String,
                             expiresIn: (object?["expires_in"] as? NSNumber)?.intValue)
    }
    let reason = ["message", "error_description", "error"].lazy
        .compactMap { object?[$0] as? String }.first
    throw FordError.http(status, reason ?? bodyText(data))
}

func parseRefreshResponse(data: Data, status: Int) throws -> TokenResponse {
    switch status {
    case 400, 401: throw FordError.reauthRequired("HTTP \(status): \(bodyText(data))")
    case 200: return try parseTokenResponse(data: data, status: status)
    default: throw FordError.http(status, bodyText(data))
    }
}

private let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

// Spaces become "+" like aiohttp's form encoder; everything else outside the unreserved set is percent-encoded.
func formEncode(_ pairs: [(String, String)]) -> String {
    func encode(_ s: String) -> String {
        (s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s)
    }
    return pairs.map { key, value in
        encode(key) + "=" + encode(value).replacingOccurrences(of: "%20", with: "+")
    }.joined(separator: "&")
}

func pkceChallenge(verifier: String) -> String {
    Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func nonEmpty(_ value: Any?) -> String? {
    (value as? String).flatMap { $0.isEmpty ? nil : $0 }
}

/// First vehicle of the garage response; HTTP status handling stays with the caller.
func parseGarage(_ data: Data) throws -> VehicleProfile {
    guard let vehicles = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          let first = vehicles.first, let vin = nonEmpty(first["vin"]) else { throw FordError.noVehicle }
    let profile = first["profile"] as? [String: Any]
    let model = nonEmpty(profile?["model"])
    let year = (profile?["year"] as? NSNumber).map(\.intValue) ?? (profile?["year"] as? String).flatMap { Int($0) }
    let capabilities = (first["capabilities"] as? [String: Any] ?? [:]).filter { $0.value as? String == "Display" }.keys
    return VehicleProfile(
        vin: vin,
        name: nonEmpty(first["nickName"]) ?? model ?? "Ford",
        model: model, year: year,
        color: nonEmpty(first["color"]) ?? nonEmpty(profile?["paintDescription"]),
        licensePlate: nonEmpty(first["licensePlate"]),
        imageURL: nonEmpty(profile?["vehicleImage"]).flatMap(URL.init(string:)),
        capabilities: Set(capabilities))
}

/// The command endpoint answers with the id the car's later state reports carry.
func parseCommandId(_ data: Data) throws -> String {
    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    guard let id = ["id", "commandId", "correlationId"].lazy.compactMap({ nonEmpty(object?[$0]) }).first else {
        throw FordError.decoding("no command id in the response")
    }
    return id
}

/// Where our command stands in the telemetry `states`. A state entry with another commandId is an older command's.
func commandPhase(states: [String: Any], command: CarCommand, commandId: String) -> CommandPhase {
    // The integration flattens a nested `commands` object to the root; the plain key wins over the "Command" suffix.
    var all = states
    if let nested = states["commands"] as? [String: Any] { all.merge(nested) { root, _ in root } }
    guard let state = (all[command.rawValue] ?? all[command.rawValue + "Command"]) as? [String: Any],
          state["commandId"] as? String == commandId,
          let value = state["value"] as? [String: Any],
          let toState = (value["toState"] as? String)?.uppercased() else { return .waiting }
    switch toState {
    case "SUCCESS", "COMMAND_SUCCEEDED_ON_DEVICE":
        return .succeeded
    case "FAILURE", "COMMAND_FAILED_ON_DEVICE":
        let failure = ((value["data"] as? [String: Any])?["commandError"] as? [String: Any])?["commandExecutionFailure"] as? [String: Any]
        return .failed(nonEmpty(failure?["oemErrorContext"]) ?? "Failed")
    case "EXPIRED":
        return .expired
    default:
        return .waiting
    }
}
