import Foundation

func parseTokenResponse(data: Data, status: Int) throws -> TokenResponse {
    TokenResponse(accessToken: "", refreshToken: nil, expiresIn: nil)
}

func parseRefreshResponse(data: Data, status: Int) throws -> TokenResponse {
    TokenResponse(accessToken: "", refreshToken: nil, expiresIn: nil)
}

func formEncode(_ pairs: [(String, String)]) -> String { "" }

func pkceChallenge(verifier: String) -> String { "" }
