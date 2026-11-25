import Foundation
@preconcurrency import AVFoundation
import YouTubeKit

/// Compiles the production TV resolver on macOS. Public trailer IDs are
/// nonsensitive fixtures; signed media URLs and raw service errors are omitted.
@main struct NativeYouTubeSmoke {
    private enum ProbeError: Error { case fixture, timeout, assetNotPlayable, protectedAsset, missingTracks }
    private struct Readiness: Sendable { let videoTracks: Int; let audioTracks: Int }

    static func main() async throws {
        try fixtures()
        emit(["stage": "fixtures", "result": "passed"])
        guard CommandLine.arguments.contains("--live") else {
            emit(["stage": "live", "result": "not_requested", "playback_verified": false])
            return
        }
        // Marvel Entertainment: Avengers Endgame official trailer (2019).
        // Warner Bros. Pictures: Interstellar official trailer (2014).
        let publicTrailers = [("TcMBFSGVi1c", "Avengers Endgame"), ("zSWdZVtXT7E", "Interstellar")]
        var successes = 0
        for (id, title) in publicTrailers {
            guard let trailer = YouTubeTrailer(videoID: id) else { throw ProbeError.fixture }
            do {
                let url = try await NativeYouTubeTrailerResolver.resolve(trailer)
                let readiness = try await inspect(url)
                successes += 1
                emit(["stage": "live", "video_id": id, "title": title, "result": "native_asset_ready",
                      "video_tracks": readiness.videoTracks, "audio_tracks": readiness.audioTracks,
                      "playback_verified": false])
            } catch let error as NativeYouTubeTrailerResolver.Failure {
                emit(["stage": "live", "video_id": id, "title": title, "result": "unavailable",
                      "category": error.rawValue, "playback_verified": false])
            } catch {
                emit(["stage": "live", "video_id": id, "title": title, "result": "asset_not_ready",
                      "category": error is ProbeError ? String(describing: error) : "native_asset_error", "playback_verified": false])
            }
        }
        // Service availability is evidence, not a deterministic CI gate.
        emit(["stage": "live_summary", "native_assets_ready": successes, "attempted": publicTrailers.count,
              "playback_verified": false])
    }

    private static func fixtures() throws {
        let id = "TcMBFSGVi1c"
        guard PublicYouTubePolicy.isMediaURL(URL(string: "https://r1.googlevideo.com/videoplayback")!),
              !PublicYouTubePolicy.isMediaURL(URL(string: "https://googlevideo.com.evil.test/video")!),
              !PublicYouTubePolicy.isMediaURL(URL(string: "https://user:pass@r1.googlevideo.com/video")!) else { throw ProbeError.fixture }
        for status in ["LOGIN_REQUIRED", "UNPLAYABLE", "AGE_CHECK_REQUIRED", "ERROR"] {
            let data = try JSONSerialization.data(withJSONObject: ["playabilityStatus": ["status": status]])
            do { try PublicYouTubePolicy.validatePlayerResponse(data, videoID: id); throw ProbeError.fixture }
            catch is PublicYouTubeError {}
        }
        let protected: [String: Any] = ["playabilityStatus": ["status": "OK"],
            "videoDetails": ["videoId": id, "thumbnail": ["thumbnails": []]],
            "streamingData": ["licenseInfos": [["drmFamily": "WIDEVINE"]]]]
        let protectedData = try JSONSerialization.data(withJSONObject: protected)
        do { try PublicYouTubePolicy.validatePlayerResponse(protectedData, videoID: id); throw ProbeError.fixture }
        catch PublicYouTubeError.protectedContent {}
    }

    private static func inspect(_ url: URL) async throws -> Readiness {
        try await withThrowingTaskGroup(of: Readiness.self) { group in
            group.addTask {
                let asset = AVURLAsset(url: url)
                return try await withTaskCancellationHandler(operation: {
                    let (playable, protected) = try await asset.load(.isPlayable, .hasProtectedContent)
                    guard playable else { throw ProbeError.assetNotPlayable }
                    guard !protected else { throw ProbeError.protectedAsset }
                    let video = try await asset.loadTracks(withMediaType: .video)
                    let audio = try await asset.loadTracks(withMediaType: .audio)
                    guard !video.isEmpty, !audio.isEmpty else { throw ProbeError.missingTracks }
                    return Readiness(videoTracks: video.count, audioTracks: audio.count)
                }, onCancel: { asset.cancelLoading() })
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 12_000_000_000)
                throw ProbeError.timeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw ProbeError.assetNotPlayable }
            return result
        }
    }

    private static func emit(_ object: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
    }
}
