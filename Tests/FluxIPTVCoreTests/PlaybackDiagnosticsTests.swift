import XCTest
@testable import FluxIPTVCore

final class PlaybackDiagnosticsTests: XCTestCase {
    func testFormatFailureKeepsOnlySafeCodesFromTheErrorChain() {
        let secretURL = "https://private.example/username/password/episode.mkv?token=private-token"
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                                 userInfo: [NSLocalizedDescriptionKey: secretURL,
                                            NSURLErrorFailingURLStringErrorKey: secretURL])
        let error = NSError(domain: "AVFoundationErrorDomain", code: -11828,
                            userInfo: [NSLocalizedDescriptionKey: secretURL,
                                       NSLocalizedFailureReasonErrorKey: secretURL,
                                       NSUnderlyingErrorKey: underlying])
        XCTAssertEqual(PlaybackDiagnostics.native(.unrecognizedFormat, error: error),
                       "AVPlayer ne reconnaît pas le format des données reçues (AVFoundation -11828 ; Réseau -1001).")
    }

    func testUnrecognizedErrorDomainCannotLeakAnAddress() {
        let error = NSError(domain: "https://private.example/password", code: 7,
                            userInfo: [NSLocalizedDescriptionKey: "password"])
        XCTAssertEqual(PlaybackDiagnostics.native(.other, error: error),
                       "AVPlayer n’a pas pu ouvrir ce média (Erreur 7).")
        XCTAssertEqual(PlaybackDiagnostics.native(.other, error: nil),
                       "AVPlayer n’a pas pu ouvrir ce média.")
    }

    func testErrorChainIsBounded() {
        var error = NSError(domain: NSOSStatusErrorDomain, code: 4)
        for code in (1...3).reversed() {
            error = NSError(domain: NSOSStatusErrorDomain, code: code,
                            userInfo: [NSUnderlyingErrorKey: error])
        }
        XCTAssertEqual(PlaybackDiagnostics.native(.decodingFailed, error: error),
                       "AVPlayer ne parvient pas à décoder ce média (OSStatus 1 ; OSStatus 2 ; OSStatus 3).")
    }
}
