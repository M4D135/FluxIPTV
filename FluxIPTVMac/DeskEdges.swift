import SwiftUI

#if os(tvOS)
/// The edges of a screen at the remote of a television, as at the keys of
/// a Mac: no press leads nowhere. The focus engine of tvOS goes nowhere when
/// nothing lies in the way of a press. Four strips that no one sees stand
/// along the edges of the screen: the remote finds one only where nothing
/// else lies that way, and the screen sends it on, where a fresh press of a
/// Mac goes from the control it left (`FluxScreen.crossEdge`): Left to Back,
/// any other way to the icon of the screen, round the bar at its ends, and
/// from the bar away from the screen to its top.
///
/// A run of presses stops at the edge: the strips take the remote only
/// after a pause, as a Mac tells a fresh press (`FluxPressCadence`).
@MainActor @Observable final class DeskEdges {
    enum Side: String, CaseIterable {
        case left, right, top, bottom

        var id: String { Self.prefix + rawValue }
        init?(id: String) {
            guard id.hasPrefix(Self.prefix) else { return nil }
            self.init(rawValue: String(id.dropFirst(Self.prefix.count)))
        }
        private static let prefix = "desk-edge-"

        /// The press that leads to this strip.
        var action: RemoteAction {
            switch self {
            case .left: .left
            case .right: .right
            case .top: .up
            case .bottom: .down
            }
        }
        var alongHeight: Bool { self == .left || self == .right }
        var alignment: Alignment {
            switch self {
            case .left: .leading
            case .right: .trailing
            case .top: .top
            case .bottom: .bottom
            }
        }
    }

    /// The strips may take the remote: a pause has followed the last move.
    private(set) var armed = false
    /// The last control of the screen that held the remote. Nil for a
    /// control with a focus of its own, as the field of the search or the
    /// rows of the settings.
    @ObservationIgnored private(set) var last: String?
    @ObservationIgnored private var revision = 0

    /// The remote moved: the strips wait for a pause before they take it.
    func moved(to id: String?) {
        last = id
        rest()
    }

    /// The strips stand back until the remote has paused.
    func rest() {
        if armed { armed = false }
        revision &+= 1
        let mine = revision
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((FluxPressCadence.pause + 0.05) * 1_000_000_000))
            guard let self, self.revision == mine else { return }
            self.armed = true
        }
    }
}

/// The strips themselves. Only they read whether they may take the remote:
/// a press redraws four invisible keys, not the screen.
struct DeskEdgeStrips: View {
    let edges: DeskEdges
    let sides: [DeskEdges.Side]
    let focus: FocusState<String?>.Binding

    var body: some View {
        let armed = edges.armed
        ZStack {
            ForEach(sides, id: \.self) { side in
                Button {} label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(FluxBareButtonStyle())
                    .focusEffectDisabled()
                    .focused(focus, equals: side.id)
                    .frame(width: side.alongHeight ? Self.thickness : nil, height: side.alongHeight ? nil : Self.thickness)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: side.alignment)
                    // Out of reach until the remote has paused.
                    .disabled(!armed)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
        // A screen that has just come keeps the remote where it puts it.
        .onAppear { edges.rest() }
    }

    private static let thickness: CGFloat = 8
}
#endif
