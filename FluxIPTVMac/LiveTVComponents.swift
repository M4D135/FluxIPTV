import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Large television tiles and compact desktop rows share the same channel
/// data. The surrounding button owns focus; only its selected tile gets video.
struct LiveTVChannelLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: IPTVItem
    let number: Int
    let favorite: Bool
    let highlighted: Bool
    let accent: Color
    var preview: LiveTVPreviewController? = nil
    var delay: LiveTVPreviewDelay = .three
    var automaticPreview = true

    private var logoSize: CGFloat {
        #if os(tvOS)
        72
        #else
        52
        #endif
    }

    var body: some View {
        #if os(tvOS)
        televisionTile
        #else
        HStack(spacing: 14) {
            ArtworkView(url: item.logoURL, fit: true) {
                Image(systemName: "tv").font(.title2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(7)
            .frame(width: logoSize, height: logoSize)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            .clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.headline).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.group).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(.red.opacity(0.9)).frame(width: 5, height: 5)
                    Text("DIRECT").font(.system(size: 9, weight: .semibold)).tracking(1)
                    Text("· \(number)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if favorite {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: logoSize + 32, alignment: .leading)
        .background(highlighted ? accent.opacity(0.20) : .black.opacity(0.25), in: RoundedRectangle(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .strokeBorder(highlighted ? .white.opacity(0.85) : .white.opacity(0.11), lineWidth: highlighted ? 2 : 0.8)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 19))
        .scaleEffect(highlighted && !reduceMotion ? 1.018 : 1)
        .offset(y: highlighted && !reduceMotion ? -2 : 0)
        .shadow(color: .black.opacity(highlighted ? 0.32 : 0), radius: 12, x: 0, y: 9)
        #endif
    }

    #if os(tvOS)
    private var televisionTile: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                if let preview {
                    // ContentView passes its single preview controller only to
                    // the focused tile. Other channels retain static artwork.
                    LiveTVPreviewScreen(preview: preview, item: item, delay: delay, automatic: automaticPreview)
                } else {
                    channelArtwork
                }
                HStack(spacing: 9) {
                    Text(String(format: "%02d", number)).font(.system(size: 18, weight: .semibold, design: .monospaced))
                    if favorite { Image(systemName: "star.fill").font(.system(size: 18)).foregroundStyle(.yellow) }
                }
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.70), in: Capsule())
                .padding(13)
            }
            Text(item.name)
                .font(.system(size: 27, weight: .semibold)).lineLimit(2, reservesSpace: true)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.group)
                .font(.system(size: 20, weight: .medium)).lineLimit(1)
                .foregroundStyle(.white.opacity(0.57))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? Color(red: 0.10, green: 0.13, blue: 0.17) : Color(red: 0.035, green: 0.045, blue: 0.065),
                    in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(highlighted ? .white.opacity(0.95) : .white.opacity(0.08), lineWidth: highlighted ? 3 : 1)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .scaleEffect(highlighted && !reduceMotion ? 1.025 : 1)
        .offset(y: highlighted && !reduceMotion ? -3 : 0)
    }

    private var channelArtwork: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Color(red: 0.065, green: 0.080, blue: 0.11)
                if let backdrop = item.backdropURL {
                    ArtworkView(url: backdrop, fit: false) { Color.clear }
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    ArtworkView(url: item.logoURL, fit: true) {
                        Image(systemName: "tv.fill").font(.system(size: 64, weight: .light)).foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(width: geometry.size.width * 0.66, height: geometry.size.height * 0.64)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                Label("EN DIRECT", systemImage: "circle.fill")
                    .font(.system(size: 15, weight: .bold)).tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.black.opacity(0.72), in: Capsule())
                    .padding(13)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    #endif
}

