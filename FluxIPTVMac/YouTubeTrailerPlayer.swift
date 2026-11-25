#if (os(macOS) || os(iOS)) && canImport(WebKit)
import Combine
import Foundation
import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Owns one embedded player for both the case preview and its full-screen view.
/// The controller that owns this session must call stop() when leaving the case.
@MainActor final class YouTubeTrailerSession: NSObject, ObservableObject {
    enum State: Equatable {
        case idle, loading, playing, paused, ended, blocked, failed(String)
    }

    let trailer: YouTubeTrailer
    @Published private(set) var state: State = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var isMuted = true
    var onStateChange: ((State) -> Void)?
    var onReady: (() -> Void)?

    private static let messageName = "fluxTrailer"
    private let token = UUID().uuidString
    private let identityURL: URL?
    private var webView: WKWebView?
    private var hosts: [WeakTrailerHost] = []
    private var hasStarted = false
    private var isReady = false
    private var wantsPlayback = false
    private var isDisposed = false
    private var hasFailed = false
    private var startupTimeout: Task<Void, Never>?
    private var readyPlaybackTask: Task<Void, Never>?
    #if FLUX_TRAILER_TESTING
    private var iframeAPIFixture: String?
    var fixtureWebView: WKWebView? { webView }

    /// Compiled only by the standalone native smoke test. The normal app has no
    /// fixture initializer or alternate player endpoint.
    convenience init(trailer: YouTubeTrailer, iframeAPIFixture: String) {
        self.init(trailer: trailer)
        self.iframeAPIFixture = iframeAPIFixture
    }
    #endif

    init(trailer: YouTubeTrailer) {
        self.trailer = trailer
        var identity = URLComponents()
        identity.scheme = "https"
        identity.host = Bundle.main.bundleIdentifier?.lowercased()
        identityURL = identity.host?.isEmpty == false ? identity.url : nil

        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // WebKit still permits a popup initiated by a real click, which the UI
        // delegate sends to the system browser instead of replacing this player.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif
        let view = WKWebView(frame: .zero, configuration: configuration)
        #if os(iOS)
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        #endif
        webView = view
        super.init()
        view.configuration.userContentController.add(WeakTrailerMessageHandler(self), name: Self.messageName)
        view.navigationDelegate = self
        view.uiDelegate = self
    }

    /// Repeated starts never reload or reset a player that is already running.
    func start(muted: Bool = true) {
        guard !isDisposed, !hasStarted else { return }
        hasStarted = true
        isMuted = muted
        wantsPlayback = true
        guard let identityURL, let webView else {
            fail("L’application ne fournit pas son identifiant à YouTube (153).")
            return
        }
        transition(to: .loading)
        armStartupTimeout()
        webView.loadHTMLString(playerHTML(origin: identityURL), baseURL: identityURL)
    }

    func play(unmute: Bool = false) {
        guard !isDisposed, !hasFailed else { return }
        if !hasStarted {
            start(muted: unmute ? false : isMuted)
            return
        }
        cancelReadyPlayback()
        if unmute { isMuted = false }
        wantsPlayback = true
        if state != .playing { transition(to: .loading); armStartupTimeout() }
        if isReady { sendCommand("play(\(isMuted ? "true" : "false"))") }
    }

    func pause() {
        guard !isDisposed else { return }
        wantsPlayback = false
        cancelReadyPlayback()
        cancelStartupTimeout()
        if isReady { sendCommand("pause()") }
        webView?.pauseAllMediaPlayback(completionHandler: nil)
        if hasStarted, !hasFailed, state != .ended { transition(to: .paused) }
    }

    func setMuted(_ muted: Bool) {
        guard !isDisposed else { return }
        isMuted = muted
        if isReady, !hasFailed { sendCommand("setMuted(\(muted ? "true" : "false"))") }
    }

    func togglePlayback() {
        if state == .playing || (state == .loading && wantsPlayback) { pause() }
        else { play() }
    }

    func seek(by delta: Double) {
        guard !isDisposed, !hasFailed, isReady, delta.isFinite else { return }
        sendCommand("seek(\(delta))")
    }

