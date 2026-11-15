import Foundation

struct FordRegion: Equatable, Sendable {
    let id: String
    let appId: String
    let locale: String
    let loginHost: String
    let countryCode: String

    static let oauthId = "4566605f-43a7-400a-946e-89cc9fdb0bd7"
    static let clientId = "09852200-05fd-41f6-8c21-d36d3497dc64"
    static let redirectURI = "fordapp://userauthorized"

    private static let africa = "71AA9ED7-B26B-4C15-835E-9F35CC238561"
    private static let asiaPacific = "39CD6590-B1B9-42CB-BEF9-0DC1FDB96260"
    private static let europe = "667D773E-1BDC-4139-8AD0-2B16474E8DC7"
    private static let northAmerica = "BFE8C5ED-D687-4C19-A5DD-F92CDFC4503A"
    private static let southAmerica = "C1DFFEF5-5BA5-486A-9054-8B39A9DF9AFC"

    static let all: [FordRegion] = [
        FordRegion(id: "deu", appId: europe, locale: "de-DE", loginHost: "https://login.ford.de", countryCode: "DEU"),
        FordRegion(id: "dnk", appId: europe, locale: "da-DK", loginHost: "https://login.ford.com", countryCode: "DNK"),
        FordRegion(id: "fra", appId: europe, locale: "fr-FR", loginHost: "https://login.ford.com", countryCode: "FRA"),
        FordRegion(id: "ita", appId: europe, locale: "it-IT", loginHost: "https://login.ford.com", countryCode: "ITA"),
        FordRegion(id: "esp", appId: europe, locale: "es-ES", loginHost: "https://login.ford.com", countryCode: "ESP"),
        FordRegion(id: "nor", appId: europe, locale: "no-NO", loginHost: "https://login.ford.no", countryCode: "NOR"),
        FordRegion(id: "nld", appId: europe, locale: "nl-NL", loginHost: "https://login.ford.com", countryCode: "NLD"),
        FordRegion(id: "gbr", appId: europe, locale: "en-GB", loginHost: "https://login.ford.co.uk", countryCode: "GBR"),
        FordRegion(id: "pol", appId: europe, locale: "pl-PL", loginHost: "https://login.ford.pl", countryCode: "POL"),
        FordRegion(id: "prt", appId: europe, locale: "pt-PT", loginHost: "https://login.ford.com", countryCode: "PRT"),
        FordRegion(id: "rest_of_europe", appId: europe, locale: "en-GB", loginHost: "https://login.ford.com", countryCode: "GBR"),
        FordRegion(id: "can", appId: northAmerica, locale: "en-CA", loginHost: "https://login.ford.com", countryCode: "CAN"),
        FordRegion(id: "mex", appId: northAmerica, locale: "es-MX", loginHost: "https://login.ford.com", countryCode: "MEX"),
        FordRegion(id: "usa", appId: northAmerica, locale: "en-US", loginHost: "https://login.ford.com", countryCode: "USA"),
        FordRegion(id: "bra", appId: southAmerica, locale: "pt-BR", loginHost: "https://login.ford.com", countryCode: "BRA"),
        FordRegion(id: "arg", appId: southAmerica, locale: "es-AR", loginHost: "https://login.ford.com", countryCode: "ARG"),
        FordRegion(id: "aus", appId: asiaPacific, locale: "en-AU", loginHost: "https://login.ford.com", countryCode: "AUS"),
        FordRegion(id: "nzl", appId: asiaPacific, locale: "en-NZ", loginHost: "https://login.ford.com", countryCode: "NZL"),
        FordRegion(id: "zaf", appId: africa, locale: "en-ZA", loginHost: "https://login.ford.com", countryCode: "ZAF"),
        FordRegion(id: "rest_of_world", appId: northAmerica, locale: "en-US", loginHost: "https://login.ford.com", countryCode: "USA"),
    ]

    static let byId: [String: FordRegion] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static let fallback = byId["rest_of_europe"]!

    // ISO 3166-1 alpha-2 of the device region -> region id; anything else falls back to rest_of_europe.
    private static let idByCountry: [String: String] = [
        "DE": "deu", "DK": "dnk", "FR": "fra", "IT": "ita", "ES": "esp", "NO": "nor", "NL": "nld",
        "GB": "gbr", "PL": "pol", "PT": "prt", "CA": "can", "MX": "mex", "US": "usa", "BR": "bra",
        "AR": "arg", "AU": "aus", "NZ": "nzl", "ZA": "zaf",
    ]

    static func `default`(for locale: Locale = .current) -> FordRegion {
        locale.region.flatMap { idByCountry[$0.identifier] }.flatMap { byId[$0] } ?? fallback
    }

    var displayName: String {
        switch id {
        case "rest_of_europe": return "Other European countries"
        case "rest_of_world": return "Rest of the world"
        // Regions are countries; the locale's region part names the country ("de-DE" → "Germany").
        default: return Locale.current.localizedString(forRegionCode: String(locale.suffix(2))) ?? id
        }
    }

    private var authBase: String {
        "\(loginHost)/\(Self.oauthId)/B2C_1A_SignInSignUp_\(locale)/oauth2/v2.0"
    }

    var tokenURL: URL { URL(string: "\(authBase)/token")! }

    // Built as a literal string: URLComponents would re-encode the pre-encoded "%20" scope and the redirect URI.
    func authorizeURL(codeChallenge: String) -> String {
        let client = Self.clientId
        return "\(authBase)/authorize?redirect_uri=\(Self.redirectURI)&response_type=code&max_age=3600"
            + "&code_challenge=\(codeChallenge)&code_challenge_method=S256&scope=%20\(client)%20openid"
            + "&client_id=\(client)&ui_locales=\(locale)&language_code=\(locale)"
            + "&ford_application_id=\(appId)&country_code=\(countryCode)"
    }
}
