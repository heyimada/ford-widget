import AuthenticationServices
import LocalAuthentication
import Observation
import SwiftUI
import WidgetKit

enum AppTab: String, Hashable {
    case overview, location, health, vehicle
}

@MainActor
@Observable
final class AppModel {
    private(set) var session: FordSession?
    private(set) var snapshot: VehicleSnapshot?
    private(set) var profile: VehicleProfile?
    private(set) var carImage: Image?
    private(set) var errorText = ""
    private(set) var needsReauth = false
    private(set) var isBusy = false
    /// The command in flight, or the last one's outcome until the next command starts.
    private(set) var commandPhases: [CarCommand: CommandPhase] = [:]
    private(set) var isDemo = false
    var selectedTab: AppTab = .overview
    var regionId: String

    /// Waking the car drains its 12 V battery while it is in power-saving mode, so update requests are rationed.
    static let updateCooldown: TimeInterval = 15 * 60
    private static let lastUpdateKey = "lastStatusRefreshSentAt"

    private let webAuth = WebAuth()
    private var current: Task<Void, Error>?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            regionId = FordRegion.default().id
            loadDemo()
            return
        }
        #endif
        let stored = SessionStore.load()
        session = stored
        // The widget may write a newer but thinner snapshot, so the app reads only its own file.
        snapshot = stored == nil ? nil : SnapshotStore.load(.app)
        profile = stored == nil ? nil : ProfileStore.load()
        carImage = CarImage.load()
        regionId = stored?.regionId ?? FordRegion.default().id
    }

    var isSignedIn: Bool { session != nil }

    /// Seconds until "Update from car" may be sent again; 0 when it may be sent now.
    func updateCooldownRemaining(now: Date = Date()) -> TimeInterval {
        let sent = UserDefaults.standard.object(forKey: Self.lastUpdateKey) as? Date
        return cooldownRemaining(lastSent: sent, now: now, interval: Self.updateCooldown)
    }

    var canLockUnlock: Bool { profile?.capabilities.contains("remoteLock") == true }
    var canRemoteStart: Bool { profile?.capabilities.contains("remoteStart") == true }

    // MARK: sign-in and fetching

    func signIn() async {
        guard !isDemo else { return }
        await run {
            let region = FordRegion.byId[self.regionId] ?? .fallback
            let pkce = FordAPI.newPKCE()
            guard let url = URL(string: region.authorizeURL(codeChallenge: pkce.challenge)) else {
                throw FordError.decoding("could not build the sign-in URL")
            }
            let code = try await self.webAuth.authorizationCode(url: url)
            var session = try await FordAPI.signIn(code: code, verifier: pkce.verifier, region: region)
            let vehicle = try await FordAPI.vehicleProfile(session)
            session.vin = vehicle.vin
            session.vehicleName = vehicle.name
            try Task.checkCancellation()
            try SessionStore.save(session)
            self.session = session
            self.store(vehicle)
            if let imageURL = vehicle.imageURL {
                try? await FordAPI.downloadCarImage(from: imageURL, session: session)
                self.carImage = CarImage.load()
            }
            try await self.fetchSnapshot(session)
        }
    }

    func refresh() async {
        guard !isDemo else { return }
        await run {
            guard let session = self.session else { return }
            var fresh = try await self.renewed(session)
            if let vehicle = try? await FordAPI.vehicleProfile(fresh) {
                try Task.checkCancellation()
                if vehicle.vin != fresh.vin || vehicle.name != fresh.vehicleName {
                    fresh.vin = vehicle.vin
                    fresh.vehicleName = vehicle.name
                    try SessionStore.save(fresh)
                    self.session = fresh
                }
                self.store(vehicle)
            }
            try await self.fetchSnapshot(fresh)
        }
    }

    func signOut() {
        guard !isDemo else { return }
        current?.cancel()
        SessionStore.clear()
        SnapshotStore.clear()
        ProfileStore.clear()
        CarImage.clear()
        session = nil
        snapshot = nil
        profile = nil
        carImage = nil
        errorText = ""
        needsReauth = false
        commandPhases = [:]
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: commands

    func perform(_ command: CarCommand) async {
        guard !isBusy else { return }
        if isDemo {
            commandPhases = [command: .failed("Demo mode")]
            return
        }
        if command == .statusRefresh {
            guard updateCooldownRemaining() == 0 else { return }
        }
        // Authentication runs inside `run` so the busy gate is held during the Touch ID / Face ID prompt: the prompt
        // bounces scenePhase, and the refresh that triggers must not take the gate and drop the approved command.
        await run {
            if command == .unlock || command == .remoteStart {
                switch await Self.confirm(command) {
                case .confirmed: break
                case .cancelled: return
                case .failed(let message):
                    self.commandPhases = [command: .failed(message)]
                    return
                }
            }
            try await self.runCommand(command)
        }
    }

    private enum Confirmation {
        case confirmed, cancelled
        case failed(String)
    }

    private static func confirm(_ command: CarCommand) async -> Confirmation {
        let reason = command == .unlock ? "Confirm unlocking your car." : "Confirm starting your car."
        do {
            let ok = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? .confirmed : .cancelled
        } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Polls the telemetry `states` for our command id with growing delays (2, 4, … 18 s: about 90 s in all).
    private func runCommand(_ command: CarCommand) async throws {
        guard let session, let vin = session.vin else { return }
        commandPhases = [command: .sending]
        do {
            let fresh = try await renewed(session)
            let token = try await FordAPI.autonomicToken(refreshToken: fresh.refreshToken)
            if command == .statusRefresh { UserDefaults.standard.set(Date(), forKey: Self.lastUpdateKey) }
            let id: String
            do {
                id = try await FordAPI.send(command, vin: vin, token: token)
            } catch FordError.http(let status, let body) {
                throw FordError.http(status, body)
            } catch {
                // Timeout after transmission or an unreadable 2xx: the car may still act on it.
                try Task.checkCancellation()
                commandPhases[command] = .failed(Self.unconfirmedMessage)
                try? await fetchSnapshot(fresh, token: token)
                return
            }
            commandPhases[command] = .waiting

            var phase = CommandPhase.waiting
            for delay in stride(from: 2, through: 18, by: 2) {
                try await Task.sleep(for: .seconds(delay))
                // A failed poll is not a failed command: try again at the next delay.
                guard let response = try? await FordAPI.telemetryResponse(vin: vin, token: token) else { continue }
                phase = commandPhase(states: response["states"] as? [String: Any] ?? [:], command: command, commandId: id)
                if phase != .waiting { break }
            }
            // The command may still have reached the car, so an unconfirmed send must not read as "nothing happened".
            if phase == .waiting { phase = .failed(Self.unconfirmedMessage) }
            try Task.checkCancellation()
            commandPhases[command] = phase
            if phase == .succeeded { forgetSuccess(of: command) }
            // A failed refresh must not overwrite the command's own outcome.
            try? await fetchSnapshot(fresh, token: token)
        } catch {
            if Task.isCancelled { throw error }
            if case FordError.reauthRequired = error {
                commandPhases = [:]
                throw error
            }
            commandPhases[command] = .failed((error as? FordError)?.description ?? error.localizedDescription)
        }
    }

    private static let unconfirmedMessage = "Sent, but the car has not confirmed yet. The status below is the latest the car reported."

    private func forgetSuccess(of command: CarCommand) {
        Task {
            try? await Task.sleep(for: .seconds(6))
            if commandPhases[command] == .succeeded { commandPhases[command] = nil }
        }
    }

    // MARK: plumbing

    /// Ford token refresh is app-only: the widget never writes the Keychain.
    private func renewed(_ session: FordSession) async throws -> FordSession {
        let fresh = try await FordAPI.freshSession(session)
        if fresh.accessToken != session.accessToken {
            try Task.checkCancellation()
            try SessionStore.save(fresh)
            self.session = fresh
        }
        return fresh
    }

    private func fetchSnapshot(_ session: FordSession, token: String? = nil) async throws {
        try store(try await FordAPI.snapshot(for: session, token: token, fullState: true))
    }

    /// Main-actor isolated, so a sign-out cannot land between the cancellation check and the writes.
    private func store(_ latest: VehicleSnapshot) throws {
        try Task.checkCancellation()
        snapshot = latest
        SnapshotStore.save(latest, as: .app)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func store(_ vehicle: VehicleProfile) {
        profile = vehicle
        ProfileStore.save(vehicle)
    }

    /// Runs one operation at a time as a task that `signOut()` cancels, so a late result cannot resurrect the session.
    private func run(_ work: @escaping @MainActor () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        let task = Task { try await work() }
        current = task
        defer {
            isBusy = false
            current = nil
        }
        do {
            try await task.value
            errorText = ""
            needsReauth = false
        } catch _ where task.isCancelled {
            return
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch let error as FordError {
            errorText = error.description
            if case .reauthRequired = error { needsReauth = true }
        } catch {
            errorText = error.localizedDescription
        }
    }

    #if DEBUG
    /// Screenshot mode: fixtures from the app's Documents/demo, no Keychain, no network.
    private func loadDemo() {
        isDemo = true
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-tab"), arguments.indices.contains(flag + 1),
           let tab = AppTab(rawValue: arguments[flag + 1]) {
            selectedTab = tab
        }
        let directory = URL.documentsDirectory.appending(path: "demo")
        guard let telemetry = try? Data(contentsOf: directory.appending(path: "telemetry-full.json")),
              let metrics = (try? JSONSerialization.jsonObject(with: telemetry) as? [String: Any])?["metrics"] as? [String: Any],
              let garage = try? Data(contentsOf: directory.appending(path: "garage.json")),
              let vehicle = try? parseGarage(garage) else {
            errorText = "Demo files missing in Documents/demo."
            return
        }
        profile = vehicle
        carImage = CarImage.load(from: directory.appending(path: "car.png"))
        snapshot = VehicleSnapshot.parse(metrics: metrics, vin: vehicle.vin, name: vehicle.name, fetchedAt: Date())
        regionId = "deu"
        session = FordSession(regionId: "deu", accessToken: "demo", refreshToken: "demo",
                              accessExpiresAt: .distantFuture, vin: vehicle.vin, vehicleName: vehicle.name)
    }
    #endif
}
