import AVFoundation
import Combine
import CoreGraphics
import Foundation

/// One inline trailer for the visible case back. Its player is shared with the
/// SceneKit material, never duplicated by a second inline video surface.
@MainActor final class CaseMediaPreviewController: ObservableObject {
    enum Phase: Equatable { case idle, preparing, still, waiting, loading, playing, ended, external, unavailable, failed }
    enum StillSource: Equatable { case none, filmFrame, trailerFrame, providerImage }

    @Published private(set) var still: CGImage?
    @Published private(set) var source: StillSource = .none
    @Published private(set) var player: AVPlayer?
    @Published private(set) var showVideo = false
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0

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
    private var backVisible = false
    private var generation = UUID()
    private var screenshotTask: Task<Void, Never>?
    private var drainingScreenshot: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
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

    var externalURL: URL? {
        guard case .external(let url) = TrailerPreviewRoute.resolve(configuration?.trailerURL) else { return nil }
        return url
    }
    var hasNativeTrailer: Bool {
        if case .native = TrailerPreviewRoute.resolve(configuration?.trailerURL) { return true }
        return false
    }
    var isLoading: Bool { phase == .loading }
    var isPlaying: Bool { phase == .playing }
    var stillLabel: String {
        switch source {
        case .filmFrame: "Image du film"
        case .trailerFrame: "Image de la bande-annonce"
        case .providerImage: "Image du fournisseur"
        case .none: "Aperçu indisponible"
        }
    }
    var statusText: String {
        switch phase {
        case .idle: ""
        case .preparing: "Préparation de l’image…"
        case .still: "Bande-annonce"
        case .waiting: "Bande-annonce automatique après \(configuration?.delay.rawValue ?? 5) s"
        case .loading: "Chargement de la bande-annonce…"
        case .playing: "Bande-annonce · sélectionner pour agrandir"
        case .ended: "Revoir la bande-annonce"
        case .external: "Bande-annonce sur le site du fournisseur"
        case .unavailable: "Bande-annonce indisponible"
        case .failed: "Aperçu indisponible · réessayer la bande-annonce"
        }
    }

    /// Synchronous lifecycle entry point. Repeating an identical visible request
    /// does not restart the countdown or the player.
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
        case .native:
            phase = automatic ? .preparing : .still
            if automatic {
                let framePreparation = screenshotTask ?? drainingScreenshot
                let backdropPreparation = artworkTask
                delayTask = Task { @MainActor [weak self] in
                    // Image generation is preparation, not part of the requested
                    // 3/5/10 seconds during which the still must remain visible.
                    await framePreparation?.value
                    guard let self, self.isCurrent(token) else { return }
                    if self.still == nil { await backdropPreparation?.value }
                    guard self.isCurrent(token) else { return }
                    guard self.still != nil else {
                        // An unavailable still must not turn an empty frame into
                        // automatic video. Explicit full-screen playback remains.
                        self.phase = .still
                        return
                    }
                    // Let the published CGImage reach the native case surface
                    // before starting its full display interval.
                    await Task.yield()
                    guard self.isCurrent(token) else { return }
                    self.phase = .waiting
                    do { try await Task.sleep(nanoseconds: UInt64(delay.rawValue) * 1_000_000_000) }
                    catch { return }
                    guard self.isCurrent(token) else { return }
                    await self.handoffToPlayer(token: token, unmute: false)
                }
            }
        }
    }

    /// Optional explicit inline start. Selecting the miniature in the interface
    /// should instead stop this controller and open the full-screen trailer.
    @discardableResult func activateTrailer(unmute: Bool = true) -> Bool {
        guard backVisible, hasNativeTrailer else { return false }
        delayTask?.cancel()
        if let player {
            player.isMuted = !unmute
            player.play()
            return true
        }
        let token = generation
        delayTask = Task { @MainActor [weak self] in
            guard let self, self.isCurrent(token) else { return }
            await self.handoffToPlayer(token: token, unmute: unmute)
        }
        return true
    }

    /// Call before film/episode/full-screen trailer playback, a neighbor change,
    /// front-face rotation, app backgrounding and inspector dismissal.
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
        if let screenshotTask { screenshotTask.cancel(); drainingScreenshot = screenshotTask }
        screenshotTask = nil
        extractionTimeout?.cancel(); extractionTimeout = nil
        generator?.cancelAllCGImageGeneration(); generator = nil
        stopPlayer()
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
                guard let self, self.isCurrent(token), self.source == .none, let image else { return }
                self.still = image.image; self.source = .providerImage
            }
        }

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
    }

    private func handoffToPlayer(token: UUID, unmute: Bool) async {
        let pending = screenshotTask ?? drainingScreenshot
        pending?.cancel()
        generator?.cancelAllCGImageGeneration()
        extractionTimeout?.cancel()
        await pending?.value
        guard isCurrent(token), case .native(let url) = TrailerPreviewRoute.resolve(configuration?.trailerURL) else { return }
        screenshotTask = nil; drainingScreenshot = nil; generator = nil; extractionTimeout = nil
        startPlayer(url: url, token: token, unmute: unmute)
    }

    private func startPlayer(url: URL, token: UUID, unmute: Bool) {
        stopPlayer()
        guard isCurrent(token) else { return }
        phase = .loading
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 2
        item.preferredPeakBitRate = 4_000_000
        let candidate = AVPlayer()
        candidate.isMuted = !unmute
        candidate.actionAtItemEnd = .pause
        candidate.preventsDisplaySleepDuringVideoPlayback = false
        candidate.automaticallyWaitsToMinimizeStalling = true

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
                    self.playbackTimeout?.cancel(); self.playbackTimeout = nil
                    self.phase = .playing
                    self.showVideo = true
                } else if observed.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    self.phase = .loading
                    self.schedulePlaybackTimeout(token: token)
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.isCurrent(token), self.player?.currentItem === item else { return }
                self.stopPlayer(); self.phase = .ended
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
        schedulePlaybackTimeout(token: token)
        candidate.play()
    }

    private func schedulePlaybackTimeout(token: UUID) {
        playbackTimeout?.cancel()
        playbackTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
            guard let self, self.isCurrent(token), self.phase == .loading else { return }
            self.stopPlayer(); self.phase = .failed
        }
    }

    private func stopPlayer() {
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
        delayTask?.cancel(); artworkTask?.cancel(); screenshotTask?.cancel(); drainingScreenshot?.cancel()
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
    }
}
