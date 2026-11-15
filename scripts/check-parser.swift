import Foundation

nonisolated(unsafe) var failures: [String] = []
nonisolated(unsafe) var assertionCount = 0
nonisolated(unsafe) var fixtureRoot = ""

func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    assertionCount += 1
    if actual != expected { failures.append("FAIL \(message): expected \(expected), got \(actual)") }
}

func expectMillis(_ date: Date?, _ expected: Int?, _ message: String) {
    expect(date.map { Int(($0.timeIntervalSince1970 * 1000).rounded()) }, expected, message)
}

func data(_ name: String) -> Data {
    guard let d = FileManager.default.contents(atPath: "\(fixtureRoot)/\(name)") else {
        fatalError("missing fixture \(name)")
    }
    return d
}

func json(_ name: String) -> [String: Any] {
    (try! JSONSerialization.jsonObject(with: data(name))) as! [String: Any]
}

func metrics(of name: String) -> [String: Any] {
    json(name)["metrics"] as? [String: Any] ?? [:]
}

func parse(_ metrics: [String: Any]) -> VehicleSnapshot {
    VehicleSnapshot.parse(metrics: metrics, vin: "VIN1", name: "Focus ST", fetchedAt: Date(timeIntervalSince1970: 0))
}

func frame(_ name: String) -> [String: Any] {
    if case .data(let d) = WSMessage.classify(json(name)) { return d }
    failures.append("FAIL \(name) did not classify as .data")
    return [:]
}

enum Kind: Equatable { case data, status(Int), error(String), other }

func kind(_ name: String) -> Kind {
    switch WSMessage.classify(json(name)) {
    case .data: return .data
    case .status(let s): return .status(s)
    case .error(let e): return .error(e)
    case .other: return .other
    }
}

func errorText(_ body: () throws -> TokenResponse) -> String {
    do { return "no error, parsed \(try body())" } catch { return "\(error)" }
}

func errorCase(_ body: () throws -> TokenResponse) -> String {
    do { _ = try body(); return "none" } catch let e as FordError {
        switch e {
        case .reauthRequired: return "reauthRequired"
        case .http: return "http"
        case .noVehicle: return "noVehicle"
        case .decoding: return "decoding"
        }
    } catch { return "other" }
}