    /// Final disposal. A fullscreen handoff only moves the surface; it must not
    /// call this method. No actor-isolated cleanup is deferred to deinit.
    func stop() {
        guard !isDisposed else { return }
        isDisposed = true
        wantsPlayback = false
        isReady = false
        cancelReadyPlayback()
        cancelStartupTimeout()
        if let view = webView {
            view.pauseAllMediaPlayback(completionHandler: nil)
            view.closeAllMediaPresentations(completionHandler: nil)
            view.evaluateJavaScript("window.fluxTrailer && window.fluxTrailer.dispose();", completionHandler: nil)
            view.stopLoading()
            view.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageName)
            view.navigationDelegate = nil
            view.uiDelegate = nil
            view.removeFromSuperview()
            // Navigating away also ends media if the script process was hung.
            view.loadHTMLString("", baseURL: nil)
        }
        for host in hosts.compactMap(\.value) { host.session = nil; host.clearSurface() }
        hosts.removeAll()
        webView = nil
        progress = 0
        transition(to: .idle)
        onStateChange = nil
        onReady = nil
    }

    private func transition(to next: State) {
        guard state != next else { return }
        state = next
        onStateChange?(next)
    }

    private func armStartupTimeout() {
        cancelStartupTimeout()
        startupTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 18_000_000_000) } catch { return }
            guard let self, !self.isDisposed, !self.hasFailed, self.wantsPlayback else { return }
            self.fail("La bande-annonce ne répond pas. Vérifiez la connexion et réessayez.")
        }
    }

    private func cancelStartupTimeout() {
        startupTimeout?.cancel()
        startupTimeout = nil
    }

    private func cancelReadyPlayback() {
        readyPlaybackTask?.cancel()
        readyPlaybackTask = nil
    }

    private func fail(_ message: String) {
        guard !isDisposed else { return }
        hasFailed = true
        wantsPlayback = false
        cancelReadyPlayback()
        cancelStartupTimeout()
        webView?.pauseAllMediaPlayback(completionHandler: nil)
        transition(to: .failed(message))
    }

    private func sendCommand(_ command: String) {
        guard !isDisposed, !hasFailed, isReady, let webView else { return }
        webView.evaluateJavaScript("window.fluxTrailer && window.fluxTrailer.\(command);") { [weak self] _, error in
            guard let self, !self.isDisposed, !self.hasFailed, error != nil else { return }
            self.fail("Le lecteur YouTube s’est interrompu. Réessayez la bande-annonce.")
        }
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard !isDisposed, !hasFailed, message.name == Self.messageName,
              message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              body["session"] as? String == token,
              let event = body["type"] as? String else { return }
        switch event {
        case "ready":
            guard !isReady else { return }
            isReady = true
            // The owner reveals the ready iframe with a 0.5-second fade. Wait
            // until that visible surface has settled before starting autoplay.
            // Queue before the callback so an explicit play/pause/stop inside
            // that callback can cancel the pending automatic request too.
            if wantsPlayback {
                cancelReadyPlayback()
                readyPlaybackTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: 550_000_000) } catch { return }
                    guard let self, !self.isDisposed, !self.hasFailed, self.isReady, self.wantsPlayback else { return }
                    self.readyPlaybackTask = nil
                    self.sendCommand("play(\(self.isMuted ? "true" : "false"))")
                }
            }
            onReady?()
            guard !isDisposed, !hasFailed else { return }
            if !wantsPlayback { sendCommand("pause()") }
        case "state":
            guard let value = body["value"] as? Int else { return }
            switch value {
            case 1:
                wantsPlayback = true
                cancelStartupTimeout()
                transition(to: .playing)
            case 2:
                wantsPlayback = false
                cancelStartupTimeout()
                if state != .blocked { transition(to: .paused) }
            case 0:
                wantsPlayback = false
                cancelStartupTimeout()
                progress = 1
                transition(to: .ended)
            case 3:
                if wantsPlayback { transition(to: .loading); armStartupTimeout() }
            default: break
            }
        case "progress":
            if let time = body["time"] as? Double, let duration = body["duration"] as? Double,
               time.isFinite, duration.isFinite, duration > 0 {
                progress = min(max(time / duration, 0), 1)
            }
            // The iframe is intentionally muted while its ready surface fades
            // in. Its 500 ms sample can arrive before the 550 ms play request;
            // that temporary state must not replace an explicit fullscreen
            // request to start with sound. Once the request has been sent,
            // follow the real player again, including its own mute controls.
            if readyPlaybackTask == nil, let muted = body["muted"] as? Bool { isMuted = muted }
        case "blocked":
            wantsPlayback = false
            cancelReadyPlayback()
            cancelStartupTimeout()
            transition(to: .blocked)
        case "error":
            let code = body["value"] as? Int ?? 0
            switch code {
            case 101, 150:
                fail("Cette bande-annonce ne peut pas être intégrée. Regardez-la sur YouTube.")
            case 153:
                fail("YouTube ne reconnaît pas l’application (153). Réessayez après sa mise à jour.")
            case 100:
                fail("Cette bande-annonce est privée ou n’est plus disponible sur YouTube.")
            case 2:
                fail("Le lien de cette bande-annonce YouTube n’est pas valide.")
            default:
                fail("YouTube ne peut pas lire cette bande-annonce. Réessayez ou ouvrez-la sur YouTube.")
            }
        case "scriptError":
            fail("Impossible de joindre YouTube. Vérifiez la connexion et réessayez.")
        default: break
        }
    }

    /// New hosts take ownership; subsequent updates of an old inline host must
    /// not steal the view back from fullscreen. Removing fullscreen restores the
    /// surviving inline host even if SwiftUI updates it before dismantling.
    fileprivate func attach(to host: YouTubeTrailerHostView) {
        guard !isDisposed, let webView else { return }
        if let previous = host.session, previous !== self { previous.detach(from: host) }
        host.session = self
        hosts.removeAll { $0.value == nil }
        let isNewHost = !hosts.contains { $0.value === host }
        if isNewHost { hosts.append(WeakTrailerHost(host)) }
        if isNewHost || webView.superview == nil { host.install(webView) }
    }

    fileprivate func detach(from host: YouTubeTrailerHostView) {
        hosts.removeAll { $0.value == nil || $0.value === host }
        guard host.session === self else { return }
        host.session = nil
        let wasCurrent = webView?.superview === host
        host.clearSurface()
        if wasCurrent, !isDisposed, let webView, let replacement = hosts.last?.value {
            replacement.install(webView)
        }
    }

    private func playerHTML(origin: URL) -> String {
        // Values are serialized, never interpreted as HTML or JavaScript source.
        let values = ["videoID": trailer.videoID, "origin": origin.absoluteString, "session": token]
        let data = (try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])) ?? Data("{}".utf8)
        let settings = (String(data: data, encoding: .utf8) ?? "{}")
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
        return """
        <!doctype html>
        <html lang="fr"><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body,#player{width:100%;height:100%;margin:0;padding:0;background:#000;overflow:hidden}iframe{display:block;border:0}</style>
        </head><body><div id="player"></div><script>
        (() => {
          'use strict';
          const settings = \(settings);
          let player = null, ready = false, disposed = false, poll = null;
          const emit = (type, values = {}) => {
            if (!disposed) window.webkit.messageHandlers.fluxTrailer.postMessage(
              Object.assign({type, session: settings.session}, values));
          };
          const snapshot = () => {
            if (!ready || disposed) return;
            const time = player.getCurrentTime(), duration = player.getDuration();
            if (Number.isFinite(time) && Number.isFinite(duration))
              emit('progress', {time, duration, muted: player.isMuted()});
          };
          window.fluxTrailer = {
            play: (muted) => {
              if (!ready || disposed) return;
              muted ? player.mute() : player.unMute();
              if (player.getPlayerState() === 0) player.seekTo(0, true);
              player.playVideo();
              snapshot();
            },
            pause: () => { if (ready && !disposed) { player.pauseVideo(); snapshot(); } },
            setMuted: (muted) => {
              if (!ready || disposed) return;
              muted ? player.mute() : player.unMute();
              snapshot();
            },
            seek: (delta) => {
              if (!ready || disposed || !Number.isFinite(delta)) return;
              const duration = player.getDuration();
              if (duration > 0) player.seekTo(Math.max(0, Math.min(duration, player.getCurrentTime() + delta)), true);
              snapshot();
            },
            dispose: () => {
              if (disposed) return;
              disposed = true;
              if (poll !== null) clearInterval(poll);
              if (player) { if (ready) player.stopVideo(); player.destroy(); }
              player = null; ready = false;
            }
          };
          window.onYouTubeIframeAPIReady = () => {
            if (disposed) return;
            player = new YT.Player('player', {
              width: '100%', height: '100%', videoId: settings.videoID,
              playerVars: {enablejsapi: 1, origin: settings.origin, playsinline: 1, autoplay: 0, controls: 1, fs: 1},
              events: {
                onReady: (event) => {
                  if (disposed) return;
                  ready = true;
                  const frame = event.target.getIframe();
                  frame.setAttribute('allow', 'autoplay; encrypted-media; fullscreen; picture-in-picture');
                  frame.setAttribute('allowfullscreen', '');
                  frame.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
                  frame.setAttribute('title', 'Bande-annonce YouTube');
                  event.target.mute();
                  emit('ready');
                  poll = setInterval(snapshot, 500);
                },
                onStateChange: (event) => { emit('state', {value: event.data}); snapshot(); },
                onError: (event) => emit('error', {value: event.data}),
                onAutoplayBlocked: () => emit('blocked')
              }
            });
          };
          \(iframeAPILoader)
        })();
        </script></body></html>
        """
    }

    private var iframeAPILoader: String {
        #if FLUX_TRAILER_TESTING
        if let iframeAPIFixture {
            return iframeAPIFixture + "\nwindow.onYouTubeIframeAPIReady();"
        }
        #endif
        return """
        const script = document.createElement('script');
        script.src = 'https://www.youtube.com/iframe_api';
        script.onerror = () => emit('scriptError');
        document.head.appendChild(script);
        """
    }
}

