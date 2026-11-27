import AVFoundation
import Combine
import CoreGraphics
import Foundation

/// One trailer session for the detail page and its expanded presentation.
/// tvOS resolves public YouTube streams locally into the same AVPlayer. Mac
/// and iOS retain the official embedded player.
@MainActor final class CaseMediaPreviewController: ObservableObject {
    enum Phase: Equatable { case idle, preparing, still, waiting, loading, playing, paused, blocked, ended, external, unavailable, failed }
    enum StillSource: Equatable { case none, filmFrame, trailerFrame, providerImage, trailerThumbnail }

    @Published private(set) var still: CGImage?
    @Published private(set) var source: StillSource = .none
    @Published private(set) var player: AVPlayer?
    @Published private(set) var showVideo = false
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var failureMessage: String?
    // Retain the latest audio intent while the native URL or web session is
    // still loading. Returning to the silent inline preview can happen before
    // either player exists, so applying mute only to a player loses that choice.
    @Published private(set) var isMuted = true
    #if os(macOS) || os(iOS)
    @Published private(set) var youtubeSession: YouTubeTrailerSession?
    private var youtubeCleanup: (@MainActor @Sendable () -> Void)?
    #if FLUX_TRAILER_TESTING
    // The standalone native harness supplies the same local IFrame boundary
    // used by YouTubeTrailerSession; production has no alternate provider.
    var iframeAPIFixture: String?
    #endif
    #endif

