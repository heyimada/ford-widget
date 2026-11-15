import AuthenticationServices
import UIKit

@MainActor
final class WebAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// Runs the Ford login in the system browser sheet and returns the `code` from the `fordapp://` callback.
    func authorizationCode(url: URL) async throws -> String {
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "fordapp") { @Sendable callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? FordError.decoding("sign-in returned nothing"))
                }
            }
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }
        session = nil
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw FordError.decoding("no code in the sign-in redirect")
        }
        return code
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            // Sign-in is started from a visible screen, so a window scene always exists.
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
                preconditionFailure("no window scene to present the sign-in sheet")
            }
            return scene.keyWindow ?? ASPresentationAnchor(windowScene: scene)
        }
    }
}
