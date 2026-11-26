import SwiftUI

// MARK: - What is drawn over the picture during playback

/// One action of the bar under the picture: a round key and its name. The
/// key under the remote, the keyboard or the pointer turns white and grows,
/// the way a television shows where it stands.
struct PlayerActionLabel: View {
    let symbol: String
    let title: String
    /// Play and pause stand out among the others.
    var prominent = false
    var highlighted = false
    /// A state that is on: a favourite, a muted sound, an open list.
    var active = false
    var tint: Color = .white
    /// A narrow window keeps the keys and leaves their names out.
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var width: CGFloat { Desk.pt(78) }

    var body: some View {
        let side = compact ? CGFloat(prominent ? 46 : 40) : Desk.pt(prominent ? 58 : 48)
        // Every key keeps the room of the largest one: their names line up.
        let room = compact ? CGFloat(46) : Desk.pt(58)
        VStack(spacing: Desk.pt(4)) {
            Image(systemName: symbol)
                .font(.system(size: compact ? (prominent ? 20 : 16) : Desk.pt(prominent ? 24 : 19), weight: .semibold))
                .foregroundStyle(highlighted ? Color.black : active ? tint : Color.white)
                .frame(width: side, height: side)
                .background(highlighted ? Color.white : Color.white.opacity(prominent ? 0.24 : 0.10), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(highlighted ? 0 : 0.18), lineWidth: 1))
                .shadow(color: .black.opacity(highlighted ? 0.4 : 0), radius: 10, y: 5)
                .scaleEffect(highlighted && !reduceMotion ? 1.12 : 1)
                .frame(width: room, height: room)
            if !compact {
                Text(title)
                    .font(Desk.font(.caption2, highlighted ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(highlighted ? 1 : 0.76))
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
        }
        .frame(width: compact ? side + 4 : Self.width)
        .opacity(isEnabled ? 1 : 0.34)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78), value: highlighted)
    }
}

/// Position in a film or an episode, where a slider cannot be used.
struct PlayerProgressTrack: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.24))
                Capsule().fill(.white)
                    .frame(width: max(height, geometry.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: Desk.pt(6))
    }
}

