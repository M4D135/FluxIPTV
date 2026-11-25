import Foundation

/// Stateless transport. Login cookies, credentials, disk caches and foreign
/// redirects are never shared with the application or a browser session.
enum PublicYouTubeHTTP {
    static func data(for original: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        guard let url = original.url, PublicYouTubePolicy.isRequestURL(url) else { throw PublicYouTubeError.invalidURL }
        var request = original
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        request.setValue(nil, forHTTPHeaderField: "Cookie")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, let finalURL = response.url,
              PublicYouTubePolicy.isRequestURL(finalURL), (200..<300).contains(response.statusCode) else {
            throw PublicYouTubeError.network
        }
        let limit = 12 * 1024 * 1024
        guard response.expectedContentLength <= Int64(limit) else { throw PublicYouTubeError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            if data.count % 16384 == 0 { try Task.checkCancellation() }
            guard data.count < limit else { throw PublicYouTubeError.invalidResponse }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }

    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            guard let url = request.url, PublicYouTubePolicy.isRequestURL(url),
                  !["/signin", "/login", "/consent"].contains(url.path) else { completionHandler(nil); return }
            var clean = request
            clean.httpShouldHandleCookies = false
            clean.setValue(nil, forHTTPHeaderField: "Authorization")
            clean.setValue(nil, forHTTPHeaderField: "Cookie")
            completionHandler(clean)
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            // Permit normal TLS trust evaluation; never supply an account credential.
            completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                              ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
        }
    }
}
