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
