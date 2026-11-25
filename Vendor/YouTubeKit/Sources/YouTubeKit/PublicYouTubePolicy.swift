import Foundation

/// These errors intentionally contain no signed URL, response body or account data.
public enum PublicYouTubeError: String, Error, Sendable {
    case invalidIdentifier, invalidURL, restricted, loginRequired, ageRestricted
    case protectedContent, unavailable, unsupported, invalidResponse, network, timeout
}

/// Shared by the extractor and deterministic native smoke tests.
public enum PublicYouTubePolicy {
    public static func isVideoID(_ value: String) -> Bool {
        value.utf8.count == 11 && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }

    public static func isMediaURL(_ url: URL) -> Bool {
        guard isHTTPS(url), let host = url.host?.lowercased() else { return false }
        return host == "googlevideo.com" || host.hasSuffix(".googlevideo.com")
    }

    static func isRequestURL(_ url: URL) -> Bool {
        isHTTPS(url) && ["youtube.com", "www.youtube.com"].contains(url.host?.lowercased() ?? "")
    }

    private static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443) && url.fragment == nil
    }

    /// Validates the same response shape used by watch pages and /player.
    /// Exposed for fixture tests; it never makes a network request.
    public static func validatePlayerResponse(_ data: Data, videoID: String, ageRestricted: Bool = false) throws {
        let info = try JSONDecoder().decode(InnerTube.VideoInfo.self, from: data)
        try requirePublic(info, videoID: videoID, ageRestricted: ageRestricted)
    }

    static func requirePublic(_ info: InnerTube.VideoInfo, videoID: String, ageRestricted: Bool = false) throws {
        guard isVideoID(videoID) else { throw PublicYouTubeError.invalidIdentifier }
        guard !ageRestricted else { throw PublicYouTubeError.ageRestricted }
        switch info.playabilityStatus?.status {
        case "OK": break
        case "LOGIN_REQUIRED": throw PublicYouTubeError.loginRequired
        case "UNPLAYABLE", "CONTENT_CHECK_REQUIRED", "AGE_CHECK_REQUIRED": throw PublicYouTubeError.restricted
        case "ERROR": throw PublicYouTubeError.unavailable
        default: throw PublicYouTubeError.invalidResponse
        }
        guard info.playabilityStatus?.playableInEmbed != false else { throw PublicYouTubeError.restricted }
        guard info.videoDetails?.videoId == videoID else { throw PublicYouTubeError.invalidResponse }
        guard info.videoDetails?.isLiveContent != true else { throw PublicYouTubeError.unsupported }
        if let streaming = info.streamingData {
            let formats = (streaming.formats ?? []) + (streaming.adaptiveFormats ?? [])
            guard streaming.licenseInfos?.isEmpty ?? true,
                  !formats.contains(where: { !($0.drmFamilies?.isEmpty ?? true) }) else {
                throw PublicYouTubeError.protectedContent
            }
        }
    }

    /// Returns clear, muxed H.264/AAC MP4 candidates. Separate DASH tracks are
    /// deliberately excluded: the app creates exactly one native decoder.
    static func supportedProgressive(_ formats: [InnerTube.StreamingData.Format]) -> [Stream] {
        formats.compactMap { format -> Stream? in
            guard format.drmFamilies?.isEmpty ?? true,
                  let stream = try? Stream(format: format), isMediaURL(stream.url),
                  stream.includesVideoAndAudioTrack, stream.fileExtension == .mp4,
                  stream.videoCodec == .avc1, stream.audioCodec == .mp4a,
                  stream.isNativelyPlayable, (stream.videoResolution ?? 0) <= 1080 else { return nil }
            return stream
        }.sorted {
            if $0.videoResolution != $1.videoResolution { return ($0.videoResolution ?? 0) > ($1.videoResolution ?? 0) }
            return ($0.bitrate ?? 0) < ($1.bitrate ?? 0)
        }
    }
}
