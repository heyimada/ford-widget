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

func details(_ metrics: [String: Any]) -> VehicleDetails { parse(metrics).details! }

func entry(_ value: Any?, _ extra: [String: Any] = [:]) -> [String: Any] {
    var e = extra
    if let value { e["value"] = value }
    return e
}

func rangeValue(_ upper: Double) -> [String: Any] { ["doubleRange": ["lowerBound": 0.0, "upperBound": upper]] }

func checkDetails() {
    // 1. the real fixture
    let full = details(metrics(of: "telemetry-full.json"))
    expect(full.doors.count, 6, "D1: six door entries")
    expect(full.doors.map(\.state), Array(repeating: OpenState.closed, count: 6), "D1: all doors closed")
    expect(Set(full.doors.map(\.id)).count, 6, "D1: door ids are distinct (two UNSPECIFIED_FRONT told apart by side/role)")
    expect(full.doors.map(\.position),
           ["Rear left", "Passenger", "Rear right", "Tailgate", "Driver", "Inner tailgate"], "D1: door position labels")
    expect(full.windows.count, 4, "D1: four windows")
    expect(full.windows.map(\.state), Array(repeating: OpenState.closed, count: 4), "D1: all windows closed")
    expect(Set(full.windows.map(\.id)).count, 4, "D1: window ids are distinct")
    expect(full.hood, .closed, "D1: hood closed")
    expect(full.alarm, .armed, "D1: alarm armed")
    expect(full.ignition, .off, "D1: ignition off")
    expectMillis(full.remoteStartEndsAt, nil, "D1: remoteStartEndsAt nil when the timer is 0")
    expect(full.tires.map(\.wheel), [.frontLeft, .frontRight, .rearLeft, .rearRight], "D1: four tires in wheel order")
    expect(full.tires.first?.pressureKPa, 242.0, "D1: front-left 242 kPa")
    expect(full.tires.first?.placardKPa, 206.8428, "D1: front-left placard from wheelPlacardFront")
    expect(full.tires.dropFirst(2).first?.placardKPa, 179.26376000000002, "D1: rear-left placard from wheelPlacardRear")
    expect(full.tires.map(\.status), Array(repeating: TireStatus.normal, count: 4), "D1: all tires normal")
    expect(full.oilLifePercent, 59, "D1: oil life 59")
    expect(full.batteryPercent, 67, "D1: battery 67 %")
    expect(full.batteryVoltage, 12.0, "D1: battery 12.0 V")
    expect(full.outsideTemperatureC, 11.5, "D1: outside 11.5")
    expect(full.coolantTemperatureC, 10.0, "D1: coolant 10.0")
    expect(full.location?.latitude, 50.9375, "D1: latitude")
    expect(full.location?.longitude, 6.9603, "D1: longitude")
    expectMillis(full.location?.reportedAt, 1793292088000, "D1: reportedAt is position.updateTime")
    expect(full.warnings, ["fastenSeatBeltWarning", "startStopEngineWarning"], "D1: lit indicators, sorted")

    // 2. door states
    func door(_ value: String?, role: String = "DRIVER") -> OpenState? {
        let e = entry(value, ["vehicleDoor": "UNSPECIFIED_FRONT", "vehicleOccupantRole": role, "vehicleSide": "DRIVER"])
        return details(["doorStatus": [e]]).doors.first?.state
    }
    expect(door("OPEN"), .open, "D2: OPEN -> open")
    expect(door("AJAR"), .open, "D2: AJAR -> open")
    expect(door("CLOSED"), .closed, "D2: CLOSED -> closed")
    expect(door("UNKNOWN"), .unknown, "D2: UNKNOWN -> unknown")
    expect(door(nil), .unknown, "D2: missing value -> unknown")
    expect(details(["hoodStatus": entry("OPEN")]).hood, .open, "D2: hood OPEN")

    // 3. windows
    func window(_ value: Any?) -> OpenState? {
        details(["windowStatus": [entry(value, ["vehicleWindow": "UNSPECIFIED_FRONT", "vehicleSide": "DRIVER"])]]).windows.first?.state
    }
    expect(window(rangeValue(0.4)), .open, "D3: upperBound 0.4 -> open")
    expect(window(rangeValue(0)), .closed, "D3: upperBound 0 -> closed")
    expect(window(nil), .unknown, "D3: window without value -> unknown")
    expect(window(["doubleRange": ["lowerBound": 0.0]]), .unknown, "D3: range without upperBound -> unknown")

    // 4. nothing known
    let empty = details([:])
    expect(empty.doors, [], "D4: no doors")
    expect(empty.windows, [], "D4: no windows")
    expect(empty.hood, .unknown, "D4: hood unknown, not closed")
    expect(empty.alarm, .unknown, "D4: alarm unknown")
    expect(empty.ignition, .unknown, "D4: ignition unknown")
    expect(empty.tires, [], "D4: no tires")
    expect(empty.oilLifePercent, nil, "D4: oil nil")
    expect(empty.batteryPercent, nil, "D4: battery nil")
    expect(empty.batteryVoltage, nil, "D4: voltage nil")
    expect(empty.outsideTemperatureC, nil, "D4: outside nil")
    expect(empty.coolantTemperatureC, nil, "D4: coolant nil")
    expect(empty.location, nil, "D4: location nil")
    expect(empty.warnings, [], "D4: no warnings")
    expectMillis(empty.remoteStartEndsAt, nil, "D4: no remote start end")

    // alarm and ignition values
    expect(details(["alarmStatus": entry("DISARMED")]).alarm, .disarmed, "D4: DISARMED")
    expect(details(["alarmStatus": entry("TRIGGERED")]).alarm, .triggered, "D4: TRIGGERED")
    expect(details(["alarmStatus": entry("SOMETHING")]).alarm, .unknown, "D4: other alarm value -> unknown")
    expect(details(["ignitionStatus": entry("RUN")]).ignition, .on, "D4: RUN -> on")
    expect(details(["ignitionStatus": entry("accessory")]).ignition, .on, "D4: accessory -> on")
    expect(details(["ignitionStatus": entry("START")]).ignition, .on, "D4: START -> on")
    expect(details(["ignitionStatus": entry("WEIRD")]).ignition, .unknown, "D4: other ignition value -> unknown")

    // 5. remote start countdown
    let stamp = "2026-11-03T16:45:00Z"
    expectMillis(details(["remoteStartCountdownTimer": entry(600.0, ["updateTime": stamp])]).remoteStartEndsAt,
                 1793724300000 + 600_000, "D5: updateTime + 600 s")
    expectMillis(details(["remoteStartCountdownTimer": entry(0.0, ["updateTime": stamp])]).remoteStartEndsAt, nil, "D5: 0 -> nil")
    expectMillis(details(["remoteStartCountdownTimer": entry(600.0)]).remoteStartEndsAt, nil, "D5: no updateTime -> nil")

    // 6. indicators
    let indicators: [String: Any] = [
        "zeta": entry(true), "alpha": entry(true), "off": entry(false),
        "string": entry("true"), "number": entry(1), "missing": ["updateTime": stamp], "notAnObject": true,
    ]
    expect(details(["indicators": indicators]).warnings, ["alpha", "zeta"], "D6: only value == true, sorted")

    // 7. tires
    let tires = details([
        "tirePressure": [entry(250.0, ["vehicleWheel": "FRONT_LEFT", "wheelPlacardFront": 200.0]),
                         ["vehicleWheel": "REAR_RIGHT", "wheelPlacardRear": 180.0]],
        "tirePressureStatus": [entry("LOW", ["vehicleWheel": "FRONT_LEFT"]), entry("NORMAL", ["vehicleWheel": "REAR_RIGHT"])],
    ]).tires
    expect(tires.count, 2, "D7: two tires")
    expect(tires.first, Tire(wheel: .frontLeft, pressureKPa: 250, placardKPa: 200, status: .low), "D7: LOW -> low")
    expect(tires.dropFirst().first, Tire(wheel: .rearRight, pressureKPa: nil, placardKPa: 180, status: .normal), "D7: missing pressure -> nil")
    expect(details(["tirePressure": [entry(240.0, ["vehicleWheel": "FRONT_RIGHT"])]]).tires.first?.status, .unknown,
           "D7: no status entry -> unknown, not normal")

    // 8. position
    func location(_ lat: Any, _ lon: Any) -> CarLocation? {
        details(["position": ["updateTime": stamp, "value": ["location": ["lat": lat, "lon": lon]]]]).location
    }
    expect(location("50.9375", "6.9603"), CarLocation(latitude: 50.9375, longitude: 6.9603,
                                                        reportedAt: Date(timeIntervalSince1970: 1793724300)), "D8: string coordinates")
    expect(location(1.5, -2.5)?.longitude, -2.5, "D8: numeric coordinates")
    expect(location("north", 1.0), nil, "D8: non-numeric latitude -> nil")
    expect(details(["position": ["value": [:]]]).location, nil, "D8: position without location -> nil")
}

