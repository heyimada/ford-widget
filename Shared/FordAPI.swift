import Foundation
import Security

struct GarageVehicle {
    var vin: String
    var name: String
    var imageURL: URL?
}

/// Wire details are copied from the ha-fordpass bridge; the older Ford headers break the token call.
enum FordAPI {
    private static let foundational = "https://api.foundational.ford.com/api"
    private static let garageURL = "https://api.vehicle.ford.com/api/fpcpl-user-garage-service/v1/user/garage"
    private static let autonomicAccounts = "https://accounts.autonomic.ai/v1"
    private static let autonomic = "https://api.autonomic.ai/v1"
    private static let autonomicSocket = "wss://api.autonomic.ai/v1beta"
    private static let socketDeadline: Duration = .seconds(10)

    private static func send(
        _ url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil
    ) async throws -> (data: Data, status: Int) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("okhttp/4.12.0", forHTTPHeaderField: "User-Agent")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private static func region(of session: FordSession) -> FordRegion {
        FordRegion.byId[session.regionId] ?? .fallback
    }

    // MARK: sign-in (app only)

    static func newPKCE() -> (verifier: String, challenge: String) {
        var bytes = [UInt8](repeating: 0, count: 96)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return (verifier, pkceChallenge(verifier: verifier))
    }

    static func signIn(code: String, verifier: String, region: FordRegion, now: Date = Date()) async throws -> FordSession {
        let form = formEncode([
            ("client_id", FordRegion.clientId),
            ("scope", "\(FordRegion.clientId) openid"),
            ("redirect_uri", FordRegion.redirectURI),
            ("grant_type", "authorization_code"),
            ("resource", ""),
            ("code", code),
            ("code_verifier", verifier),
        ])
        let b2c = try await send(region.tokenURL, method: "POST",
                                 headers: ["Content-Type": "application/x-www-form-urlencoded"], body: Data(form.utf8))
        let idp = try parseTokenResponse(data: b2c.data, status: b2c.status)

        let final = try await send(
            URL(string: "\(foundational)/token/v2/cat-with-b2c-access-token")!, method: "POST",
            headers: ["Content-Type": "application/json", "Application-Id": region.appId],
            body: try json(["idpToken": idp.accessToken]))
        let tokens = try parseTokenResponse(data: final.data, status: final.status)
        guard let refresh = tokens.refreshToken else { throw FordError.decoding("no refresh_token in token response") }
        return FordSession(regionId: region.id, accessToken: tokens.accessToken, refreshToken: refresh,
                           accessExpiresAt: now.addingTimeInterval(TimeInterval(tokens.expiresIn ?? 300)),
                           vin: nil, vehicleName: nil)
    }

    // MARK: Ford token refresh, garage and image (app only; the widget must never call these)

    static func refresh(_ session: FordSession, now: Date = Date()) async throws -> FordSession {
        let (data, status) = try await send(
            URL(string: "\(foundational)/token/v2/cat-with-refresh-token")!, method: "POST",
            headers: ["Content-Type": "application/json", "Application-Id": region(of: session).appId],
            body: try json(["refresh_token": session.refreshToken]))
        let tokens = try parseRefreshResponse(data: data, status: status)
        var renewed = session
        renewed.accessToken = tokens.accessToken
        renewed.refreshToken = tokens.refreshToken ?? session.refreshToken
        renewed.accessExpiresAt = now.addingTimeInterval(TimeInterval(tokens.expiresIn ?? 300))
        return renewed
    }

    static func freshSession(_ session: FordSession, now: Date = Date()) async throws -> FordSession {
        session.accessExpiresAt.timeIntervalSince(now) > 60 ? session : try await refresh(session, now: now)
    }