    private struct Configuration: Equatable {
        let itemID: String
        let filmURL: URL?
        let backdropURL: URL?
        let trailerURL: URL?
        let delay: TrailerPreviewDelay
        let automatic: Bool
    }
    private static let frameCache: NSCache<NSString, FluxBitmap> = {
        let cache = NSCache<NSString, FluxBitmap>()
        cache.countLimit = 6
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    private var configuration: Configuration?
    // Session activity is independent of the selected case's orientation.
    private var backVisible = false
    private var backFacing = false
    private var generation = UUID()
    private var screenshotTask: Task<Void, Never>?
    private var drainingScreenshot: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var delayTask: Task<Void, Never>?
    private var extractionTimeout: Task<Void, Never>?
    private var playbackTimeout: Task<Void, Never>?
    private var generator: AVAssetImageGenerator?
    private var extractionExpired = false
    private var itemObservation: NSKeyValueObservation?
    private var transportObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    // A nonisolated deinit may copy this Sendable action without reading the
    // actor-isolated @Published player. The action owns only playback resources.
    private var playerCleanup: (@MainActor @Sendable () -> Void)?
    private var youtubeViewportEligible = false
    private var nativeWantsPlayback = false

    var externalURL: URL? {
        switch TrailerPreviewRoute.resolve(configuration?.trailerURL) {
        case .external(let url): return url
        case .youtube(let video): return video.watchURL
        default: return nil
        }
    }
    var hasInlineTrailer: Bool {
        switch TrailerPreviewRoute.resolve(configuration?.trailerURL) {
        case .native, .youtube: return true
        default: return false
        }
    }
    var isLoading: Bool { phase == .loading }
    var isPlaying: Bool { phase == .playing }
    var stillLabel: String {
        switch source {
        case .filmFrame: "Image du film"
        case .trailerFrame: "Image de la bande-annonce"
        case .providerImage: "Image du fournisseur"
        case .trailerThumbnail: "Miniature de la bande-annonce"
        case .none: "Aperçu indisponible"
        }
    }
    var statusText: String {
        switch phase {
        case .idle: ""
        case .preparing: "Préparation de l’image…"
        case .still:
            if case .youtube = TrailerPreviewRoute.resolve(configuration?.trailerURL), !youtubeViewportEligible { "Agrandir pour lire la bande-annonce" }
            else { "Bande-annonce" }
        case .waiting: "Bande-annonce automatique après \(configuration?.delay.rawValue ?? 5) s"
        case .loading: "Chargement de la bande-annonce…"
        case .playing: "Bande-annonce · sélectionner pour agrandir"
        case .paused: "Bande-annonce en pause"
        case .blocked: "Sélectionnez Lire pour démarrer la bande-annonce"
        case .ended: "Revoir la bande-annonce"
        case .external: "Format de bande-annonce non pris en charge"
        case .unavailable: "Aucune bande-annonce fournie pour ce titre"
        case .failed: failureMessage ?? "Lecture indisponible · réessayer la bande-annonce"
        }
    }

    /// Synchronous lifecycle entry point. backVisible means that the selected
    /// case's preview session is active, even while its front faces the camera.
    /// Use setBackFacing for orientation changes without recreating the player.
    func update(item: IPTVItem, details: IPTVDetails, filmURL: URL?, backVisible: Bool,
                automatic: Bool, delay: TrailerPreviewDelay) {
        guard !Task.isCancelled else { return }
        let next = Configuration(itemID: item.id,
                                 filmURL: item.isSeriesCollection ? nil : filmURL,
                                 backdropURL: item.backdropURL,
                                 trailerURL: details.trailerURL,
                                 delay: delay, automatic: automatic)
        let changed = configuration != next
        let becameVisible = backVisible && !self.backVisible
        guard changed || becameVisible || self.backVisible != backVisible else { return }
        let previousScreenshot = screenshotTask ?? drainingScreenshot
        cancelWork(clearStill: changed)
        configuration = next
        self.backVisible = backVisible
        guard backVisible else { phase = .idle; return }

        let token = generation
        loadStill(next, token: token, after: previousScreenshot)
        switch TrailerPreviewRoute.resolve(next.trailerURL) {
        case .unavailable: phase = .unavailable
        case .external: phase = .external
        case .youtube, .native:
            phase = automatic && backFacing ? .preparing : .still
            if automatic && backFacing { queueAutomaticStart(token: token) }
        }
    }

    private func queueAutomaticStart(token: UUID) {
        guard let request = configuration, request.automatic, backFacing else { return }
        delayTask?.cancel()
        let framePreparation = screenshotTask ?? drainingScreenshot
        delayTask = Task { @MainActor [weak self] in
            await framePreparation?.value
            guard let self, self.isCurrent(token), self.backFacing else { return }
            // Give the still/thumbnail a bounded chance to arrive. Its failure
            // must not suppress an otherwise available trailer indefinitely.
            for _ in 0..<20 where self.still == nil {
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                guard self.isCurrent(token), self.backFacing else { return }
            }
            await Task.yield()
            guard self.isCurrent(token), self.backFacing else { return }
            if case .youtube = TrailerPreviewRoute.resolve(request.trailerURL), !self.youtubeViewportEligible {
                self.phase = .still; self.delayTask = nil; return
            }
            self.phase = .waiting
            do { try await Task.sleep(nanoseconds: UInt64(request.delay.rawValue) * 1_000_000_000) }
            catch { return }
            guard self.isCurrent(token), self.backFacing else { return }
            if case .youtube = TrailerPreviewRoute.resolve(request.trailerURL), !self.youtubeViewportEligible {
                self.phase = .still
                self.delayTask = nil
                return
            }
            await self.handoffToPlayer(token: token)
            guard self.isCurrent(token) else { return }
            self.delayTask = nil
        }
    }

    /// The same session moves into the expanded native container. No restart,
    /// second web view or second audio decoder is needed on promotion.
    @discardableResult func activateTrailer(unmute: Bool = true) -> Bool {
        guard backVisible, backFacing, hasInlineTrailer else { return false }
        if unmute { setMuted(false) }
        delayTask?.cancel(); delayTask = nil
        failureMessage = nil
        #if os(macOS) || os(iOS)
        if let youtubeSession, phase != .failed {
            youtubeSession.play(unmute: unmute)
            return true
        }
        #endif
        if let player {
            if phase == .ended { player.seek(to: .zero); progress = 0 }
            nativeWantsPlayback = true
            requestNativePlayback(player)
            return true
        }
        let token = generation
        delayTask = Task { @MainActor [weak self] in
            guard let self, self.isCurrent(token) else { return }
            await self.handoffToPlayer(token: token)
            guard self.isCurrent(token) else { return }
            self.delayTask = nil
        }
        return true
    }

    /// Only the first automatic start depends on the eligible viewport. Once
    /// started, rotation preserves playback until the front faces the camera.
    func setYouTubeViewportEligible(_ eligible: Bool) {
        guard eligible != youtubeViewportEligible else { return }
        objectWillChange.send()
        youtubeViewportEligible = eligible
        #if os(macOS) || os(iOS)
        if youtubeSession == nil, eligible, backVisible, backFacing, configuration?.automatic == true, delayTask == nil,
                  case .youtube = TrailerPreviewRoute.resolve(configuration?.trailerURL), phase == .still {
            queueAutomaticStart(token: generation)
        }
        #elseif os(tvOS)
        if player == nil, eligible, backVisible, backFacing, configuration?.automatic == true, delayTask == nil,
           case .youtube = TrailerPreviewRoute.resolve(configuration?.trailerURL), phase == .still {
            queueAutomaticStart(token: generation)
        }
        #endif
    }

    /// Pause the retained session on the front, then resume the same position
    /// on the back only if it was playing or loading before the turn.
    func setBackFacing(_ visible: Bool) {
        guard backFacing != visible else { return }
        backFacing = visible
        if !visible {
            delayTask?.cancel(); delayTask = nil
            playbackTimeout?.cancel(); playbackTimeout = nil
            if [.preparing, .waiting].contains(phase) { phase = .still }
        }
        #if os(macOS) || os(iOS)
        if let youtubeSession {
            youtubeSession.setBackFacing(visible)
            return
        }
        #endif
        if let player {
            if !visible {
                player.pause()
                if nativeWantsPlayback { phase = .paused }
            } else if nativeWantsPlayback, phase != .ended {
                requestNativePlayback(player)
            }
        } else if visible, backVisible, configuration?.automatic == true, delayTask == nil,
                  [.still, .preparing, .waiting].contains(phase) {
            queueAutomaticStart(token: generation)
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.isMuted = muted
        #if os(macOS) || os(iOS)
        youtubeSession?.setMuted(muted)
        #endif
    }
    func toggleMuted() {
        #if os(macOS) || os(iOS)
        if let youtubeSession { setMuted(!youtubeSession.isMuted); return }
        #endif
        setMuted(!isMuted)
    }
    func togglePlayback() {
        // Failed web sessions intentionally reject commands. An explicit retry
        // must dispose that session and pass through the normal creation path.
        if phase == .failed { activateTrailer(unmute: false); return }
        #if os(macOS) || os(iOS)
        if let youtubeSession { youtubeSession.togglePlayback(); return }
        #endif
        guard let player else { activateTrailer(unmute: false); return }
        if nativeWantsPlayback {
            nativeWantsPlayback = false
            playbackTimeout?.cancel(); playbackTimeout = nil
            player.pause(); phase = .paused
        } else { activateTrailer(unmute: false) }
    }
    func seek(by delta: Double) {
        #if os(macOS) || os(iOS)
        if let youtubeSession { youtubeSession.seek(by: delta); return }
        #endif
        guard let player else { return }
        let seconds = player.currentTime().seconds
        if seconds.isFinite { player.seek(to: CMTime(seconds: max(0, seconds + delta), preferredTimescale: 600)) }
    }

    /// Call before film/episode playback, a neighbor change, app backgrounding
    /// and inspector dismissal. A front-face rotation only uses setBackFacing.
    func stop() {
        cancelWork(clearStill: true)
        configuration = nil
        backVisible = false
        phase = .idle
    }

    /// The full-screen presentation can await a cancelled frame extraction too,
    /// ensuring that its new decoder starts only after the old request drains.
    func stopAndWait() async {
        let pending = screenshotTask ?? drainingScreenshot
        stop()
        await pending?.value
    }

    private func isCurrent(_ token: UUID) -> Bool { generation == token && backVisible && !Task.isCancelled }

    private func cancelWork(clearStill: Bool) {
        generation = UUID()
        delayTask?.cancel(); delayTask = nil
        artworkTask?.cancel(); artworkTask = nil
        thumbnailTask?.cancel(); thumbnailTask = nil
        if let screenshotTask { screenshotTask.cancel(); drainingScreenshot = screenshotTask }
        screenshotTask = nil
        extractionTimeout?.cancel(); extractionTimeout = nil
        generator?.cancelAllCGImageGeneration(); generator = nil
        stopPlayer()
        stopYouTube()
        failureMessage = nil
        isMuted = true
        if clearStill { still = nil; source = .none }
    }

    private func loadStill(_ request: Configuration, token: UUID, after previous: Task<Void, Never>?) {
        // Only real backdrop metadata is used. The poster is deliberately not
        // substituted for a movie frame.
        if let backdrop = request.backdropURL {
            if source == .none, let cached = ArtworkLoader.cached(backdrop, wallpaper: true) {
                still = cached.image; source = .providerImage
            }
            artworkTask = Task { @MainActor [weak self] in
                let image = await ArtworkLoader.load(backdrop, wallpaper: true)
                guard let self, self.isCurrent(token), self.source == .none || self.source == .trailerThumbnail, let image else { return }
                self.still = image.image; self.source = .providerImage
            }
        }
        if case .youtube(let video) = TrailerPreviewRoute.resolve(request.trailerURL) {
            if source == .none, let cached = ArtworkLoader.cached(video.thumbnailURL) {
                still = cached.image; source = .trailerThumbnail
            }
            thumbnailTask = Task { @MainActor [weak self] in
                let image = await ArtworkLoader.load(video.thumbnailURL)
                guard let self, self.isCurrent(token), self.source == .none, let image else { return }
                // A YouTube thumbnail is labelled honestly; never call it an
                // extracted frame from the film or overwrite a real film still.
                self.still = image.image; self.source = .trailerThumbnail
            }
        }

        #if !os(tvOS)
        // Apple TV uses the supplied still/thumbnail while its one trailer
        // decoder loads. Do not open the feature film merely for a preview.
        let frameURL: URL?
        let frameSource: StillSource
        if let filmURL = request.filmURL, ["https", "http", "file"].contains(filmURL.scheme?.lowercased() ?? "") {
            frameURL = filmURL; frameSource = .filmFrame
        } else if case .native(let trailerURL) = TrailerPreviewRoute.resolve(request.trailerURL) {
            frameURL = trailerURL; frameSource = .trailerFrame
        } else { frameURL = nil; frameSource = .none }
        guard let frameURL else { return }
        let cacheKey = (frameURL.absoluteString + (frameSource == .filmFrame ? "|film12" : "|trailer1")) as NSString
        if let cached = Self.frameCache.object(forKey: cacheKey) {
            still = cached.image; source = frameSource
            return
        }
        screenshotTask = Task { @MainActor [weak self] in
            // A fast neighbor change must not overlap two frame decoders.
            await previous?.value
            guard let self, self.isCurrent(token) else { return }
            self.drainingScreenshot = nil
            let asset = AVURLAsset(url: frameURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 960, height: 540)
            imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
            imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
            self.generator = imageGenerator
            self.extractionExpired = false
            self.extractionTimeout = Task { @MainActor [weak self, weak imageGenerator] in
                do { try await Task.sleep(nanoseconds: 2_400_000_000) } catch { return }
                guard let self, self.isCurrent(token) else { return }
                self.extractionExpired = true
                imageGenerator?.cancelAllCGImageGeneration()
            }
            var image: CGImage?
            do {
                image = try await imageGenerator.image(at: CMTime(seconds: frameSource == .filmFrame ? 12 : 1, preferredTimescale: 600)).image
            } catch {}
            // Short files may not contain the requested twelve-second frame.
            if image == nil, self.isCurrent(token), !self.extractionExpired {
                image = try? await imageGenerator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
            }
            guard self.generation == token else { return }
            self.extractionTimeout?.cancel(); self.extractionTimeout = nil
            self.generator = nil
            guard self.isCurrent(token), let image else { return }
            let bitmap = FluxBitmap(image)
            Self.frameCache.setObject(bitmap, forKey: cacheKey, cost: image.bytesPerRow * image.height)
            self.still = image; self.source = frameSource
        }
        #endif
    }

    private func handoffToPlayer(token: UUID) async {
        let pending = screenshotTask ?? drainingScreenshot
        pending?.cancel()
        generator?.cancelAllCGImageGeneration()
        extractionTimeout?.cancel()
        await pending?.value
        guard isCurrent(token), backFacing else { return }
        screenshotTask = nil; drainingScreenshot = nil; generator = nil; extractionTimeout = nil
        switch TrailerPreviewRoute.resolve(configuration?.trailerURL) {
        case .native(let url): startPlayer(url: url, token: token)
        case .youtube(let video):
            #if os(macOS) || os(iOS)
            startYouTube(video, token: token)
            #elseif os(tvOS) && FLUX_APP_STORE
            // The build of the App Store reads no YouTube stream itself.
            _ = video
            failureMessage = "Les bandes-annonces YouTube ne se lisent pas sur l’Apple TV dans cette version."
            phase = .failed
            #elseif os(tvOS)
            phase = .loading
            do {
                let url = try await NativeYouTubeTrailerResolver.resolve(video)
                guard isCurrent(token), backFacing else { return }
                startPlayer(url: url, token: token)
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(token), backFacing else { return }
                failureMessage = (error as? NativeYouTubeTrailerResolver.Failure)?.message
                    ?? "La bande-annonce est momentanément indisponible. Réessayez."
                phase = .failed
            }
            #endif
        default: break
        }
    }

    #if os(macOS) || os(iOS)
    private func startYouTube(_ video: YouTubeTrailer, token: UUID) {
        stopPlayer(); stopYouTube()
        guard isCurrent(token) else { return }
        phase = .loading
        #if FLUX_TRAILER_TESTING
        let candidate = iframeAPIFixture.map { YouTubeTrailerSession(trailer: video, iframeAPIFixture: $0) }
            ?? YouTubeTrailerSession(trailer: video)
        #else
        let candidate = YouTubeTrailerSession(trailer: video)
        #endif
        candidate.setBackFacing(backFacing)
        candidate.onReady = { [weak self, weak candidate] in
            guard let self, let candidate, self.isCurrent(token), self.youtubeSession === candidate else { return }
            // The iframe is ready before the session asks it to play. Reveal
            // the real player first, so autoplay never starts while hidden.
            self.showVideo = true
        }
        candidate.onStateChange = { [weak self, weak candidate] state in
            guard let self, let candidate, self.isCurrent(token), self.youtubeSession === candidate else { return }
            switch state {
            case .idle: break
            case .loading: self.phase = .loading
            case .playing:
                self.phase = .playing; self.showVideo = true
            case .paused: self.phase = .paused
            case .ended: self.phase = .ended
            case .blocked: self.phase = .blocked; self.showVideo = true
            case .failed(let reason): self.failureMessage = reason; self.phase = .failed
            }
        }
        youtubeSession = candidate
        // The embedded player's own mute control also feeds the shared UI.
        // Ignore only its initial default; start(muted:) applies our retained
        // intent immediately and all subsequent samples are authoritative.
        let muteObservation = candidate.$isMuted.dropFirst().sink { [weak self, weak candidate] muted in
            guard let self, let candidate, self.isCurrent(token), self.youtubeSession === candidate else { return }
            self.isMuted = muted
        }
        youtubeCleanup = { @MainActor [candidate, muteObservation] in
            muteObservation.cancel()
            candidate.onReady = nil; candidate.onStateChange = nil; candidate.stop()
        }
        candidate.start(muted: isMuted)
    }
    #endif

    private func stopYouTube() {
        #if os(macOS) || os(iOS)
        let cleanup = youtubeCleanup
        youtubeCleanup = nil
        cleanup?()
        youtubeSession = nil
        #endif
    }

    private func startPlayer(url: URL, token: UUID) {
        stopPlayer()
        stopYouTube()
        guard isCurrent(token) else { return }
        phase = .loading
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 2
        item.preferredPeakBitRate = 4_000_000
        item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
        let candidate = AVPlayer()
        candidate.isMuted = isMuted
        candidate.actionAtItemEnd = .pause
        candidate.preventsDisplaySleepDuringVideoPlayback = false
        candidate.automaticallyWaitsToMinimizeStalling = true
        nativeWantsPlayback = true

        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(token), self.player?.currentItem === item else { return }
                if item.status == .failed { self.stopPlayer(); self.phase = .failed }
            }
        }
        transportObservation = candidate.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrent(token), self.player === observed else { return }
                if observed.timeControlStatus == .playing {
                    guard self.backFacing else { observed.pause(); return }
                    self.nativeWantsPlayback = true
                    self.playbackTimeout?.cancel(); self.playbackTimeout = nil
                    self.phase = .playing
                    self.showVideo = true
                } else if observed.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    guard self.backFacing else { observed.pause(); return }
                    self.nativeWantsPlayback = true
                    self.phase = .loading
                    self.schedulePlaybackTimeout(token: token)
                } else if self.showVideo, self.phase != .ended {
                    if self.backFacing { self.nativeWantsPlayback = false }
                    self.playbackTimeout?.cancel(); self.playbackTimeout = nil
                    self.phase = .paused
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.isCurrent(token), self.player?.currentItem === item else { return }
                self.nativeWantsPlayback = false
                self.playbackTimeout?.cancel(); self.playbackTimeout = nil
                self.progress = 1
                self.phase = .ended
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.isCurrent(token), self.player?.currentItem === item else { return }
                self.stopPlayer(); self.phase = .failed
            }
        }
        player = candidate
        candidate.replaceCurrentItem(with: item)
        let timeObserver = candidate.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self, weak candidate] time in
            Task { @MainActor [weak self, weak candidate] in
                guard let self, let candidate, self.isCurrent(token), self.player === candidate,
                      let duration = candidate.currentItem?.duration.seconds,
                      duration.isFinite, duration > 0, time.seconds.isFinite else { return }
                self.progress = min(1, max(0, time.seconds / duration))
            }
        }
        playerCleanup = { @MainActor [candidate, timeObserver] in
            candidate.removeTimeObserver(timeObserver)
            candidate.pause()
            candidate.replaceCurrentItem(with: nil)
        }
        requestNativePlayback(candidate)
    }

    private func requestNativePlayback(_ candidate: AVPlayer) {
        guard backVisible, backFacing else { phase = .paused; return }
        if candidate.timeControlStatus == .playing {
            phase = .playing
            showVideo = true
            return
        }
        phase = .loading
        schedulePlaybackTimeout(token: generation)
        candidate.play()
    }

    private func schedulePlaybackTimeout(token: UUID) {
        playbackTimeout?.cancel()
        playbackTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
            guard let self, self.isCurrent(token), self.backFacing, self.phase == .loading else { return }
            self.stopPlayer(); self.phase = .failed
        }
    }

    private func stopPlayer() {
        nativeWantsPlayback = false
        playbackTimeout?.cancel(); playbackTimeout = nil
        itemObservation?.invalidate(); itemObservation = nil
        transportObservation?.invalidate(); transportObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }; endObserver = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }; failureObserver = nil
        let cleanup = playerCleanup
        playerCleanup = nil
        cleanup?()
        player = nil
        showVideo = false
        progress = 0
    }

    deinit {
        delayTask?.cancel(); artworkTask?.cancel(); thumbnailTask?.cancel(); screenshotTask?.cancel(); drainingScreenshot?.cancel()
        extractionTimeout?.cancel(); playbackTimeout?.cancel()
        generator?.cancelAllCGImageGeneration()
        itemObservation?.invalidate(); transportObservation?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        if let cleanup = playerCleanup {
            // Never capture self after destruction or assume which executor
            // released its final reference. The player is stopped on MainActor.
            Task { @MainActor [cleanup] in cleanup() }
        }
        #if os(macOS) || os(iOS)
        if let cleanup = youtubeCleanup { Task { @MainActor [cleanup] in cleanup() } }
        #endif
    }
}