func checkGarage() {
    // 9.
    let p = try? parseGarage(data("garage.json"))
    expect(p?.vin, "WF0XXXGCHXJA00000", "G9: vin")
    expect(p?.name, "Focus ST", "G9: nickName")
    expect(p?.model, "Focus (2018)", "G9: model")
    expect(p?.year, 2021, "G9: year is the Int from profile.year")
    expect(p?.color, "FROZEN WHITE", "G9: color")
    expect(p?.licensePlate, "K FS 123", "G9: plate")
    expect(p?.imageURL, URL(string: "https://example.invalid/vehicle.png"), "G9: image URL")
    for key in ["remoteLock", "remoteStart", "oilLife", "tirePressureMonitoring", "remotePanicAlarm"] {
        expect(p?.capabilities.contains(key), true, "G9: capability \(key)")
    }
    expect(p?.capabilities.contains("remoteClimateControl"), false, "G9: NoDisplay capability excluded")
    expect(p?.capabilities.contains("extendRemoteStart"), false, "G9: non-string capability excluded")

    let noNick = #"[{"vin":"V1","nickName":"","profile":{"model":"Fiesta","paintDescription":"RED"}}]"#
    let q = try? parseGarage(Data(noNick.utf8))
    expect(q?.name, "Fiesta", "G9: empty nickName -> model")
    expect(q?.color, "RED", "G9: color falls back to profile.paintDescription")
    expect(q?.year, nil, "G9: no year -> nil")
    expect(q?.capabilities, Set<String>(), "G9: no capabilities")
    let bare = try? parseGarage(Data(#"[{"vin":"V2"}]"#.utf8))
    expect(bare?.name, "Ford", "G9: neither nickName nor model -> Ford")
    expect(errorCase { _ = try parseGarage(Data("[]".utf8)); return TokenResponse(accessToken: "", refreshToken: nil, expiresIn: nil) },
           "noVehicle", "G9: empty garage -> noVehicle")
    expect(errorCase { _ = try parseGarage(Data("nope".utf8)); return TokenResponse(accessToken: "", refreshToken: nil, expiresIn: nil) },
           "noVehicle", "G9: garbage -> noVehicle")
}

func checkCommands() {
    let states = json("telemetry-full.json")["states"] as! [String: Any]
    let oldLock = "00000000-0000-0000-0000-000000000003"
    // 10.
    expect(commandPhase(states: states, command: .lock, commandId: "NEW"), .waiting, "C10: old lockCommand with another id is not ours")
    expect(commandPhase(states: states, command: .remoteStart, commandId: "NEW"), .waiting, "C10: old remoteStartCommand is not ours")
    expect(commandPhase(states: [:], command: .unlock, commandId: "NEW"), .waiting, "C10: no state at all -> waiting")
    expect(commandPhase(states: states, command: .lock, commandId: oldLock), .failed("CAN Timeout"),
           "C10: lock finds lockCommand; FAILURE carries oemErrorContext")
    expect(commandPhase(states: states, command: .cancelRemoteStart, commandId: "00000000-0000-0000-0000-000000000002"),
           .succeeded, "C10: matching id + success -> succeeded")

    func phase(_ toState: String?, key: String = "lockCommand", error: [String: Any]? = nil) -> CommandPhase {
        var value: [String: Any] = [:]
        if let toState { value["toState"] = toState }
        if let error { value["data"] = ["commandError": ["commandExecutionFailure": error]] }
        return commandPhase(states: [key: ["commandId": "ID", "value": value]], command: .lock, commandId: "ID")
    }
    expect(phase("success"), .succeeded, "C10: success")
    expect(phase("COMMAND_SUCCEEDED_ON_DEVICE"), .succeeded, "C10: COMMAND_SUCCEEDED_ON_DEVICE")
    expect(phase("Success"), .succeeded, "C10: toState compared case-insensitively")
    expect(phase("FAILURE", error: ["oemErrorContext": "CAN Timeout"]), .failed("CAN Timeout"), "C10: FAILURE + oemErrorContext")
    expect(phase("command_failed_on_device"), .failed("Failed"), "C10: failure without context -> Failed")
    expect(phase("expired"), .expired, "C10: expired")
    for waiting in ["request_queued", "received_by_device", "oem_cloud_to_device_delivery_in_progress", "something_delivery_x", "mystery"] {
        expect(phase(waiting), .waiting, "C10: \(waiting) -> waiting")
    }
    expect(phase(nil), .waiting, "C10: no toState -> waiting")
    expect(phase("success", key: "lock"), .succeeded, "C10: plain key is looked up first")
    expect(commandPhase(states: ["lock": ["commandId": "ID", "value": ["toState": "failure"]],
                                 "lockCommand": ["commandId": "ID", "value": ["toState": "success"]]],
                        command: .lock, commandId: "ID"), .failed("Failed"), "C10: plain key wins over the Command suffix")
    expect(commandPhase(states: ["commands": ["lockCommand": ["commandId": "ID", "value": ["toState": "success"]]]],
                        command: .lock, commandId: "ID"), .succeeded, "C10: states.commands is flattened like the integration does")

    // 11.
    func id(_ body: String) -> String {
        do { return try parseCommandId(Data(body.utf8)) } catch { return "error" }
    }
    expect(id(#"{"id":"A","commandId":"B"}"#), "A", "C11: id first")
    expect(id(#"{"commandId":"B","correlationId":"C"}"#), "B", "C11: commandId second")
    expect(id(#"{"correlationId":"C"}"#), "C", "C11: correlationId third")
    expect(id(#"{"other":"X"}"#), "error", "C11: none -> error")
    expect(id("[]"), "error", "C11: non-object -> error")
    expect(id("not json"), "error", "C11: garbage -> error")
    expect(CarCommand.allCases.map(\.rawValue), ["lock", "unlock", "remoteStart", "cancelRemoteStart", "statusRefresh"], "C11: wire names")
}

func checkLegacySnapshot() {
    // 12. a snapshot file written by the build before `details` existed
    let old = #"{"vin":"V","name":"Focus ST","fuelPercent":57,"rangeKm":267,"odometerKm":44181,"lock":"locked","updatedAt":1751261664.9,"fetchedAt":1751866464.9}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let snapshot = try? decoder.decode(VehicleSnapshot.self, from: Data(old.utf8))
    expect(snapshot?.fuelPercent, 57, "S12: legacy snapshot decodes")
    expect(snapshot?.details == nil, true, "S12: legacy snapshot has no details")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let roundTrip = try? decoder.decode(VehicleSnapshot.self, from: encoder.encode(parse(metrics(of: "telemetry-full.json"))))
    expect(roundTrip?.details, parse(metrics(of: "telemetry-full.json")).details, "S12: snapshot with details round-trips")
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

        checkDetails()
        checkGarage()
        checkCommands()
        checkLegacySnapshot()

        for f in failures { print(f) }
        if failures.isEmpty {
            print("OK: \(assertionCount) assertions passed")
        } else {
            print("\(failures.count) of \(assertionCount) assertions failed")
            exit(1)
        }
    }
}
