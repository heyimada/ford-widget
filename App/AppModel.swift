import AuthenticationServices
import Observation
import SwiftUI
import WidgetKit

@MainActor
@Observable
final class AppModel {
    private(set) var session: FordSession?
    private(set) var snapshot: VehicleSnapshot?
    private(set) var carImage: Image?
    private(set) var errorText = ""
    private(set) var needsReauth = false
    private(set) var isBusy = false
    var regionId: String

    private let webAuth = WebAuth()

    init() {
        let stored = SessionStore.load()
        session = stored
        snapshot = SnapshotStore.latest()
        carImage = CarImage.load()
        regionId = stored?.regionId ?? FordRegion.default().id
    }

    var isSignedIn: Bool { session != nil }

    func signIn() async {
        await run {
            let region = FordRegion.byId[self.regionId] ?? .fallback
            let pkce = FordAPI.newPKCE()
            guard let url = URL(string: region.authorizeURL(codeChallenge: pkce.challenge)) else {
                throw FordError.decoding("could not build the sign-in URL")
            }
            let code = try await self.webAuth.authorizationCode(url: url)
            var session = try await FordAPI.signIn(code: code, verifier: pkce.verifier, region: region)
            let vehicle = try await FordAPI.firstVehicle(session)
            session.vin = vehicle.vin
            session.vehicleName = vehicle.name
            try SessionStore.save(session)
            self.session = session
            if let imageURL = vehicle.imageURL {
                try? await FordAPI.downloadCarImage(from: imageURL, session: session)
                self.carImage = CarImage.load()
            }
            try await self.fetchSnapshot(session)
        }
    }

    func refresh() async {
        await run {
            guard let session = self.session else { return }
            try await self.fetchSnapshot(self.renewed(session))
        }
    }

    /// Sends statusRefresh, then polls every 10 s for up to 60 s until the car reports something newer.
    func askCarToRefresh() async {
        await run {
            guard let session = self.session, let vin = session.vin else { return }
            let fresh = try await self.renewed(session)
            let token = try await FordAPI.autonomicToken(refreshToken: fresh.refreshToken)
            let baseline = self.snapshot?.updatedAt
            try await FordAPI.requestStatusRefresh(vin: vin, token: token)
            for _ in 0..<6 {
                try await Task.sleep(for: .seconds(10))
                let latest = try await FordAPI.snapshot(for: fresh, token: token)
                self.store(latest)
                if let updated = latest.updatedAt, baseline.map({ updated > $0 }) ?? true { break }
            }
        }
    }

    func signOut() {
        SessionStore.clear()
        SnapshotStore.clear()
        CarImage.clear()
        session = nil
        snapshot = nil
        carImage = nil
        errorText = ""
        needsReauth = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Ford token refresh is app-only: the widget never writes the Keychain.
    private func renewed(_ session: FordSession) async throws -> FordSession {
        let fresh = try await FordAPI.freshSession(session)
        if fresh.accessToken != session.accessToken {
            try SessionStore.save(fresh)
            self.session = fresh
        }
        return fresh
    }

    private func fetchSnapshot(_ session: FordSession) async throws {
        store(try await FordAPI.snapshot(for: session))
    }

    private func store(_ latest: VehicleSnapshot) {
        snapshot = latest
        SnapshotStore.save(latest, as: .app)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
            errorText = ""
            needsReauth = false
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch let error as FordError {
            errorText = error.description
            if case .reauthRequired = error { needsReauth = true }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
