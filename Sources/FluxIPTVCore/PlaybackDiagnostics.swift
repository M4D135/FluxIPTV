import Foundation

/// AVFoundation's SDK symbols are classified by the native controller. This
/// formatter never copies an error's description, arbitrary domain, or URL.
public enum PlaybackDiagnostics {
    public enum NativeFailure: Sendable {
        case unrecognizedFormat, invalidMedia, missingDecoder, decodingFailed, network, other

        fileprivate var message: String {
            switch self {
            case .unrecognizedFormat: return "AVPlayer ne reconnaît pas le format des données reçues"
            case .invalidMedia: return "AVPlayer ne parvient pas à analyser les données reçues"
            case .missingDecoder: return "Le décodeur nécessaire n’est pas disponible dans AVPlayer"
            case .decodingFailed: return "AVPlayer ne parvient pas à décoder ce média"
            case .network: return "AVPlayer n’a pas pu charger le média via le réseau"
            case .other: return "AVPlayer n’a pas pu ouvrir ce média"
            }
        }
    }

    public static func native(_ kind: NativeFailure, error: Error?) -> String {
        var codes: [String] = []
        var visited = Set<ObjectIdentifier>()
        var current = error.map { $0 as NSError }
        // Error chains can contain URLs, credentials and even cycles. Only a
        // few numeric codes and our own fixed domain labels are retained.
        while let error = current, codes.count < 3, visited.insert(ObjectIdentifier(error)).inserted {
            let domain: String
            switch error.domain {
            case "AVFoundationErrorDomain": domain = "AVFoundation"
            case NSURLErrorDomain: domain = "Réseau"
            case NSOSStatusErrorDomain: domain = "OSStatus"
            case NSPOSIXErrorDomain: domain = "POSIX"
            default: domain = "Erreur"
            }
            codes.append("\(domain) \(error.code)")
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return kind.message + (codes.isEmpty ? "." : " (\(codes.joined(separator: " ; "))).")
    }
}