@main
struct CheckParser {
    static func main() {
        fixtureRoot = CommandLine.arguments[1]

        // 1. no metrics key
        let none = parse(metrics(of: "no-metrics.json"))
        expect(none.fuelPercent, nil, "1: no metrics -> fuelPercent nil")
        expect(none.rangeKm, nil, "1: no metrics -> rangeKm nil")
        expect(none.odometerKm, nil, "1: no metrics -> odometerKm nil")
        expect(none.lock, .unknown, "1: no metrics -> lock unknown")
        expectMillis(none.updatedAt, nil, "1: no metrics -> updatedAt nil")

        // 2, 4, 5, 6 on the sample
        let sample = parse(metrics(of: "telemetry-sample.json"))
        expect(sample.fuelPercent, 57, "2: fuelLevel 56.7 rounds to 57")
        expect(sample.rangeKm, 267, "4: fuelRange 267.4 rounds to 267")
        expect(sample.odometerKm, 44181, "5: odometer 44181.0 -> 44181")
        expect(sample.lock, .locked, "6: ALL_DOORS LOCKED beats a FRONT_LEFT UNLOCKED")
        expect(sample.vin, "VIN1", "parse keeps vin")
        expect(sample.name, "Focus ST", "parse keeps name")
        expectMillis(sample.updatedAt, 1751261664902, "8: latest of the four metrics is fuelLevel 05:34:24.902Z")

        // 3. fuelLevel missing / string / out of Int range
        let fuel = json("fuel-variants.json")
        expect(parse(fuel["missing"] as! [String: Any]).fuelPercent, nil, "3: fuelLevel missing -> nil")
        expect(parse(fuel["missing"] as! [String: Any]).rangeKm, 100, "3: other metrics survive a missing fuelLevel")
        expect(parse(fuel["string"] as! [String: Any]).fuelPercent, nil, "3: fuelLevel as string -> nil")
        expect(parse(fuel["huge"] as! [String: Any]).fuelPercent, nil, "3: fuelLevel 1e300 -> nil without trapping")

        // 7. door lock counting
        let locks = json("door-locks.json")
        func lock(_ key: String) -> LockState { parse(["doorLockStatus": locks[key]!]).lock }
        expect(lock("fourPlusTailgateUnknown"), .locked, "7: four locked + TAILGATE UNKNOWN -> locked")
        expect(lock("twoOfFour"), .partlyLocked, "7: two of four locked -> partlyLocked")
        expect(lock("none"), .unlocked, "7: none locked -> unlocked")
        expect(lock("empty"), .unknown, "7: [] -> unknown")
        expect(lock("onlyUnknown"), .unlocked, "7: only UNKNOWN entries -> unlocked (source returns unlocked)")
        expect(lock("mechanicalUnlockedIgnored"), .locked, "7: MECHANICAL-latch UNLOCKED entry does not count as required")
        expect(parse([:]).lock, .unknown, "7: missing doorLockStatus -> unknown")

        // 8. update times
        let times = json("update-times.json")
        func updated(_ key: String) -> Date? { parse(times[key] as! [String: Any]).updatedAt }
        expectMillis(updated("fractionalAndPlainLatestWins"), 1751261664902, "8: fractional beats earlier plain timestamp")
        expectMillis(updated("garbageIgnored"), 1749773154000, "8: garbage updateTime ignored, plain Z parsed")
        expectMillis(updated("onlyGarbage"), nil, "8: only garbage -> nil")
        expectMillis(updated("lockEntryIsLatest"), 1751364000000, "8: doorLockStatus entry updateTime counts")
        expectMillis(updated("otherMetricIgnored"), 1749773154000, "8: metrics outside the four are ignored")

        // 9. merge
        var merged: [String: Any] = [:]
        mergeMetrics(into: &merged, frame: frame("ws-frame-a.json"))
        expect(Set(merged.keys), ["fuelLevel", "odometer"], "9: frame A keys")
        expect(isComplete(merged), false, "9: incomplete after frame A")
        mergeMetrics(into: &merged, frame: frame("ws-frame-b.json"))
        expect(parse(merged).fuelPercent, 40, "9: fuelLevel from A kept after B")
        expect(parse(merged).odometerKm, 105, "9: odometer from B wins")
        expect(isComplete(merged), false, "9: still incomplete without fuelRange/doorLockStatus")
        mergeMetrics(into: &merged, frame: frame("ws-frame-c.json"))
        expect(isComplete(merged), true, "9: complete once all four metrics arrived")
        expect(parse(merged).lock, .locked, "9: merged lock")
        expect(parse(merged).rangeKm, 200, "9: merged range")
        var untouched: [String: Any] = ["fuelLevel": ["value": 1.0]]
        mergeMetrics(into: &untouched, frame: frame("ws-heartbeat.json"))
        expect(Set(untouched.keys), ["fuelLevel"], "9: frame without metrics changes nothing")

        // 10. classification
        expect(kind("ws-frame-a.json"), .data, "10: _data frame")
        expect(kind("ws-heartbeat.json"), .data, "10: heartbeat _data frame")
        expect(kind("ws-http-status.json"), .status(202), "10: _httpStatus number")
        expect(kind("ws-http-status-string.json"), .status(200), "10: _httpStatus numeric string")
        expect(kind("ws-error.json"), .error("provided token was expired"), "10: _error with message")
        expect(kind("ws-error-no-message.json"), .error(#"{"code":401}"#), "10: _error without message carries its JSON")
        expect(kind("ws-other.json"), .other, "10: unknown object")

        // 11. token response
        let ok = try? parseTokenResponse(data: data("token-ok.json"), status: 200)
        expect(ok, TokenResponse(accessToken: "b2c-access", refreshToken: "ford-refresh", expiresIn: 1800), "11: token ok parsed")
        expect(errorText { try parseTokenResponse(data: data("token-no-access-message.json"), status: 200) },
               "HTTP 200: Invalid code", "11: 200 without access_token carries message")
        expect(errorText { try parseTokenResponse(data: data("token-no-access-error-description.json"), status: 200) },
               "HTTP 200: The provided grant has expired", "11: falls back to error_description")
        expect(errorText { try parseTokenResponse(data: data("token-no-access-error.json"), status: 200) },
               "HTTP 200: invalid_grant", "11: falls back to error")
        expect(errorText { try parseTokenResponse(data: data("token-no-access-message.json"), status: 400) },
               "HTTP 400: Invalid code", "11: non-200 keeps its status")
        expect(errorText { try parseTokenResponse(data: Data("<html>".utf8), status: 403) },
               "HTTP 403: <html>", "11: non-JSON body is carried verbatim")

        // 12. refresh response
        let body460 = #"{"errorCode":"460","message":"Invalid or Expired Token","timestamp":"2026-11-15T03:38:37.012720962Z"}"#
        expect(errorCase { try parseRefreshResponse(data: data("refresh-460.json"), status: 400) }, "reauthRequired", "12: 400 -> reauthRequired")
        expect(errorText { try parseRefreshResponse(data: data("refresh-460.json"), status: 400) },
               "HTTP 400: \(body460)", "12: 400 description is the status and raw body")
        expect(errorCase { try parseRefreshResponse(data: data("refresh-401.json"), status: 401) }, "reauthRequired", "12: 401 -> reauthRequired")
        expect(errorCase { try parseRefreshResponse(data: data("refresh-502.json"), status: 502) }, "http", "12: 502 -> http")
        expect(errorText { try parseRefreshResponse(data: data("refresh-502.json"), status: 502) },
               #"HTTP 502: {"message":"Bad gateway"}"#, "12: 502 description")
        expect(try? parseRefreshResponse(data: data("token-ok.json"), status: 200),
               TokenResponse(accessToken: "b2c-access", refreshToken: "ford-refresh", expiresIn: 1800), "12: 200 refresh parsed")

        // wire encoders
        expect(pkceChallenge(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
               "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "PKCE S256 matches the RFC 7636 vector")
        expect(formEncode([("code", "a+b/c=="), ("scope", "x openid"), ("resource", ""),
                           ("grant_type", "urn:ietf:params:oauth:grant-type:token-exchange")]),
               "code=a%2Bb%2Fc%3D%3D&scope=x+openid&resource=&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange",
               "form body percent-encodes everything outside the unreserved set")
        expect(FordRegion.byId["deu"]!.authorizeURL(codeChallenge: "CHALLENGE"),
               "https://login.ford.de/4566605f-43a7-400a-946e-89cc9fdb0bd7/B2C_1A_SignInSignUp_de-DE/oauth2/v2.0/authorize?redirect_uri=fordapp://userauthorized&response_type=code&max_age=3600&code_challenge=CHALLENGE&code_challenge_method=S256&scope=%2009852200-05fd-41f6-8c21-d36d3497dc64%20openid&client_id=09852200-05fd-41f6-8c21-d36d3497dc64&ui_locales=de-DE&language_code=de-DE&ford_application_id=667D773E-1BDC-4139-8AD0-2B16474E8DC7&country_code=DEU",
               "authorize URL matches config_flow.py generate_url()")
        expect(FordRegion.all.count, 20, "region table has the 20 non-Lincoln non-legacy rows")
        expect(FordRegion.default(for: Locale(identifier: "en_DE")).id, "deu", "default region from en_DE")
        expect(FordRegion.default(for: Locale(identifier: "en_SE")).id, "rest_of_europe", "unmapped region falls back to rest_of_europe")

        for f in failures { print(f) }
        if failures.isEmpty {
            print("OK: \(assertionCount) assertions passed")
        } else {
            print("\(failures.count) of \(assertionCount) assertions failed")
            exit(1)
        }
    }
}