struct LiveTVPreviewScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var preview: LiveTVPreviewController
    let item: IPTVItem
    let delay: LiveTVPreviewDelay
    let automatic: Bool

    private var displayedPhase: LiveTVPreviewController.Phase {
        preview.previewedItemID == item.id ? preview.phase : .idle
    }

    private var showPlaceholder: Bool {
        #if os(tvOS)
        displayedPhase != .playing
        #else
        true
        #endif
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.18), .black.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if showPlaceholder {
                GeometryReader { geometry in
                    VStack(spacing: geometry.size.height < 100 ? 4 : 10) {
                        ArtworkView(url: item.logoURL, fit: true) {
                            Image(systemName: "tv").font(.title2).foregroundStyle(.secondary)
                        }
                        #if os(tvOS)
                        .frame(width: geometry.size.width * 0.66, height: geometry.size.height * 0.56)
                        #else
                        .frame(width: min(78, geometry.size.width * 0.5), height: min(64, geometry.size.height * 0.5))
                        #endif
                        if displayedPhase == .loading { ProgressView().controlSize(.small) }
                        else if geometry.size.height >= 100 {
                            #if os(tvOS)
                            Text(status).font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).lineLimit(2)
                            #else
                            Text(status).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
                            #endif
                        }
                    }
                    .padding(geometry.size.height < 100 ? 4 : 14)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            if preview.previewedItemID == item.id, let player = preview.player {
                LiveTVNativePreview(player: player)
                    .opacity(displayedPhase == .playing ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: displayedPhase == .playing)
            }
            #if os(tvOS)
            if displayedPhase == .playing {
                VStack {
                    Spacer()
                    HStack {
                        Label("EN DIRECT", systemImage: "circle.fill")
                            .font(.system(size: 15, weight: .bold)).tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.black.opacity(0.72), in: Capsule())
                        Spacer(minLength: 0)
                    }
                }.padding(13)
            }
            #endif
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.30), lineWidth: 1).allowsHitTesting(false)
        }
        #if !os(tvOS)
        .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 12)
        #endif
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    private var status: String {
        if !automatic { return "Aperçu automatique désactivé" }
        switch displayedPhase {
        case .idle, .waiting: return "Aperçu après \(delay.title)"
        case .loading: return "Ouverture de la chaîne…"
        case .playing: return "En direct"
        case .failed: return "Aperçu indisponible. Vous pouvez ouvrir la chaîne."
        }
    }
}

#if os(macOS)
@MainActor private final class LiveTVLayerView: NSView {
    private let videoLayer = AVPlayerLayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        videoLayer.videoGravity = .resizeAspect
        layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
    func setPlayer(_ player: AVPlayer?) { if videoLayer.player !== player { videoLayer.player = player } }
}
private struct LiveTVNativePreview: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> LiveTVLayerView { let view = LiveTVLayerView(frame: .zero); view.setPlayer(player); return view }
    func updateNSView(_ view: LiveTVLayerView, context: Context) { view.setPlayer(player) }
    static func dismantleNSView(_ view: LiveTVLayerView, coordinator: ()) { view.setPlayer(nil) }
}
#else
@MainActor private final class LiveTVLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    func setPlayer(_ player: AVPlayer?) {
        let videoLayer = layer as! AVPlayerLayer
        videoLayer.videoGravity = .resizeAspect
        if videoLayer.player !== player { videoLayer.player = player }
    }
}
private struct LiveTVNativePreview: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> LiveTVLayerView { let view = LiveTVLayerView(frame: .zero); view.setPlayer(player); return view }
    func updateUIView(_ view: LiveTVLayerView, context: Context) { view.setPlayer(player) }
    static func dismantleUIView(_ view: LiveTVLayerView, coordinator: ()) { view.setPlayer(nil) }
}
#endif

/// Sidebar rows use one enclosing glass surface rather than a glass effect
/// for every category. Labels remain readable while scrolling a large list.
struct LiveTVScopeLabel: View {
    let title: String
    let symbol: String
    var count: Int? = nil
    let selected: Bool
    let focused: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 20)
                .foregroundStyle(selected ? accent : .secondary)
            Text(title).font(.callout.weight(selected ? .semibold : .regular))
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if let count { Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(accent) }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(selected ? accent.opacity(0.16) : .white.opacity(focused ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(focused ? .white.opacity(0.75) : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13))
    }
}
