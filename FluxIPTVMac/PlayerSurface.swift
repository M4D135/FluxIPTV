import SwiftUI
import AVKit
#if os(macOS)
import AppKit
private final class AVLayerView: NSView {
    private let videoLayer = AVPlayerLayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        videoLayer.videoGravity = .resizeAspect
        layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); videoLayer.frame = bounds; CATransaction.commit() }
    func setPlayer(_ player: AVPlayer) { if videoLayer.player !== player { videoLayer.player = player } }
}
private struct NativeVideoSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVLayerView { let v = AVLayerView(frame: .zero); v.setPlayer(player); return v }
    func updateNSView(_ view: AVLayerView, context: Context) { view.setPlayer(player) }
}
#else
import UIKit
private final class AVLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    func setPlayer(_ player: AVPlayer) { let v = layer as! AVPlayerLayer; v.videoGravity = .resizeAspect; if v.player !== player { v.player = player }; backgroundColor = .black }
}
private struct NativeVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> AVLayerView { let v = AVLayerView(frame: .zero); v.setPlayer(player); return v }
    func updateUIView(_ view: AVLayerView, context: Context) { view.setPlayer(player) }
}
private final class VLCWindowView: UIView {
    weak var controller: PlaybackController?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { let view=self; DispatchQueue.main.async { view.controller?.attachVLC(view) } }
    }
}
struct VLCVideoSurface: UIViewRepresentable {
    let playback: PlaybackController
    func makeUIView(context: Context) -> UIView {
        let view = VLCWindowView()
        view.controller = playback
        view.backgroundColor = .black
        DispatchQueue.main.async { playback.attachVLC(view) }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { playback.attachVLC(view) }
    }
}
#endif

struct PlayerSurface: View {
    @ObservedObject var playback: PlaybackController
    var showsTransport: Bool = true
    @State private var scrubPosition = 0.0
    @State private var scrubbing = false
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            #if os(macOS)
            NativeVideoSurface(player: playback.player)
            #else
            if playback.engine == .native { NativeVideoSurface(player: playback.player) }
            else { VLCVideoSurface(playback: playback) }
            #endif
            if showsTransport && showControls && !playback.opening && playback.playbackError == nil {
                controls.padding(12).transition(.opacity)
            }
            if playback.opening {
                VStack(spacing: 10) {
                    ProgressView()
                        #if !os(tvOS)
                        .controlSize(.large)
                        #endif
                    Text("Ouverture du flux…").font(.headline)
                    Text(playback.attemptLabel).font(.caption).foregroundStyle(.secondary)
                }
                .padding(22).fluxFrosted(radius: 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
            if playback.playbackError != nil {
                VStack(spacing: 12) {
                    Image(systemName: "play.slash.fill").font(.largeTitle)
                    Text("Impossible de lire ce flux").font(.headline)
                    Button("Réessayer") { playback.retry(preferred: playback.preferredEngine) }
                        .buttonStyle(.borderedProminent)
                    #if os(macOS)
                    Button("Ouvrir dans VLC externe") { playback.openExternalVLC() }.buttonStyle(.bordered)
                    #endif
                }
                .padding(20).fluxFrosted(radius: 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
        .onChange(of: playback.position) { _, value in if !scrubbing { scrubPosition = value } }
        .onChange(of: playback.playingItem?.id) { _, _ in scrubbing = false; scrubPosition = 0 }
    }

    private var showControls: Bool {
        #if os(macOS)
        return hovering || !playback.isPlaying
        #else
        return true
        #endif
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { playback.togglePause() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold)).frame(width: 30, height: 30)
            }.buttonStyle(.plain).accessibilityLabel("Lecture / pause")
            if playback.seekable {
                Text(playback.elapsed).font(.caption.monospacedDigit())
                #if os(tvOS)
                Button { playback.skip(seconds: -Double(playback.settings.skipSeconds)) } label: { Image(systemName: "gobackward") }
                ProgressView(value: playback.position).frame(maxWidth: .infinity)
                Button { playback.skip(seconds: Double(playback.settings.skipSeconds)) } label: { Image(systemName: "goforward") }
                #else
                Slider(value: $scrubPosition, in: 0...1, onEditingChanged: { editing in
                    scrubbing = editing
                    if !editing { playback.seek(scrubPosition) }
                }).labelsHidden()
                #endif
                Text(playback.duration).font(.caption.monospacedDigit())
            } else { Spacer(); Label(playback.engine.title, systemImage: "play.rectangle").font(.caption) }
            #if !os(tvOS)
            Button { playback.toggleMute() } label: { Image(systemName: playback.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 28, height: 28) }.buttonStyle(.plain).accessibilityLabel("Sourdine")
            Slider(value: Binding(get: { playback.localVolume }, set: { playback.setVolume($0) }), in: 0...1).labelsHidden().frame(width: 82).accessibilityLabel("Volume")
            #endif
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .fluxFrosted(radius: 25)
    }
}
