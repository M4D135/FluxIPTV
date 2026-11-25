// Derived from YouTubeKit 0.4.10 (MIT); see UPSTREAM.json.
// Local extraction of an already-public video for a single native player.
import Foundation

public final class YouTube {
    public let videoID: String

    public init(videoID: String) {
        self.videoID = videoID
    }

    /// No OAuth, browser cookies, remote server or age/login override exists in
    /// this subset. Each response must explicitly permit public playback.
    public func nativeStreamURL() async throws -> URL {
        guard PublicYouTubePolicy.isVideoID(videoID) else { throw PublicYouTubeError.invalidIdentifier }
        try Task.checkCancellation()
        let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
        var request = URLRequest(url: watchURL)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        let data = try await PublicYouTubeHTTP.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { throw PublicYouTubeError.invalidResponse }
        let watchInfo = try Extraction.getVideoInfo(fromHTML: html)
        try PublicYouTubePolicy.requirePublic(watchInfo, videoID: videoID,
                                             ageRestricted: Extraction.isAgeRestricted(watchHTML: html))
        try Task.checkCancellation()
        if let direct = directURL(watchInfo) { return direct }

        let config = try Extraction.extractYtCfg(from: html)
        guard let scriptURL = URL(string: try Extraction.jsURL(html: html)),
              PublicYouTubePolicy.isRequestURL(scriptURL) else { throw PublicYouTubeError.invalidURL }
        let scriptData = try await PublicYouTubeHTTP.data(for: URLRequest(url: scriptURL))
        guard let script = String(data: scriptData, encoding: .utf8) else { throw PublicYouTubeError.invalidResponse }
        let timestamp = Extraction.extractSignatureTimestamp(fromJS: script)
        var infos = [watchInfo]
        // These are normal upstream public clients, not embedded/creator
        // clients. A denied response terminates the attempt immediately.
        for client in [InnerTube.ClientType.visionOS, .tvSamsung, .web] {
            try Task.checkCancellation()
            let info = try await InnerTube(client: client, signatureTimestamp: timestamp, ytcfg: config).player(videoID: videoID)
            if let direct = directURL(info) { return direct }
            infos.append(info)
        }

        // Most supported HLS sources avoid this path entirely. The bounded
        // public player script is evaluated locally; no browser is created.
        try Task.checkCancellation()
        for info in infos {
            guard let data = info.streamingData else { continue }
            var formats = Extraction.applyDescrambler(streamData: data)
            // Decode only progressive H.264/AAC candidates, never DASH pairs.
            formats = formats.filter {
                $0.mimeType.hasPrefix("video/mp4") && $0.mimeType.contains("avc1") && $0.mimeType.contains("mp4a")
            }
            guard !formats.isEmpty else { continue }
            try Task.checkCancellation()
            try Extraction.applySignature(streamManifest: &formats, videoInfo: info, js: script)
            try Task.checkCancellation()
            if let native = PublicYouTubePolicy.supportedProgressive(formats).first { return native.url }
        }
        throw PublicYouTubeError.unsupported
    }

    private func directURL(_ info: InnerTube.VideoInfo) -> URL? {
        guard let data = info.streamingData else { return nil }
        // AVPlayer owns the adaptive HLS presentation (one player/decoder).
        if let text = data.hlsManifestUrl, let url = URL(string: text), PublicYouTubePolicy.isMediaURL(url) {
            return url
        }
        let formats = (data.formats ?? []).filter { format in
            guard format.signatureCipher == nil, let text = format.url,
                  let components = URLComponents(string: text) else { return false }
            return !(components.queryItems ?? []).contains(where: { $0.name == "n" })
        }
        return PublicYouTubePolicy.supportedProgressive(formats).first?.url
    }
}