/// Darkens the top and the foot of the picture, so that what is written
/// there stays readable over a bright image.
struct PlayerScrim: View {
    /// The banner of a channel stands at the foot only.
    var top = true

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if top {
                    LinearGradient(colors: [.black.opacity(0.66), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: geometry.size.height * 0.26)
                }
                Spacer(minLength: 0)
                LinearGradient(colors: [.black.opacity(0), .black.opacity(top ? 0.72 : 0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.size.height * (top ? 0.42 : 0.3))
            }
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// The banner of a channel at the foot of the picture, as a television
/// shows it when the channel changes: its number, its logo, its name on one
/// line, its category, what the stream is doing, the time, and what the
/// remote does from there. It stands alone over the picture: the commands
/// stay away while the channels are walked.
struct PlayerChannelBanner: View {
    enum Status: Equatable {
        case live, opening, failed
    }
    /// A key of the remote or of the keyboard, and what it does.
    struct Hint: Identifiable {
        var symbol: String? = nil
        var text: String? = nil
        let action: String
        var id: String { action }
    }

    let number: Int?
    let name: String
    let group: String
    let logoURL: URL?
    let favorite: Bool
    let status: Status
    let accent: Color
    var hints: [Hint] = []
    /// A narrow window keeps the channel and leaves the clock and the hints out.
    var compact = false

    var body: some View {
        HStack(alignment: .center, spacing: Desk.pt(compact ? 10 : 18)) {
            if let number {
                // A channel number is read at a glance, and never wraps.
                Text(String(number))
                    .font(.system(size: Desk.pt(compact ? 26 : 40), weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent).lineLimit(1).fixedSize()
            }
            ArtworkView(url: logoURL, fit: true) {
                Image(systemName: "tv").font(Desk.font(.title2)).foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: Desk.pt(compact ? 46 : 74), height: Desk.pt(compact ? 32 : 48))
            .padding(Desk.pt(6))
            .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: Desk.pt(12), style: .continuous))
            VStack(alignment: .leading, spacing: Desk.pt(6)) {
                // The name is what the banner is for: it has the whole line,
                // up to the time, and shrinks before it is cut.
                HStack(alignment: .firstTextBaseline, spacing: Desk.pt(14)) {
                    Text(name).font(Desk.font(compact ? .headline : .title, .bold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !compact {
                        TimelineView(.everyMinute) { context in
                            Text(context.date.formatted(.dateTime.hour().minute()))
                                .font(Desk.font(.title3, .semibold).monospacedDigit())
                        }
                        .fixedSize()
                    }
                }
                HStack(spacing: Desk.pt(9)) {
                    statusBadge.fixedSize()
                    if !group.isEmpty {
                        Text(group).font(Desk.font(.callout)).foregroundStyle(.white.opacity(0.74)).lineLimit(1)
                    }
                    if favorite {
                        Image(systemName: "star.fill").font(Desk.font(.caption)).foregroundStyle(.yellow)
                    }
                    Spacer(minLength: Desk.pt(10))
                    if !compact && !hints.isEmpty {
                        HStack(spacing: Desk.pt(12)) { ForEach(hints) { hint($0) } }.fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Desk.pt(compact ? 14 : 24)).padding(.vertical, Desk.pt(compact ? 10 : 15))
        .frame(maxWidth: Desk.pt(900))
        .fluxMediaGlass(radius: Desk.pt(compact ? 20 : 30))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(number.map { "Chaîne \($0), \(name)" } ?? name)
        .accessibilityValue(spoken)
        .accessibilityIdentifier("player-banner")
    }

    private var spoken: String {
        let state: String
        switch status {
        case .live: state = "En direct"
        case .opening: state = "Ouverture"
        case .failed: state = "Indisponible"
        }
        return group.isEmpty ? state : state + ", " + group
    }

    @ViewBuilder private var statusBadge: some View {
        switch status {
        case .live:
            HStack(spacing: Desk.pt(6)) {
                Circle().fill(.red).frame(width: Desk.pt(8), height: Desk.pt(8))
                Text("EN DIRECT").font(Desk.font(.caption, .bold)).tracking(0.8)
            }
        case .opening:
            HStack(spacing: Desk.pt(7)) {
                DeskSpinner().frame(width: Desk.pt(14), height: Desk.pt(14))
                Text("OUVERTURE…").font(Desk.font(.caption, .bold)).tracking(0.8)
            }
        case .failed:
            HStack(spacing: Desk.pt(6)) {
                Image(systemName: "exclamationmark.triangle.fill").font(Desk.font(.caption)).foregroundStyle(.yellow)
                Text("INDISPONIBLE").font(Desk.font(.caption, .bold)).tracking(0.8)
            }
        }
    }

    private func hint(_ hint: Hint) -> some View {
        HStack(spacing: Desk.pt(5)) {
            Group {
                if let symbol = hint.symbol { Image(systemName: symbol).font(Desk.system(9, .bold)) }
                else { Text(hint.text ?? "").font(Desk.system(9, .bold)) }
            }
            .padding(.horizontal, Desk.pt(6)).frame(minWidth: Desk.pt(22), minHeight: Desk.pt(20))
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: Desk.pt(6), style: .continuous))
            Text(hint.action).font(Desk.font(.caption2)).foregroundStyle(.white.opacity(0.72))
        }
    }
}

/// A small turning arc: the wheel of the system is too large on a television
/// to stand in a line of text.
struct DeskSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            Circle().trim(from: 0.08, to: 0.78)
                .stroke(.white, style: StrokeStyle(lineWidth: Desk.pt(2.2), lineCap: .round))
                .rotationEffect(.degrees(reduceMotion ? 0 : turn * 360))
        }
        .accessibilityHidden(true)
    }
}

/// Identifiers of the audio and subtitle rows, shared by their panel and by
/// the navigation of a keyboard.
enum PlayerTracks {
    static let buttonID = "tracks"
    static let closeID = "tracks-close"
    static func audioID(_ id: String) -> String { "track-audio-" + id }
    static func subtitleID(_ id: String?) -> String { "track-sub-" + (id ?? "off") }

    /// Rows a keyboard walks: the close button, then both columns side by side.
    static func rows(audio: [PlaybackTrack], subtitles: [PlaybackTrack], canBeOff: Bool) -> [[String]] {
        let left = audio.map { audioID($0.id) }
        let right = (canBeOff && !subtitles.isEmpty ? [subtitleID(nil)] : []) + subtitles.map { subtitleID($0.id) }
        var rows: [[String]] = [[closeID]]
        for index in 0..<max(left.count, right.count) {
            rows.append((index < left.count ? [left[index]] : []) + (index < right.count ? [right[index]] : []))
        }
        return rows
    }

    /// Row that receives the remote when the panel opens: the audio in use.
    static func entry(audio: [PlaybackTrack], subtitles: [PlaybackTrack], canBeOff: Bool) -> String {
        if let current = audio.first(where: \.selected) ?? audio.first { return audioID(current.id) }
        return rows(audio: audio, subtitles: subtitles, canBeOff: canBeOff).dropFirst().first?.first ?? closeID
    }
}

/// Languages of the media on screen: the audio on the left, the subtitles on
/// the right. Choosing a row applies it at once; nothing is to be saved.
struct PlayerTracksPanel: View {
    let audio: [PlaybackTrack]
    let subtitles: [PlaybackTrack]
    let subtitlesCanBeOff: Bool
    /// Row under the remote or the keyboard.
    let focusedID: String?
    let systemFocus: FocusState<String?>.Binding
    let accent: Color
    let selectAudio: (String) -> Void
    let selectSubtitle: (String?) -> Void
    let close: () -> Void
    @State private var hovered: String?

    private static var rowHeight: CGFloat { Desk.pt(42) }
    private static var rowGap: CGFloat { Desk.pt(5) }
    /// Row drawn as selected. A television reads its focus here, so that
    /// this panel alone follows the remote.
    private var shownID: String? {
        #if os(tvOS)
        systemFocus.wrappedValue
        #else
        focusedID
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Desk.pt(12)) {
            HStack(spacing: Desk.pt(10)) {
                Label("Audio et sous-titres", systemImage: "captions.bubble.fill")
                    .font(Desk.font(.headline)).foregroundStyle(.white)
                Spacer(minLength: Desk.pt(8))
                closeButton
            }
            HStack(alignment: .top, spacing: Desk.pt(14)) {
                column("AUDIO", count: audio.count, note: audio.isEmpty ? "Ce flux n’annonce pas ses pistes audio." : nil) {
                    ForEach(audio) { track in
                        row(PlayerTracks.audioID(track.id), title: track.title, selected: track.selected) { selectAudio(track.id) }
                    }
                }
                column("SOUS-TITRES", count: subtitles.isEmpty ? 0 : subtitles.count + (subtitlesCanBeOff ? 1 : 0),
                       note: subtitles.isEmpty ? "Ce flux n’annonce aucun sous-titre." : nil) {
                    if subtitlesCanBeOff && !subtitles.isEmpty {
                        row(PlayerTracks.subtitleID(nil), title: "Désactivés", selected: !subtitles.contains(where: \.selected)) { selectSubtitle(nil) }
                    }
                    ForEach(subtitles) { track in
                        row(PlayerTracks.subtitleID(track.id), title: track.title, selected: track.selected) { selectSubtitle(track.id) }
                    }
                }
            }
        }
        .padding(Desk.pt(18))
        .frame(width: Desk.pt(700))
        .fluxMediaGlass(radius: Desk.pt(28))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Audio et sous-titres")
    }

    private var closeButton: some View {
        let id = PlayerTracks.closeID
        let lit = shownID == id || hovered == id
        return Button(action: close) {
            Image(systemName: "xmark").font(Desk.system(13, .bold))
                .foregroundStyle(lit ? Color.black : .white)
                .frame(width: Desk.pt(34), height: Desk.pt(34))
                .background(lit ? Color.white : Color.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(FluxBareButtonStyle())
        .playerFocus(systemFocus, id: id).id(id)
        .accessibilityLabel("Fermer").accessibilityIdentifier(id)
        #if !os(tvOS)
        .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
        #endif
    }

    /// Five rows show at once; a longer list scrolls under the remote.
    private func column<Rows: View>(_ title: String, count: Int, note: String?, @ViewBuilder rows: () -> Rows) -> some View {
        let shown = CGFloat(min(max(count, 1), 5))
        return VStack(alignment: .leading, spacing: Desk.pt(8)) {
            Text(title).font(Desk.system(11, .bold)).tracking(1.6).foregroundStyle(.white.opacity(0.55))
            if let note {
                Text(note).font(Desk.font(.callout)).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: Self.rowGap) { rows() }
                        // Room for the white key of the first and last row.
                        .padding(.vertical, 2)
                }
                .frame(height: shown * Self.rowHeight + (shown - 1) * Self.rowGap + 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func row(_ id: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let lit = shownID == id || hovered == id
        let shape = RoundedRectangle(cornerRadius: Desk.pt(12), style: .continuous)
        return Button(action: action) {
            HStack(spacing: Desk.pt(10)) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(Desk.font(.body))
                    .foregroundStyle(lit ? Color.black : selected ? accent : Color.white.opacity(0.5))
                Text(title).font(Desk.font(.callout, selected ? .semibold : .regular)).lineLimit(1)
                    .foregroundStyle(lit ? Color.black : .white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Desk.pt(12)).frame(height: Self.rowHeight)
            .background(lit ? Color.white : Color.white.opacity(selected ? 0.14 : 0.06), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(FluxBareButtonStyle())
        .playerFocus(systemFocus, id: id).id(id)
        .accessibilityIdentifier(id)
        .accessibilityLabel(title).accessibilityValue(selected ? "Sélectionnée" : "")
        #if os(tvOS) && FLUX_CATALOG_UI_TESTING
        .background(TVCatalogControlFrameProbe(identifier: id).allowsHitTesting(false))
        #endif
        #if !os(tvOS)
        .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
        #endif
    }
}

/// A key of the desk that shows by itself when the remote is on it: white
/// with a dark ink, as everywhere on a television. A pointer lights it too.
struct DeskKeyStyle: ButtonStyle {
    var prominent = false
    var tint: Color = .cyan

    func makeBody(configuration: Configuration) -> some View {
        Key(configuration: configuration, prominent: prominent, tint: tint)
    }

    private struct Key: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let tint: Color
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        /// The keyboard of the settings of a Mac is on this key.
        @Environment(\.deskTargeted) private var targeted
        @State private var hovered = false

        var body: some View {
            let lit = (isFocused || hovered || targeted) && isEnabled
            let shape = RoundedRectangle(cornerRadius: Desk.pt(14), style: .continuous)
            configuration.label
                .font(Desk.font(.body, .semibold)).lineLimit(1)
                .foregroundStyle(lit ? Color.black : .white)
                .padding(.horizontal, Desk.pt(18)).padding(.vertical, Desk.pt(10))
                .background(lit ? Color.white : prominent ? tint.opacity(0.34) : Color.white.opacity(0.10), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(lit ? 0 : 0.18), lineWidth: 1).allowsHitTesting(false))
                .scaleEffect(configuration.isPressed ? 0.97 : lit && !reduceMotion ? 1.04 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(shape)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: lit)
                #if !os(tvOS)
                .onHover { hovered = $0 }
                #endif
        }
    }
}

private extension View {
    /// The same binding as the controls of the screen: each one draws its own
    /// highlight, without the ring of the system.
    @ViewBuilder func playerFocus(_ binding: FocusState<String?>.Binding, id: String) -> some View {
        #if os(tvOS)
        self.focused(binding, equals: id).focusEffectDisabled()
        #else
        self.focusable().focused(binding, equals: id).focusEffectDisabled()
        #endif
    }
}
