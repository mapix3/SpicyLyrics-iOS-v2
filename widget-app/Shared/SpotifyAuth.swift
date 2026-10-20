import Foundation
import CryptoKit

enum SpotifyAuth {
    static let redirectURI = "spicylyricswidget://callback"
    static let callbackScheme = "spicylyricswidget"
    static let scopes = "user-read-currently-playing user-read-playback-state"

    struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    enum AuthError: LocalizedError {
        case noClientID, notLoggedIn, http(Int, String)
        var errorDescription: String? {
            switch self {
            case .noClientID: return "Укажи Client ID из developer.spotify.com"
            case .notLoggedIn: return "Войди в Spotify в приложении"
            case .http(let c, let m): return "Spotify: ошибка \(c) \(m)"
            }
        }
    }

    static var tokens: Tokens? {
        get { SharedStore.load(Tokens.self, from: "tokens.json") }
        set { if let t = newValue { SharedStore.save(t, as: "tokens.json") } else {
            try? FileManager.default.removeItem(at: SharedStore.directory.appendingPathComponent("tokens.json")) } }
    }

    static var isLoggedIn: Bool { tokens != nil }

    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64url(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func authorizeURL(verifier: String) throws -> URL {
        let id = SharedStore.clientID
        guard !id.isEmpty else { throw AuthError.noClientID }
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: id),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge(for: verifier)),
            .init(name: "scope", value: scopes),
        ]
        return c.url!
    }

    static func exchange(callback: URL, verifier: String) async throws {
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.http(0, "нет кода авторизации")
        }
        try await tokenRequest([
            "grant_type": "authorization_code", "code": code,
            "redirect_uri": redirectURI, "client_id": SharedStore.clientID, "code_verifier": verifier,
        ])
    }

    static func accessToken() async throws -> String {
        guard let t = tokens else { throw AuthError.notLoggedIn }
        if t.expiresAt.timeIntervalSinceNow > 60 { return t.accessToken }
        try await tokenRequest([
            "grant_type": "refresh_token", "refresh_token": t.refreshToken, "client_id": SharedStore.clientID,
        ])
        guard let n = tokens else { throw AuthError.notLoggedIn }
        return n.accessToken
    }

    private static func tokenRequest(_ form: [String: String]) async throws {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+:/")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200, let access = json["access_token"] as? String else {
            if status == 400, (json["error"] as? String) == "invalid_grant" { tokens = nil }
            throw AuthError.http(status, json["error_description"] as? String ?? "")
        }
        let refresh = json["refresh_token"] as? String ?? tokens?.refreshToken ?? ""
        let expires = json["expires_in"] as? Double ?? 3600
        tokens = Tokens(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expires))
    }
}
