import SwiftUI

// MARK: - Where the remote is
//
// "on devrait faire un léger effet mouvement widget Apple TV sur le panel
// pour montrer dans quelle zone on est ; marque pas zones, trouve un terme
// ou autre ou limite p'tit logo … mais discret" ; "le tips zone suivante
// fous-le ailleurs et fais-le plus discret, genre bas milieu et plus petit"
// (David, 26/11). The part of the screen that holds the remote shows a thin
// edge, crossed once by a glint as it is entered; at the foot of the screen
// a small plan lights the same part, beside the key that goes to the next.

/// What the small plan of the screen shows.
struct DeskMapModel: Equatable {
    /// The parts of this screen.
    let parts: [DeskZone]
    /// The part that holds the remote; nil lights none.
    let active: DeskZone?
    let dock: FluxDockPosition
}

/// A small plan of the screen: its parts drawn where they stand, the one
/// that holds the remote lit, and beside it the key that goes to the next.
struct DeskMiniMap: View, Equatable {
    let model: DeskMapModel

    private static let width: CGFloat = 30
    private static let height: CGFloat = 17

    var body: some View {
        HStack(spacing: Desk.pt(6)) {
            plan
            key
        }
        .padding(.horizontal, Desk.pt(7)).padding(.vertical, Desk.pt(4))
        .background(.black.opacity(0.30), in: Capsule())
        .opacity(0.8)
        .accessibilityElement(children: .ignore)
        #if os(tvOS)
        .accessibilityLabel("Lecture/Pause : partie suivante de l’écran")
        #else
        .accessibilityLabel("Tabulation : partie suivante de l’écran")
        .help("Tab passe d’une partie de l’écran à la suivante, dans le sens des aiguilles d’une montre : contenu, aperçu, barre, colonne, recherche. ⌘ + flèche va droit à la partie de ce côté.")
        #endif
        .accessibilityIdentifier("desk-zone-hint")
    }

    /// The key, drawn small as a key.
    private var key: some View {
        Group {
            #if os(tvOS)
            Image(systemName: "playpause.fill")
            #else
            Text("⇥").fontWeight(.heavy)
            #endif
        }
        .font(.system(size: Desk.pt(10), weight: .bold))
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, Desk.pt(4)).frame(minHeight: Desk.pt(15))
        .overlay(RoundedRectangle(cornerRadius: Desk.pt(4), style: .continuous)
            .strokeBorder(.white.opacity(0.45), lineWidth: 1))
    }

    private var plan: some View {
        let w = Desk.pt(Self.width), h = Desk.pt(Self.height)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Desk.pt(3), style: .continuous)
                .strokeBorder(.white.opacity(0.42), lineWidth: 1)
            ForEach(model.parts, id: \.self) { part in
                let frame = Self.frame(part, dock: model.dock, in: CGSize(width: w, height: h))
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(.white.opacity(part == model.active ? 0.95 : 0.24))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: w, height: h)
        .animation(.easeOut(duration: 0.18), value: model.active)
    }

    /// Where each part stands on a screen of `size`, the bar on its edge.
    static func frame(_ part: DeskZone, dock: FluxDockPosition, in size: CGSize) -> CGRect {
        let inset: CGFloat = 2.5, gap: CGFloat = 1.5, bar: CGFloat = 3
        var area = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        var barRect: CGRect
        switch dock {
        case .bottom, .corner:
            barRect = CGRect(x: area.minX + area.width * 0.25, y: area.maxY - bar, width: area.width * 0.5, height: bar)
            area.size.height -= bar + gap
        case .top:
            barRect = CGRect(x: area.minX + area.width * 0.25, y: area.minY, width: area.width * 0.5, height: bar)
            area.origin.y += bar + gap; area.size.height -= bar + gap
        case .leading:
            barRect = CGRect(x: area.minX, y: area.minY + area.height * 0.2, width: bar, height: area.height * 0.6)
            area.origin.x += bar + gap; area.size.width -= bar + gap
        case .trailing:
            barRect = CGRect(x: area.maxX - bar, y: area.minY + area.height * 0.2, width: bar, height: area.height * 0.6)
            area.size.width -= bar + gap
        }
        // Under the column, the bar is as wide as the column.
        if dock == .corner { barRect = CGRect(x: area.minX, y: barRect.minY, width: area.width * 0.22, height: bar) }
        let top = CGRect(x: area.minX, y: area.minY, width: area.width, height: 2.5)
        let below = CGRect(x: area.minX, y: top.maxY + gap, width: area.width, height: area.maxY - top.maxY - gap)
        let column = CGRect(x: below.minX, y: below.minY, width: below.width * 0.22, height: below.height)
        let rest = CGRect(x: column.maxX + gap, y: below.minY, width: below.maxX - column.maxX - gap, height: below.height)
        switch part {
        case .dock: return barRect
        case .top: return top
        case .column: return column
        case .content: return CGRect(x: rest.minX, y: rest.minY, width: rest.width * 0.62, height: rest.height)
        case .actions: return CGRect(x: rest.minX + rest.width * 0.62 + gap, y: rest.minY,
                                     width: rest.width * 0.38 - gap, height: rest.height)
        }
    }
}

/// The thin edge of the part that holds the remote; with « reflet », a
/// glint crosses it once as the part is entered, as on a widget of the
/// Apple TV. One layer that moves once: nothing runs while the remote
/// stays in the part.
struct DeskPanelGlint: View {
    let radius: CGFloat
    let accent: Color
    let sweeps: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var crossed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.strokeBorder(accent.opacity(0.5), lineWidth: 1.5)
            if sweeps && !reduceMotion {
                GeometryReader { geometry in
                    let size = geometry.size
                    let band = max(size.width, size.height) * 0.32
                    LinearGradient(stops: [.init(color: .white.opacity(0), location: 0),
                                           .init(color: .white.opacity(1), location: 0.5),
                                           .init(color: .white.opacity(0), location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: band, height: size.height * 2.2)
                        .rotationEffect(.degrees(20))
                        .position(x: crossed ? size.width + band : -band, y: size.height / 2)
                }
                // A bright streak along the edge, a faint sheen inside.
                .mask {
                    ZStack {
                        shape.strokeBorder(lineWidth: 2.5)
                        shape.fill(.white.opacity(0.12))
                    }
                }
                .opacity(0.75)
            }
        }
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard sweeps, !reduceMotion, !crossed else { return }
            withAnimation(.easeOut(duration: 0.95).delay(0.04)) { crossed = true }
        }
    }
}
