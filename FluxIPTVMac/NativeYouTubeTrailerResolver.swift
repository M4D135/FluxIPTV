// Not in the build sent to the App Store: see docs/APP-STORE.md.
#if (os(tvOS) || FLUX_NATIVE_YOUTUBE_TESTING) && !FLUX_APP_STORE
import Foundation
import YouTubeKit

/// Apple TV has no WKWebView. This local, nonofficial resolver accepts only
/// the ID already validated by TrailerPreviewRoute and returns a native URL.
/// It has no account, cookie store, remote instance or browser fallback.
enum NativeYouTubeTrailerResolver {
    enum Failure: String, Error, Sendable {
        case restricted, loginRequired, ageRestricted, protectedContent
        case unavailable, unsupported, network, timeout, invalidResponse

        var message: String {
            switch self {
            case .restricted: "Cette bande-annonce ne permet pas la lecture dans l’app."
            case .loginRequired: "YouTube demande une connexion pour cette bande-annonce."
            case .ageRestricted: "Cette bande-annonce demande une vérification d’âge."
            case .protectedContent: "Cette bande-annonce utilise un format protégé."
            case .unavailable: "Cette bande-annonce n’est plus disponible."
            case .unsupported: "Aucun format compatible Apple TV n’est disponible pour cette bande-annonce."
            case .network: "YouTube est inaccessible pour le moment. Réessayez."
            case .timeout: "La bande-annonce met trop de temps à répondre. Réessayez."
            case .invalidResponse: "YouTube ne fournit pas de lecture publique disponible pour cette bande-annonce."
            }
        }
    }

    static func resolve(_ trailer: YouTubeTrailer) async throws -> URL {
        let identifier = trailer.videoID
        // The parser and its optional JavaScript work stay off MainActor.
        let work = Task.detached(priority: .utility) {
            try await withThrowingTaskGroup(of: URL.self) { group in
                group.addTask {
                    let url = try await YouTube(videoID: identifier).nativeStreamURL()
                    try Task.checkCancellation()
                    guard PublicYouTubePolicy.isMediaURL(url) else { throw PublicYouTubeError.invalidURL }
                    return url
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 18_000_000_000)
                    throw Failure.timeout
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw Failure.unavailable }
                return result
            }
        }
        do {
            return try await withTaskCancellationHandler(operation: {
                let url = try await work.value
                try Task.checkCancellation()
                return url
            }, onCancel: { work.cancel() })
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as Failure {
            throw error
        } catch let error as PublicYouTubeError {
            switch error {
            case .restricted: throw Failure.restricted
            case .loginRequired: throw Failure.loginRequired
            case .ageRestricted: throw Failure.ageRestricted
            case .protectedContent: throw Failure.protectedContent
            case .unavailable: throw Failure.unavailable
            case .unsupported, .invalidURL, .invalidIdentifier: throw Failure.unsupported
            case .network: throw Failure.network
            case .timeout: throw Failure.timeout
            case .invalidResponse: throw Failure.invalidResponse
            }
        } catch let error as URLError {
            if Task.isCancelled { throw CancellationError() }
            throw error.code == .timedOut ? Failure.timeout : Failure.network
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw Failure.invalidResponse
        }
    }
}
#endif
