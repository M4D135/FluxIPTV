import AVFoundation
import Combine
import Foundation

/// One decoder for the selected TV channel, owned by the catalogue rather than
/// by its cells. Selection changes cancel both the delay and the previous item.
@MainActor final class LiveTVPreviewController: ObservableObject {
    enum Phase: Equatable { case idle, waiting, loading, playing, failed }
    @Published private(set) var player: AVPlayer?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isMuted = true
    /// The player and its status belong to one channel, including URL failures
    /// that happen before a playback request can be scheduled.
    @Published private(set) var previewedItemID: String?

    private struct Request: Equatable {
        let id: String
        let urls: [URL]
        let delay: LiveTVPreviewDelay
        let enabled: Bool
    }
    private var request: Request?
    private var generation = UUID()
    private var attempt = UUID()
    private var delayTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var itemObservation: NSKeyValueObservation?
    private var transportObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?
    private var playerCleanup: (@MainActor @Sendable () -> Void)?

    func schedule(id: String, urls: [URL], delay: LiveTVPreviewDelay, enabled: Bool = true) {
        guard !Task.isCancelled else { return }
        let next = Request(id: id, urls: Array(urls.prefix(3)), delay: delay, enabled: enabled)
        guard request != next else { return }
        stop()
        request = next
        previewedItemID = id
        guard enabled else { return }
        guard !next.urls.isEmpty else { phase = .failed; return }
        let token = generation
        phase = .waiting
        delayTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay.rawValue) * 1_000_000_000) }
            catch { return }
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.delayTask = nil
            self.start(index: 0, generation: token)
        }
    }

    /// A published value written again tells every view that watches this
    /// preview to rebuild: a preview already stopped is left as it is.
    func stop() {
        generation = UUID()
        request = nil
        if previewedItemID != nil { previewedItemID = nil }
        delayTask?.cancel(); delayTask = nil
        releasePlayer()
        if !isMuted { isMuted = true }
        if phase != .idle { phase = .idle }
    }

    func markUnavailable(id: String) {
        guard !Task.isCancelled else { return }
        stop()
        previewedItemID = id
        phase = .failed
    }

    func toggleMuted() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    private func start(index: Int, generation token: UUID) {
        guard generation == token, let request, request.enabled, request.urls.indices.contains(index) else { return }
        releasePlayer()
        let attemptToken = UUID()
        attempt = attemptToken
        phase = .loading
        let item = AVPlayerItem(url: request.urls[index])
        item.preferredPeakBitRate = 2_000_000
        item.preferredForwardBufferDuration = 2
        // A tile does not need a 4K adaptive rendition. This is an AVPlayer
        // preference, not a transcode; the main player keeps its full quality.
        item.preferredMaximumResolution = CGSize(width: 1280, height: 720)
        let candidate = AVPlayer()
        candidate.isMuted = isMuted
        candidate.preventsDisplaySleepDuringVideoPlayback = false
        candidate.automaticallyWaitsToMinimizeStalling = true
        candidate.actionAtItemEnd = .pause
        player = candidate
        playerCleanup = { @MainActor [candidate] in
            candidate.pause()
            candidate.replaceCurrentItem(with: nil)
        }
        itemObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.generation == token, self.attempt == attemptToken,
                      self.player?.currentItem === item, item.status == .failed else { return }
                self.advance(after: index, generation: token)
            }
        }
        transportObservation = candidate.observe(\.timeControlStatus, options: [.new]) { [weak self, weak candidate] _, _ in
            Task { @MainActor [weak self, weak candidate] in
                guard let self, let candidate, self.generation == token, self.attempt == attemptToken,
                      self.player === candidate else { return }
                if candidate.timeControlStatus == .playing {
                    self.timeoutTask?.cancel(); self.timeoutTask = nil
                    self.phase = .playing
                } else if candidate.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    self.phase = .loading
                    self.armTimeout(index: index, generation: token, attempt: attemptToken)
                }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.generation == token, self.attempt == attemptToken,
                      self.player?.currentItem === item else { return }
                self.advance(after: index, generation: token)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.generation == token, self.attempt == attemptToken,
                      self.player?.currentItem === item else { return }
                // A live preview that ends must not keep advertising a frozen
                // final frame as live. Try its remaining URL, then show failure.
                self.advance(after: index, generation: token)
            }
        }
        candidate.replaceCurrentItem(with: item)
        armTimeout(index: index, generation: token, attempt: attemptToken)
        candidate.play()
    }

    private func armTimeout(index: Int, generation token: UUID, attempt attemptToken: UUID) {
        guard timeoutTask == nil else { return }
        timeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            guard let self, !Task.isCancelled, self.generation == token, self.attempt == attemptToken,
                  self.phase == .loading else { return }
            self.advance(after: index, generation: token)
        }
    }

    private func advance(after index: Int, generation token: UUID) {
        guard generation == token, let request else { return }
        if request.urls.indices.contains(index + 1) { start(index: index + 1, generation: token) }
        else { releasePlayer(); phase = .failed }
    }

    private func releasePlayer() {
        attempt = UUID()
        timeoutTask?.cancel(); timeoutTask = nil
        itemObservation?.invalidate(); itemObservation = nil
        transportObservation?.invalidate(); transportObservation = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        let cleanup = playerCleanup
        playerCleanup = nil
        cleanup?()
        if player != nil { player = nil }
    }

    deinit {
        delayTask?.cancel(); timeoutTask?.cancel()
        itemObservation?.invalidate(); transportObservation?.invalidate()
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let cleanup = playerCleanup { Task { @MainActor [cleanup] in cleanup() } }
    }
}