    static func firstVehicle(_ session: FordSession) async throws -> GarageVehicle {
        let region = region(of: session)
        let (data, status) = try await send(
            URL(string: garageURL)!,
            headers: ["Content-Type": "application/json", "auth-token": session.accessToken,
                      "Application-Id": region.appId, "countryCode": region.countryCode, "locale": region.locale])
        guard status == 200 || status == 207 else {
            throw FordError.http(status, String(decoding: data, as: UTF8.self))
        }
        guard let vehicles = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = vehicles.first, let vin = first["vin"] as? String else { throw FordError.noVehicle }
        let profile = first["profile"] as? [String: Any]
        let nickName = (first["nickName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let model = profile?["model"] as? String ?? "Ford"
        return GarageVehicle(vin: vin, name: nickName ?? model,
                             imageURL: (profile?["vehicleImage"] as? String).flatMap(URL.init(string:)))
    }

    static func downloadCarImage(from url: URL, session: FordSession) async throws {
        let (data, status) = try await send(
            url, headers: ["auth-token": session.accessToken, "Application-Id": region(of: session).appId])
        guard status == 200 else { throw FordError.http(status, String(decoding: data.prefix(200), as: UTF8.self)) }
        CarImage.save(data)
    }

    // MARK: Autonomic telemetry (app and widget)

    /// Exchanged from the Ford refresh token on every run and kept in memory only.
    static func autonomicToken(refreshToken: String) async throws -> String {
        let form = formEncode([
            ("subject_token", refreshToken),
            ("subject_issuer", "fordpass"),
            ("client_id", "fordpass-prod"),
            ("grant_type", "urn:ietf:params:oauth:grant-type:token-exchange"),
            ("subject_token_type", "urn:ietf:params:oauth:token-type:jwt"),
        ])
        let (data, status) = try await send(
            URL(string: "\(autonomicAccounts)/auth/oidc/token")!, method: "POST",
            headers: ["Accept": "*/*", "Content-Type": "application/x-www-form-urlencoded"], body: Data(form.utf8))
        if status == 401 {
            throw FordError.reauthRequired("HTTP 401: \(String(decoding: data, as: UTF8.self))")
        }
        return try parseTokenResponse(data: data, status: status).accessToken
    }

    static func snapshot(for session: FordSession, token: String? = nil, now: Date = Date()) async throws -> VehicleSnapshot {
        guard let vin = session.vin else { throw FordError.noVehicle }
        let bearer: String
        if let token { bearer = token } else { bearer = try await autonomicToken(refreshToken: session.refreshToken) }
        let metrics = try await telemetry(vin: vin, token: bearer)
        return VehicleSnapshot.parse(metrics: metrics, vin: vin, name: session.vehicleName ?? "Ford", fetchedAt: now)
    }

    /// Websocket first, merging frames until the four displayed metrics are in or 10 s pass. The `:query` POST
    /// variant is deliberately not used: it answers 502 from Germany.
    static func telemetry(vin: String, token: String) async throws -> [String: Any] {
        let streamed = await streamMetrics(vin: vin, token: token)
        if isComplete(streamed) { return streamed }
        do {
            var polled = try await pollMetrics(vin: vin, token: token)
            mergeMetrics(into: &polled, frame: ["metrics": streamed])
            return polled
        } catch {
            if streamed.isEmpty { throw error }
            return streamed
        }
    }

    private static func pollMetrics(vin: String, token: String) async throws -> [String: Any] {
        let url = URL(string: "\(autonomic)/telemetry/sources/fordpass/vehicles/\(vin)?lrdt=01-01-1970%2000:00:00")!
        let (data, status) = try await send(url, headers: ["Content-Type": "application/json", "Authorization": "Bearer \(token)"])
        guard status == 200 else { throw FordError.http(status, String(decoding: data, as: UTF8.self)) }
        guard let metrics = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["metrics"] as? [String: Any],
              !metrics.isEmpty else { throw FordError.decoding("the car sent no telemetry") }
        return metrics
    }

    private static func streamMetrics(vin: String, token: String) async -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(autonomicSocket)/telemetry/sources/fordpass/vehicles/\(vin)/ws")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("okhttp/4.12.0", forHTTPHeaderField: "User-Agent")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.resume()
        // receive() has no timeout of its own: closing the socket at the deadline makes it throw.
        let deadline = Task {
            try? await Task.sleep(for: socketDeadline)
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer {
            deadline.cancel()
            socket.cancel(with: .normalClosure, reason: nil)
        }

        var metrics: [String: Any] = [:]
        while let message = try? await socket.receive() {
            let raw: Data
            switch message {
            case .string(let text): raw = Data(text.utf8)
            case .data(let data): raw = data
            @unknown default: continue
            }
            guard let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { continue }
            switch WSMessage.classify(object) {
            case .data(let frame):
                mergeMetrics(into: &metrics, frame: frame)
                if isComplete(metrics) { return metrics }
            case .error: return metrics
            case .status, .other: continue
            }
        }
        return metrics
    }

    static func requestStatusRefresh(vin: String, token: String) async throws {
        let body = try json(["properties": [String: Any](), "tags": [String: Any](), "type": "statusRefresh", "wakeUp": true])
        let (data, status) = try await send(
            URL(string: "\(autonomic)/command/vehicles/\(vin)/commands")!, method: "POST",
            headers: ["Content-Type": "application/json", "Authorization": "Bearer \(token)"], body: body)
        guard (200...205).contains(status) else { throw FordError.http(status, String(decoding: data, as: UTF8.self)) }
    }
}
