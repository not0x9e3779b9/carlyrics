import Foundation
import SpotifyIntegration

struct AppConfiguration {
    let clientID: String
    let redirectURI: URL?
    let callbackScheme: String
    let allowsSpotifyLyrics: Bool

    init(bundle: Bundle = .main) {
        clientID = bundle.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
        redirectURI = (bundle.object(forInfoDictionaryKey: "SpotifyRedirectURI") as? String).flatMap(URL.init(string:))
        callbackScheme = bundle.object(forInfoDictionaryKey: "SpotifyCallbackScheme") as? String ?? ""
        allowsSpotifyLyrics = (bundle.object(forInfoDictionaryKey: "SpotifyLyricsEnabled") as? String)?.uppercased() == "YES"
    }

    var issues: [String] {
        var result: [String] = []
        if clientID.isEmpty || clientID.contains("REPLACE") || clientID.contains("$(") {
            result.append("Set your Spotify client ID in Config.local.xcconfig.")
        }
        if redirectURI?.scheme != callbackScheme || callbackScheme.isEmpty || redirectURI?.host == nil {
            result.append("The callback scheme and redirect URI must agree exactly.")
        }
        return result
    }

    var spotify: SpotifyConfiguration? {
        guard issues.isEmpty, let redirectURI else { return nil }
        return SpotifyConfiguration(clientID: clientID, redirectURI: redirectURI)
    }
}
