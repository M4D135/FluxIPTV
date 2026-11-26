import AVKit
#if os(macOS)
import AppKit
typealias PlatformVideoView = NSView
#else
import UIKit
typealias PlatformVideoView = UIView
#endif
import Combine
import Foundation
#if !os(macOS)
import VLCKit
#endif

/// One audio or subtitle track of the media on screen, whichever engine
/// reads it.
struct PlaybackTrack: Identifiable, Hashable {
    let id: String
    let title: String
    let selected: Bool
}

@MainActor
final class PlaybackController: ObservableObject {
    let player = AVPlayer()
    // Defer VideoLAN engine initialization until a VLC stream is actually selected.
    #if !os(macOS)
    private var vlcPlayer: VLCMediaPlayer?
    #endif
    private static let recoveryKey = "fluxiptv.vlc.unclean.v1"
    @Published private(set) var recoveryMode = UserDefaults.standard.bool(forKey: "fluxiptv.vlc.unclean.v1")
    func resumeNormalMode() {
        // Explicit action only; next playback may try VLC again.
        guard playingItem == nil || engine == .native else { return }
        recoveryMode = false
        UserDefaults.standard.removeObject(forKey: Self.recoveryKey)
    }
    @Published private(set) var playingItem: IPTVItem?
    @Published private(set) var engine: PlaybackEngine = .native
    @Published private(set) var opening = false
    @Published private(set) var isPlaying = false
    @Published private(set) var seekable = false
    @Published private(set) var position = 0.0
    @Published private(set) var localVolume = 1.0
    @Published private(set) var muted = false
    private var durationSeconds = 0.0
    @Published private(set) var history = (UserDefaults.standard.data(forKey: "fluxiptv.history.v1").flatMap { try? JSONDecoder().decode(ViewingHistory.self, from: $0) } ?? ViewingHistory())
    @Published var resumeEnabled = UserDefaults.standard.object(forKey: "fluxiptv.resumeEnabled") as? Bool ?? true
    private var pendingResume: Double?
    private var lastHistoryWrite = Date.distantPast
    private var currentSeconds = 0.0
    private var hasPlayed = false
    func setResumeEnabled(_ value: Bool) { resumeEnabled = value; UserDefaults.standard.set(value, forKey: "fluxiptv.resumeEnabled") }
    func clearHistory() { history.clear(); pendingResume = nil; persistHistory() }
    func forgetProgress(_ id: String) { history.remove(id: id); persistHistory() }
    private func persistHistory() { if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: "fluxiptv.history.v1") } }
    private func saveProgress() {
        guard hasPlayed, pendingResume == nil, let item = playingItem, item.kind != .live, currentSeconds >= 5, durationSeconds > 0 else { return }
        history.record(id: item.id, seconds: currentSeconds, duration: durationSeconds)
        persistHistory(); lastHistoryWrite = Date()
    }
    @Published private(set) var elapsed = "0:00"
    @Published private(set) var duration = "–:––"
    @Published private(set) var attemptLabel = ""
    @Published private(set) var playbackError: String?
    @Published var preferredEngine: PlaybackEngine? = nil
    @Published private(set) var settings: PlaybackSettings = {
        guard let data = UserDefaults.standard.data(forKey: "fluxiptv.playback.settings.v1"), let value = try? JSONDecoder().decode(PlaybackSettings.self, from: data) else { return PlaybackSettings() }
        return value.normalized
    }()
    @Published private(set) var reconnectCount = 0
    private var activeSettings = PlaybackSettings()
    private var userPaused = false
    /// True while the stream on screen was opened with other settings than
    /// those saved now: the engine reads them when it opens a stream.
    var restartPending: Bool {
        guard playingItem != nil else { return false }
        var active = activeSettings, saved = settings
        // The length of a jump is read at each jump.
        active.skipSeconds = 0; saved.skipSeconds = 0
        return active != saved
    }
    func saveSettings(_ value: PlaybackSettings, restart: Bool) {
        settings = value.normalized
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "fluxiptv.playback.settings.v1") }
        if restart, playingItem != nil { retry(preferred: nil) }
    }
    // MARK: Tracks of the media on screen, for both engines

    @Published private(set) var audioTracks: [PlaybackTrack] = []
    @Published private(set) var subtitleTracks: [PlaybackTrack] = []
    /// False when the media gives no way of showing no subtitle at all.
    @Published private(set) var subtitlesCanBeOff = true

    func selectAudioTrack(_ id: String) {
        #if FLUX_CATALOG_UI_TESTING
        if fixtureTracks { fixtureSelect(audio: id); return }
        #endif
        if engine == .native {
            guard let group = nativeGroup(.audible), let index = Self.nativeIndex(id), group.options.indices.contains(index) else { return }
            selectTrack(group.options[index], characteristic: .audible)
        }
        #if !os(macOS)
        if engine == .vlc, vlcActive, let track = vlcPlayer?.audioTracks.first(where: { $0.trackId == id }) {
            track.isSelectedExclusively = true
        }
        #endif
        refreshTracks()
    }

    /// `nil` turns the subtitles off.
    func selectSubtitleTrack(_ id: String?) {
        #if FLUX_CATALOG_UI_TESTING
        if fixtureTracks { fixtureSelect(subtitle: id); return }
        #endif
        if engine == .native {
            if let id {
                guard let group = nativeGroup(.legible), let index = Self.nativeIndex(id), group.options.indices.contains(index) else { return }
                selectTrack(group.options[index], characteristic: .legible)
            } else { selectTrack(nil, characteristic: .legible) }
        }
        #if !os(macOS)
        if engine == .vlc, vlcActive, let vlcPlayer {
            if let id, let track = vlcPlayer.textTracks.first(where: { $0.trackId == id }) { track.isSelectedExclusively = true }
            else if id == nil { vlcPlayer.deselectAllTextTracks() }
        }
        #endif
        refreshTracks()
    }

    private static func nativeIndex(_ id: String) -> Int? { id.hasPrefix("n") ? Int(id.dropFirst()) : nil }

    private func nativeTracks(_ characteristic: AVMediaCharacteristic) -> [PlaybackTrack] {
        guard let group = nativeGroup(characteristic), let media = nativeSelectionItem else { return [] }
        let current = media.currentMediaSelection.selectedMediaOption(in: group)
        return group.options.enumerated().map { index, option in
            PlaybackTrack(id: "n\(index)", title: option.displayName, selected: option == current)
        }
    }

    /// Reads the tracks the engine knows now, and publishes them only when
    /// they changed: the monitor calls this several times a second.
    private func refreshTracks() {
        #if FLUX_CATALOG_UI_TESTING
        if fixtureTracks { return }
        #endif
        var audio: [PlaybackTrack] = [], subtitles: [PlaybackTrack] = [], canBeOff = true
        if playingItem != nil {
            if engine == .native {
                audio = nativeTracks(.audible); subtitles = nativeTracks(.legible)
                canBeOff = nativeGroup(.legible)?.allowsEmptySelection ?? true
            }
            #if !os(macOS)
            if engine == .vlc, vlcActive, let vlcPlayer {
                audio = Self.vlcTracks(vlcPlayer.audioTracks); subtitles = Self.vlcTracks(vlcPlayer.textTracks)
            }
            #endif
        }
        if audioTracks != audio { audioTracks = audio }
        if subtitleTracks != subtitles { subtitleTracks = subtitles }
        if subtitlesCanBeOff != canBeOff { subtitlesCanBeOff = canBeOff }
    }

    #if !os(macOS)
    private static func vlcTracks(_ tracks: [VLCMediaPlayer.Track]) -> [PlaybackTrack] {
        tracks.enumerated().map { index, track in
            // A provider names its tracks, describes them, or only gives a language code.
            let candidates = [track.trackName, track.trackDescription ?? "", track.language ?? ""]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let title = candidates.first(where: { !$0.isEmpty }) ?? "Piste \(index + 1)"
            return PlaybackTrack(id: track.trackId, title: title, selected: track.isSelected)
        }
    }
    #endif

    #if FLUX_CATALOG_UI_TESTING
    private var fixtureTracks = false
    /// A capture or a remote flow shows the commands of a media that plays,
    /// without opening any connection: only the published state is set.
    func showFixture(_ item: IPTVItem, playing: Bool, opening: Bool = false, fraction: Double = 0, elapsed: String = "0:00",
                     duration: String = "–:––", audio: [PlaybackTrack] = [], subtitles: [PlaybackTrack] = []) {
        playingItem = item; self.opening = opening; isPlaying = playing; playbackError = nil
        seekable = item.kind != .live; position = fraction
        self.elapsed = elapsed; self.duration = duration
        fixtureTracks = true; audioTracks = audio; subtitleTracks = subtitles
        attemptLabel = "Maquette"
    }
    /// The fixture answers the commands the way an engine would.
    private func fixtureSelect(audio id: String) {
        audioTracks = audioTracks.map { PlaybackTrack(id: $0.id, title: $0.title, selected: $0.id == id) }
    }
    private func fixtureSelect(subtitle id: String?) {
        subtitleTracks = subtitleTracks.map { PlaybackTrack(id: $0.id, title: $0.title, selected: $0.id == id) }
    }
    var showsFixture: Bool { fixtureTracks }
    /// Titles the fixture cannot show: they take the ordinary path.
    var fixtureUnplayable: Set<String> = []
    /// Titles whose simulated stream opens and then fails, as a dead channel does.
    var fixtureFailing: Set<String> = []
    /// Showing this title only changes the simulated state: the catalogue of
    /// a fixture has no address to open.
    func simulates(_ item: IPTVItem) -> Bool { fixtureTracks && !fixtureUnplayable.contains(item.id) }
    #endif
    @Published private var nativeAudioGroup: AVMediaSelectionGroup?
    @Published private var nativeSubtitleGroup: AVMediaSelectionGroup?
    private weak var nativeSelectionItem: AVPlayerItem?
    private var nativeSelectionLoad: Task<Void, Never>?
    private func nativeGroup(_ characteristic: AVMediaCharacteristic) -> AVMediaSelectionGroup? {
        guard engine == .native, let media = nativeSelectionItem, player.currentItem === media else { return nil }
        if characteristic == .audible { return nativeAudioGroup }
        if characteristic == .legible { return nativeSubtitleGroup }
        return nil
    }
    private func selectTrack(_ option: AVMediaSelectionOption?, characteristic: AVMediaCharacteristic) {
        guard let group = nativeGroup(characteristic), let media = nativeSelectionItem else { return }
        // A settings button from an earlier item must not select its old option
        // in the current item's group after a rapid channel/episode change.
        if let option, !group.options.contains(where: { $0 === option }) { return }
        guard option != nil || group.allowsEmptySelection else { return }
        media.select(option, in: group)
    }
    private func nativeSelectionIsCurrent(_ media: AVPlayerItem, token: UUID) -> Bool {
        generation == token && engine == .native && nativeSelectionItem === media && player.currentItem === media
    }
    private func loadNativeSelection(for media: AVPlayerItem, token: UUID) {
        nativeSelectionItem = media
        nativeSelectionLoad = Task { @MainActor [weak self, weak media] in
            guard let media, !Task.isCancelled else { return }
            defer {
                if self?.nativeSelectionIsCurrent(media, token: token) == true { self?.nativeSelectionLoad = nil }
            }
            // These calls load metadata asynchronously; settings rendering only
            // reads the published groups and never starts a network request.
            let audio = try? await media.asset.loadMediaSelectionGroup(for: .audible)
            guard !Task.isCancelled, self?.nativeSelectionIsCurrent(media, token: token) == true else { return }
            self?.nativeAudioGroup = audio
            let subtitles = try? await media.asset.loadMediaSelectionGroup(for: .legible)
            guard !Task.isCancelled, self?.nativeSelectionIsCurrent(media, token: token) == true else { return }
            self?.nativeSubtitleGroup = subtitles
        }
    }
    private func cancelNativeSelection() {
        if nativeSelectionLoad != nil {
            nativeSelectionLoad?.cancel()
            // This helper runs when the old playback attempt is being stopped;
            // cancelling its asset cannot interrupt the replacement item.
            nativeSelectionItem?.asset.cancelLoading()
        }
        nativeSelectionLoad = nil
        nativeSelectionItem = nil
        if nativeAudioGroup != nil { nativeAudioGroup = nil }
        if nativeSubtitleGroup != nil { nativeSubtitleGroup = nil }
    }
    private var observation: AnyCancellable?
    private var monitor: Task<Void, Never>?
    private var transition: Task<Void, Never>?
    private var attempts: [PlaybackAttempt] = []
    private var urls: [URL] = []
    private var index = 0
    private var generation = UUID()
    private var pendingVLCURL: URL?
    private weak var surface: PlatformVideoView?
    private var vlcActive = false
    private var lastDiagnostic = ""

    func play(_ item: IPTVItem, urls: [URL]) {
        #if FLUX_CATALOG_UI_TESTING
        // The fixture changes channel as an engine would, without a connection:
        // the stream opens for a moment, then plays.
        if fixtureTracks {
            showFixture(item, playing: false, opening: true, audio: audioTracks, subtitles: subtitleTracks)
            let fails = fixtureFailing.contains(item.id)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let self, self.playingItem?.id == item.id, self.opening else { return }
                self.opening = false
                if fails { self.playbackError = "Le flux de démonstration ne répond pas." } else { self.isPlaying = true }
            }
            return
        }
        #endif
        stop()
        playingItem = item
        self.urls = PlaybackPlan.candidateURLs(urls)
        pendingResume = resumeEnabled ? history.resumeSeconds(for: item.id) : nil
        startPlan()
    }

    func retry(preferred: PlaybackEngine? = nil) {
        guard playingItem != nil else { return }
        #if FLUX_CATALOG_UI_TESTING
        // The fixture has no stream to open again: it only takes the settings.
        if fixtureTracks { objectWillChange.send(); activeSettings = settings; return }
        #endif
        saveProgress()
        if resumeEnabled, let item = playingItem { pendingResume = history.resumeSeconds(for: item.id) }
        preferredEngine = preferred
        startPlan()
    }

    private func startPlan() {
        activeSettings = settings
        reconnectCount = 0
        userPaused = false
        let recovery = PlaybackRecovery(uncleanVLCSession: recoveryMode)
        #if os(macOS)
        // The experimental VideoLAN 4 build crashed in vlc_gl_filter_ApplyOutputSize.
        // Never instantiate its decoder in this process on Mac. External VLC is opt-in.
        attempts = PlaybackPlan.attempts(urls: urls, preferred: .native)
        #else
        attempts = PlaybackPlan.attempts(urls: urls, preferred: recovery.preferredEngine(preferredEngine ?? activeSettings.engine.preferred))
        #endif
        index = 0
        lastDiagnostic = ""
        startAttempt()
    }

    private func startAttempt() {
        cancelEngine()
        playbackError = nil
        guard attempts.indices.contains(index) else {
            opening = false
            #if os(macOS)
            playbackError = lastDiagnostic.isEmpty
                ? "Le lecteur Apple ne dispose d’aucune adresse de lecture utilisable."
                : lastDiagnostic
            attemptLabel = "Échec avec Apple AVPlayer"
            #else
            playbackError = "Lecture impossible avec les moteurs disponibles. " + lastDiagnostic
            attemptLabel = "Vérifiez le flux ou réessayez."
            #endif
            return
        }
        let attempt = attempts[index]
        let token = generation
        engine = attempt.engine
        opening = true
        attemptLabel = "\(attempt.engine.title) · essai \(index + 1)/\(attempts.count)"
        transition = Task { @MainActor [weak self] in
            // Release the previous connection before starting another one.
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, !Task.isCancelled, self.generation == token else { return }
            #if os(macOS)
            self.startNative(attempt.url, token: token)
            #else
            if attempt.engine == .native { self.startNative(attempt.url, token: token) }
            else { self.pendingVLCURL = attempt.url; self.startVLCIfReady() }
            #endif
            self.startMonitor(token: token)
        }
    }

    private func startNative(_ url: URL, token: UUID) {
        let media = AVPlayerItem(url: url)
        media.preferredForwardBufferDuration = activeSettings.nativeBufferSeconds
        media.preferredPeakBitRate = activeSettings.nativePeakBitrate
        player.automaticallyWaitsToMinimizeStalling = activeSettings.nativeWait
        observation = media.publisher(for: \.status, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak media] status in
                guard let self, self.generation == token else { return }
                if status == .failed {
                    let error = media?.error
                    let description = PlaybackDiagnostics.native(Self.nativeFailureKind(error), error: error)
                    let variant = PlaybackPlan.variantTitle(url: url, index: self.urls.firstIndex(of: url) ?? 0)
                    self.fail(token: token, reason: "\(variant) : \(description)")
                }
            }
        player.replaceCurrentItem(with: media)
        loadNativeSelection(for: media, token: token)
        applyVolume()
        player.play()
    }

    private static func nativeFailureKind(_ error: Error?) -> PlaybackDiagnostics.NativeFailure {
        guard let error = error as NSError? else { return .other }
        if error.domain == NSURLErrorDomain { return .network }
        guard error.domain == AVFoundationErrorDomain,
              let code = AVError.Code(rawValue: error.code) else { return .other }
        switch code {
        case .fileFormatNotRecognized: return .unrecognizedFormat
        case .fileFailedToParse: return .invalidMedia
        case .decoderNotFound: return .missingDecoder
        case .decodeFailed, .undecodableMediaData: return .decodingFailed
        default: return .other
        }
    }

    #if !os(macOS)
    func attachVLC(_ view: PlatformVideoView) {
        guard engine == .vlc, playingItem != nil, view.window != nil, view.bounds.width >= 32, view.bounds.height >= 32 else { return }
        guard surface !== view else { startVLCIfReady(); return }
        surface = view
        if vlcActive && engine == .vlc { vlcPlayer?.drawable = view }
        startVLCIfReady()
    }

    private func startVLCIfReady() {
        guard engine == .vlc, let view = surface, view.window != nil, view.bounds.width >= 32, view.bounds.height >= 32,
              let url = pendingVLCURL else { return }
        pendingVLCURL = nil
        guard let media = VLCMedia(url: url) else {
            fail(token: generation, reason: "VLC : adresse média refusée.")
            return
        }
        for option in activeSettings.vlcOptions { media.addOption(option) }
        // Keep the marker until the VLC attempt is cleanly stopped. It contains no credentials.
        UserDefaults.standard.set(true, forKey: Self.recoveryKey)
        let vlcPlayer = self.vlcPlayer ?? VLCMediaPlayer()
        self.vlcPlayer = vlcPlayer
        vlcPlayer.drawable = view
        vlcPlayer.media = media
        vlcActive = true
        vlcPlayer.play()
        applyVolume()
    }

    #endif

    private func startMonitor(token: UUID) {
        monitor = Task { @MainActor [weak self] in
            let startedAt = Date()
            var started = false
            var lastPlaying = startedAt
            while !Task.isCancelled {
                guard let self, self.generation == token else { return }
                #if os(macOS)
                let playing = self.player.timeControlStatus == .playing
                self.updateTime(current: self.player.currentTime().seconds, total: self.player.currentItem?.duration.seconds ?? 0)
                #else
                if self.engine == .vlc { self.startVLCIfReady() }
                let playing: Bool
                if self.engine == .native {
                    playing = self.player.timeControlStatus == .playing
                    let current = self.player.currentTime().seconds
                    let total = self.player.currentItem?.duration.seconds ?? 0
                    self.updateTime(current: current, total: total)
                } else if let vlcPlayer = self.vlcPlayer {
                    let state = vlcPlayer.state
                    playing = vlcPlayer.isPlaying
                    if self.vlcActive && state == .error {
                        self.fail(token: token, reason: "VLC : ouverture ou décodage impossible."); return
                    }
                    if self.vlcActive {
                        let current = Double(vlcPlayer.time.intValue) / 1000
                        let total = Double(vlcPlayer.media?.length.intValue ?? 0) / 1000
                        self.updateTime(current: current, total: total, canSeek: vlcPlayer.isSeekable)
                    }
                } else {
                    playing = false
                }
                #endif
                if self.isPlaying != playing { self.isPlaying = playing }
                self.refreshTracks()
                if playing {
                    lastPlaying = Date()
                    // VLC's audio output can be absent while the media is opening.
                    if !started { self.applyVolume() }
                    started = true
                    self.hasPlayed = true
                    if let target = self.pendingResume, self.seekable, self.durationSeconds > target + 15 {
                        self.pendingResume = nil
                        self.seek(target / self.durationSeconds)
                        self.lastHistoryWrite = Date()
                    } else if self.seekable { self.pendingResume = nil }
                    if Date().timeIntervalSince(self.lastHistoryWrite) >= 20 { self.saveProgress() }
                    if self.opening { self.opening = false }
                }
                if started && self.userPaused { lastPlaying = Date() }
                if started && !playing && !self.userPaused && self.playingItem?.kind == .live && Date().timeIntervalSince(lastPlaying) > Double(self.activeSettings.stallTimeout) {
                    self.fail(token: token, reason: "Flux direct interrompu."); return
                }
                if !started && Date().timeIntervalSince(startedAt) > Double(self.activeSettings.timeout) {
                    self.fail(token: token, reason: "\(self.engine.title) : délai d’ouverture dépassé."); return
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    private func updateTime(current: Double, total: Double, canSeek: Bool = true) {
        currentSeconds = current.isFinite ? max(0, current) : 0
        durationSeconds = total.isFinite && total > 0 ? total : 0
        let newSeekable = playingItem?.kind != .live && canSeek && total.isFinite && total > 0
        if seekable != newSeekable { seekable = newSeekable }
        let newPosition = seekable && current.isFinite ? min(1, max(0, current / total)) : 0
        if abs(position - newPosition) >= 0.0001 || newPosition == 0 && position != 0 { position = newPosition }
        let newElapsed = Self.timeLabel(current), newDuration = Self.timeLabel(total)
        // Live streams do not display a timeline. Avoid invalidating the
        // entire view tree for live-only elapsed time changes.
        if playingItem?.kind != .live {
            if elapsed != newElapsed { elapsed = newElapsed }
            if duration != newDuration { duration = newDuration }
        }
    }

    private static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < 1_000_000_000 else { return "–:––" }
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    func togglePause() {
        guard !opening, playbackError == nil else { return }
        if engine == .native {
            if !userPaused { userPaused = true; player.pause() } else { userPaused = false; player.play() }
        }
        #if !os(macOS)
        if engine == .vlc, vlcActive, let vlcPlayer {
            if !userPaused { userPaused = true; vlcPlayer.pause() } else { userPaused = false; vlcPlayer.play() }
        }
        #endif
    }

    func seek(_ fraction: Double) {
        guard seekable else { return }
        let f = min(1, max(0, fraction))
        if engine == .native, let total = player.currentItem?.duration.seconds, total.isFinite, total > 0 {
            player.seek(to: CMTime(seconds: total * f, preferredTimescale: 600))
        }
        #if !os(macOS)
        if engine == .vlc && vlcActive { vlcPlayer?.position = f }
        #endif
    }

    func skip(seconds: Double) {
        guard seekable, durationSeconds > 0 else { return }
        seek(position + seconds / durationSeconds)
    }

    func setVolume(_ value: Double) {
        let clamped = min(1, max(0, value))
        if localVolume != clamped { localVolume = clamped }
        if muted { muted = false }
        applyVolume()
    }
    func adjustVolume(_ delta: Double) { setVolume(localVolume + delta) }

    func toggleMute() { muted.toggle(); applyVolume() }

    private func applyVolume() {
        player.volume = Float(localVolume); player.isMuted = muted
        // VLCKit imports audio as VLCAudio?. It can be nil before playback.
        #if !os(macOS)
        if let audio = vlcPlayer?.audio {
            audio.volume = Int32((localVolume * 100).rounded())
            audio.isMuted = muted
        }
        #endif
    }

    private func fail(token: UUID, reason: String) {
        guard generation == token else { return }
        lastDiagnostic = reason
        // Do not silently restart a movie after it was already playing.
        if opening {
            index += 1
            startAttempt()
        } else if !userPaused && activeSettings.canReconnect(isLive: playingItem?.kind == .live, attempt: reconnectCount) {
            reconnectCount += 1
            startAttempt()
        } else {
            saveProgress()
            cancelEngine()
            playbackError = reason
            attemptLabel = "Lecture interrompue"
        }
    }

    private func cancelEngine() {
        generation = UUID()
        monitor?.cancel(); monitor = nil
        transition?.cancel(); transition = nil
        observation = nil
        cancelNativeSelection()
        pendingVLCURL = nil
        player.pause(); player.replaceCurrentItem(with: nil)
        #if !os(macOS)
        if vlcActive {
            vlcPlayer?.stop(); vlcActive = false
            vlcPlayer?.drawable = nil
            if !recoveryMode { UserDefaults.standard.removeObject(forKey: Self.recoveryKey) }
        } else { vlcPlayer?.drawable = nil }
        #endif
        opening = false; isPlaying = false; seekable = false; position = 0
        elapsed = "0:00"; duration = "–:––"; durationSeconds = 0; currentSeconds = 0; hasPlayed = false
        if !audioTracks.isEmpty { audioTracks = [] }
        if !subtitleTracks.isEmpty { subtitleTracks = [] }
    }

    #if os(macOS)
    var externalVLCVariants: [PlaybackVariant] { PlaybackPlan.variants(urls: urls) }

    /// Explicit hand-off; never put the authenticated URL in the shell, logs or preferences.
    func openExternalVLC(variantID: Int) {
        guard urls.indices.contains(variantID) else { return }
        let url = urls[variantID]
        guard let application=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"org.videolan.vlc") else {
            playbackError="VLC n’est pas installé sur ce Mac. Installez le lecteur officiel VideoLAN pour les formats non pris en charge par Apple."
            return
        }
        saveProgress();cancelEngine()
        let token = generation
        let config=NSWorkspace.OpenConfiguration();config.activates=true
        NSWorkspace.shared.open([url],withApplicationAt:application,configuration:config) { [weak self] _, error in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if error != nil {self.playbackError="Impossible d’ouvrir le flux dans VLC."}
                else {self.playbackError=nil;self.attemptLabel="Lecture confiée à VLC externe"}
            }
        }
    }
    #endif
    func stop() {
        saveProgress()
        pendingResume = nil
        cancelEngine()
        playingItem = nil; playbackError = nil; attemptLabel = ""
        urls = []; attempts = []; index = 0; userPaused = false; preferredEngine = nil; reconnectCount = 0
    }
}