extension YouTubeTrailerSession: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !isDisposed, let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.navigationType == .linkActivated {
            openExplicitLink(url)
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        guard ["https", "http", "about", "blob", "data"].contains(scheme) else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == true,
           scheme != "about", url.host?.lowercased() != identityURL?.host?.lowercased() {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Automatic JavaScript popups are disabled in the configuration.
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url { openExplicitLink(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("Le lecteur YouTube s’est interrompu. Réessayez la bande-annonce.")
    }

    private func handleNavigationFailure(_ error: Error) {
        let failure = error as NSError
        guard !(failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled) else { return }
        fail("Impossible de charger YouTube. Vérifiez la connexion et réessayez.")
    }

    private func openExplicitLink(_ url: URL) {
        guard !isDisposed, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return }
        pause()
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

@MainActor private final class WeakTrailerMessageHandler: NSObject, WKScriptMessageHandler {
    weak var session: YouTubeTrailerSession?
    init(_ session: YouTubeTrailerSession) { self.session = session }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        session?.receive(message)
    }
}

@MainActor private final class WeakTrailerHost {
    weak var value: YouTubeTrailerHostView?
    init(_ value: YouTubeTrailerHostView) { self.value = value }
}

#if os(macOS)
fileprivate typealias TrailerHostBase = NSView
#else
fileprivate typealias TrailerHostBase = UIView
#endif

@MainActor fileprivate final class YouTubeTrailerHostView: TrailerHostBase {
    weak var session: YouTubeTrailerSession?
    private weak var surface: WKWebView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if os(macOS)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        #else
        backgroundColor = .black
        clipsToBounds = true
        #endif
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func install(_ view: WKWebView) {
        if surface !== view { clearSurface() }
        surface = view
        if view.superview !== self { view.removeFromSuperview(); addSubview(view) }
        view.frame = bounds
        #if os(macOS)
        view.autoresizingMask = [.width, .height]
        #else
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #endif
    }

    func clearSurface() {
        // A stale host must never remove a surface that has moved to fullscreen.
        if let surface, surface.superview === self { surface.removeFromSuperview() }
        surface = nil
    }

    #if os(macOS)
    override func layout() {
        super.layout()
        if let surface, surface.superview === self { surface.frame = bounds }
    }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        if let surface, surface.superview === self { surface.frame = bounds }
    }
    #endif
}

/// A host only presents the session's existing player. Its destruction never
/// stops the session and cannot detach a player already owned by another host.
@MainActor struct YouTubeTrailerSurface: View {
    let session: YouTubeTrailerSession
    var body: some View { YouTubeTrailerNativeSurface(session: session) }
}

#if os(macOS)
private struct YouTubeTrailerNativeSurface: NSViewRepresentable {
    let session: YouTubeTrailerSession
    func makeNSView(context: Context) -> YouTubeTrailerHostView {
        let host = YouTubeTrailerHostView(frame: .zero)
        session.attach(to: host)
        return host
    }
    func updateNSView(_ host: YouTubeTrailerHostView, context: Context) { session.attach(to: host) }
    static func dismantleNSView(_ host: YouTubeTrailerHostView, coordinator: ()) { host.session?.detach(from: host) }
}
#else
private struct YouTubeTrailerNativeSurface: UIViewRepresentable {
    let session: YouTubeTrailerSession
    func makeUIView(context: Context) -> YouTubeTrailerHostView {
        let host = YouTubeTrailerHostView(frame: .zero)
        session.attach(to: host)
        return host
    }
    func updateUIView(_ host: YouTubeTrailerHostView, context: Context) { session.attach(to: host) }
    static func dismantleUIView(_ host: YouTubeTrailerHostView, coordinator: ()) { host.session?.detach(from: host) }
}
#endif
#endif
