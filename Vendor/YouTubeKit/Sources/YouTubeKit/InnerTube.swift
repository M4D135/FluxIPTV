// Derived from YouTubeKit 0.4.10 (MIT); see UPSTREAM.json.
// Flux subset: public player requests only, no account or restriction overrides.
import Foundation

final class InnerTube {
    enum ClientType { case visionOS, tvSamsung, web }

    private struct Client: Encodable {
        let clientName: String
        let clientVersion: String
        var deviceMake: String? = nil
        var deviceModel: String? = nil
        var osName: String? = nil
        var osVersion: String? = nil
    }
    private struct Context: Encodable { let client: Client }
    private struct PlayerRequest: Encodable {
        let context: Context
        let videoId: String
        let playbackContext: PlaybackContext
    }
    private struct PlaybackContext: Encodable {
        let contentPlaybackContext: Content
        struct Content: Encodable { let signatureTimestamp: Int? }
    }

    private let client: Client
    private let clientID: Int
    private let userAgent: String
    private let signatureTimestamp: Int?
    private let ytcfg: Extraction.YtCfg

    init(client type: ClientType, signatureTimestamp: Int?, ytcfg: Extraction.YtCfg) {
        switch type {
        case .visionOS:
            client = Client(clientName: "VISIONOS", clientVersion: "1.02", deviceMake: "Apple",
                            deviceModel: "RealityDevice17,1", osName: "visionOS", osVersion: "26.5.23O471")
            clientID = 101
            userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        case .tvSamsung:
            client = Client(clientName: "TVHTML5", clientVersion: "5.20260707", deviceMake: "Samsung",
                            deviceModel: "UKS9800", osName: "Tizen", osVersion: "2.4.0")
            clientID = 7
            userAgent = "Mozilla/5.0 (SMART-TV; Linux; Tizen 2.4.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/2.4.0 TV Safari/538.1"
        case .web:
            client = Client(clientName: "WEB", clientVersion: "2.20260708.00.00")
            clientID = 1
            userAgent = "Mozilla/5.0"
        }
        self.signatureTimestamp = signatureTimestamp
        self.ytcfg = ytcfg
    }

    func player(videoID: String) async throws -> VideoInfo {
        guard PublicYouTubePolicy.isVideoID(videoID) else { throw PublicYouTubeError.invalidIdentifier }
        let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!
        let playback = PlaybackContext(contentPlaybackContext: .init(signatureTimestamp: signatureTimestamp))
        let payload = PlayerRequest(context: Context(client: client), videoId: videoID, playbackContext: playback)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue(client.clientVersion, forHTTPHeaderField: "X-Youtube-Client-Version")
        request.setValue(String(clientID), forHTTPHeaderField: "X-Youtube-Client-Name")
        if let visitor = ytcfg.visitorData { request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id") }
        let data = try await PublicYouTubeHTTP.data(for: request)
        let result = try JSONDecoder().decode(VideoInfo.self, from: data)
        // Never fall through from denied playback into a different client.
        try PublicYouTubePolicy.requirePublic(result, videoID: videoID)
        return result
    }

    struct VideoInfo: Decodable {
        let playabilityStatus: PlayabilityStatus?
        let streamingData: StreamingData?
        let videoDetails: VideoDetails?

        struct PlayabilityStatus: Decodable {
            let status: String?
            let reason: String?
            let playableInEmbed: Bool?
        }

        struct VideoDetails: Decodable {
            let videoId: String
            let title: String?
            let shortDescription: String?
            let isLiveContent: Bool?
            let thumbnail: Thumbnail?

            struct Thumbnail: Decodable {
                let thumbnails: [ThumbnailMetadata]

                struct ThumbnailMetadata: Decodable {
                    let url: URL
                    let width: Int
                    let height: Int
                }
            }
        }
    }
    
    struct StreamingData: Decodable {
        let expiresInSeconds: String?
        let formats: [Format]?
        let adaptiveFormats: [Format]? // actually slightly different Format object (TODO)
        let onesieStreamingUrl: String?
        let hlsManifestUrl: String?
        let licenseInfos: [LicenseInfo]?
        struct LicenseInfo: Decodable {}
        
        struct Format: Decodable {
            let itag: Int
            var url: String?
            let mimeType: String
            let bitrate: Int?
            let width: Int?
            let height: Int?
            let lastModified: String?
            let contentLength: String?
            let quality: String?
            let fps: Int?
            let qualityLabel: String?
            let averageBitrate: Int?
            let audioQuality: String?
            let approxDurationMs: String?
            let audioSampleRate: String?
            let audioChannels: Int?
            let audioTrack: AudioTrack?
            let drmFamilies: [String]?
            let signatureCipher: String? // not tested yet
            var s: String? // assigned from Extraction.applyDescrambler
            var sp: String? // signature parameter name from signatureCipher
        }
        
        struct AudioTrack: Decodable {
            let displayName: String
            let id: String
            let audioIsDefault: Bool
        }
    }
    

}

