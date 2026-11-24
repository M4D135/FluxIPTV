import Foundation

/// Normalization shared by macOS and tvOS; no credentials are logged or persisted here.
public struct XtreamLogin: Equatable, Sendable {
    public let server: URL
    public let username: String
    public let password: String

    /// Accept a base URL or a provider URL with embedded query credentials.
    /// Explicit credentials take precedence; the password is never silently trimmed.
    public init(server raw: String, username: String = "", password: String = "") throws {
        var address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !address.contains(where: { $0.isWhitespace }) else { throw IPTVError.invalidURL }
        if !address.contains("://") { address = "https://" + address }
        let validated = try IPTVURL.validated(address)
        guard var parts = URLComponents(url: validated, resolvingAgainstBaseURL: false) else { throw IPTVError.invalidURL }
        let embedded = parts.queryItems ?? []
        func value(_ key: String) -> String? { embedded.first { $0.name.lowercased() == key }?.value }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.username = user.isEmpty ? (value("username") ?? "") : user
        self.password = password.isEmpty ? (value("password") ?? "") : password
        guard !self.username.isEmpty, !self.password.isEmpty else { throw IPTVError.authenticationFailed }
        // Only recognized Xtream endpoint names are removed; retain proxy subpaths and ports.
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") && !path.isEmpty { path.removeLast() }
        if ["get.php", "player_api.php", "xmltv.php"].contains(path.split(separator: "/").last?.lowercased() ?? "") {
            path = String(path[..<(path.lastIndex(of: "/") ?? path.startIndex)])
        }
        parts.percentEncodedPath = path
        parts.query = nil
        parts.fragment = nil
        guard let url = parts.url else { throw IPTVError.invalidURL }
        self.server = url
    }
}
