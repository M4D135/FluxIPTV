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

/// The image and loading/error states only. ContentView owns one transient
/// control surface so windowed playback never draws two transport bars.
struct PlayerSurface: View {
    @ObservedObject var playback: PlaybackController
    var immersive = false
    /// The banner of the channel tells what the stream does: nothing is
    /// drawn in the middle of the picture.
    var quiet = false

    var body: some View {
        ZStack {
            Color.black
            #if os(macOS)
            NativeVideoSurface(player: playback.player)
            #else
            Group {
                if playback.engine == .native { NativeVideoSurface(player: playback.player) }
                else { VLCVideoSurface(playback: playback) }
            }
            #if os(iOS)
            // Only the image extends under device cutouts. Transient commands
            // remain in the safe area in ContentView.
            .ignoresSafeArea(.container, edges: immersive ? .all : [])
            #endif
            #endif
            if playback.opening && !quiet {
                VStack(spacing: Desk.pt(10)) {
                    ProgressView()
                        #if !os(tvOS)
                        .controlSize(.large)
                        #endif
                    Text("Ouverture du flux…").font(Desk.font(.headline))
                    // Which engine is trying, and which of its attempts.
                    if !playback.attemptLabel.isEmpty {
                        Text(playback.attemptLabel).font(Desk.font(.caption)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .foregroundStyle(.white)
                .padding(Desk.pt(22)).fluxMediaGlass(radius: Desk.pt(22))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
            if let error = playback.playbackError, !quiet {
                VStack(spacing: Desk.pt(12)) {
                    Image(systemName: "play.slash.fill").font(Desk.font(.largeTitle))
                    Text("Impossible de lire ce flux").font(Desk.font(.headline))
                    Text(error).font(Desk.font(.caption)).foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Button("Réessayer") { playback.retry(preferred: playback.preferredEngine) }
                        .deskKey(prominent: true)
                        .accessibilityIdentifier("player-retry")
                    #if os(macOS)
                    if playback.externalVLCVariants.count > 1 {
                        Menu("Ouvrir dans VLC externe") {
                            ForEach(playback.externalVLCVariants) { variant in
                                Button(variant.title) { playback.openExternalVLC(variantID: variant.id) }
                            }
                        }
                        .buttonStyle(.bordered)
                    } else if let variant = playback.externalVLCVariants.first {
                        Button("Ouvrir dans VLC externe") { playback.openExternalVLC(variantID: variant.id) }
                            .buttonStyle(.bordered)
                    }
                    #endif
                }
                .foregroundStyle(.white)
                .padding(Desk.pt(20)).frame(maxWidth: Desk.pt(440)).fluxGlass(radius: Desk.pt(22))
                .padding(Desk.pt(20))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
