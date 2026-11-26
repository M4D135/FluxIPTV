import SwiftUI

// MARK: - Controls of the settings
//
// A television draws the pickers and the switches of the system at its own
// size, cuts their values when they are many and leaves their names out. The
// desk draws them itself: keys that are read from a sofa, never cut, with a
// ring under the remote. A Mac shows the same desk, so the same keys, which
// a pointer lights. On a phone the controls of the system remain.

/// One setting among a few values.
struct DeskChoice<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        #if os(tvOS) || os(macOS)
        VStack(alignment: .leading, spacing: Desk.pt(7)) {
            Text(title).font(Desk.font(.callout, .semibold)).foregroundStyle(.white.opacity(0.78))
            DeskFlow(spacing: Desk.pt(7)) {
                ForEach(options.indices, id: \.self) { index in key(index) }
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
        #else
        Picker(title, selection: $selection) {
            ForEach(options.indices, id: \.self) { index in Text(options[index].title).tag(options[index].value) }
        }
        #endif
    }
}

#if os(tvOS) || os(macOS)
private extension DeskChoice {
    func key(_ index: Int) -> some View {
        let option = options[index]
        let selected = option.value == selection
        let choose = { selection = option.value }
        return Button(action: choose) { DeskChoiceKey(title: option.title, selected: selected) }
            .buttonStyle(DeskFocusStyle(radius: Desk.pt(22)))
            .accessibilityLabel(title + " : " + option.title)
            .accessibilityValue(selected ? "Sélectionné" : "")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .deskTarget("choice-\(title)-\(index)", perform: choose)
    }
}

private struct DeskChoiceKey: View {
    let title: String
    let selected: Bool

    var body: some View {
        let fill: Color = selected ? Color.cyan.opacity(0.34) : Color.white.opacity(0.08)
        let edge: Color = selected ? Color.cyan.opacity(0.85) : Color.white.opacity(0.14)
        Text(title)
            .font(Desk.font(.callout, selected ? .semibold : .regular)).lineLimit(1).fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, Desk.pt(13)).padding(.vertical, Desk.pt(8))
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(edge, lineWidth: 1).allowsHitTesting(false))
            .contentShape(Capsule())
    }
}
#endif

/// A setting that is on or off.
struct DeskToggle: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        #if os(tvOS) || os(macOS)
        let shape = RoundedRectangle(cornerRadius: Desk.pt(14), style: .continuous)
        Button { isOn.toggle() } label: {
            HStack(spacing: Desk.pt(12)) {
                Text(title).font(Desk.font(.body)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(isOn ? "Oui" : "Non").font(Desk.font(.callout, .semibold))
                    .frame(minWidth: Desk.pt(44))
                    .padding(.horizontal, Desk.pt(10)).padding(.vertical, Desk.pt(5))
                    .background(isOn ? Color.cyan.opacity(0.36) : Color.white.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(isOn ? Color.cyan.opacity(0.85) : Color.white.opacity(0.16), lineWidth: 1))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Desk.pt(14)).padding(.vertical, Desk.pt(10))
            .background(.white.opacity(0.06), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(DeskFocusStyle(radius: Desk.pt(14)))
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(title).accessibilityValue(isOn ? "Activé" : "Désactivé")
        .deskTarget("toggle-\(title)") { isOn.toggle() }
        #else
        Toggle(title, isOn: $isOn)
        #endif
    }
}

// MARK: - The keyboard of a Mac in the settings
//
// A television moves its focus from control to control by itself. A Mac has
// no such engine for the arrows: in the settings they move a selection kept
// here, from where each control says it stands, and OK does what a click
// does. The rest of the desk keeps its own selection, in the screen.

/// The controls of the settings that the keyboard of a Mac reaches, and the
/// one it is on.
@Observable final class DeskKeys {
    /// The space in which the controls say where they stand.
    static let space = "desk-keys"
    /// Rows of the column, named by the page they show.
    static let pagePrefix = "settings-page-"

    /// The control under the keyboard; none while the keyboard is in the dock.
    var focus: String?
    /// The row of the column for the page shown.
    @ObservationIgnored var pageID: String?
    /// The keyboard enters the column as soon as the settings show it.
    @ObservationIgnored var entering = false
    /// Brings a control of the content into view.
    @ObservationIgnored var scroll: ((String) -> Void)?
    @ObservationIgnored private var frames: [String: CGRect] = [:]
    @ObservationIgnored private var actions: [String: () -> Void] = [:]
    @ObservationIgnored private var followers: Set<String> = []
    /// Where the control under the keyboard stood, should it leave the screen.
    @ObservationIgnored private var lastFrame: CGRect?

    var onPages: Bool { focus.map(isPage) ?? false }

    func register(_ id: String, follows: Bool, action: @escaping () -> Void) {
        actions[id] = action
        if follows { followers.insert(id) }
    }

    func update(_ frames: [String: CGRect]) {
        self.frames = frames
        if let focus, let frame = frames[focus] { lastFrame = frame }
    }

    /// The column, on the page shown.
    func enterPages() {
        if let id = pageID.flatMap({ frames[$0] == nil ? nil : $0 }) ?? pageIDs.first { place(id, acting: false) }
    }
    /// The first control of the page, as it is read.
    @discardableResult func enterContent() -> Bool {
        guard let first = firstContent else { return false }
        place(first)
        return true
    }
    func leave() { focus = nil }

    /// Puts the keyboard on a control; a row of the column shows its page.
    func place(_ id: String, acting: Bool = true) {
        focus = id
        lastFrame = frames[id] ?? lastFrame
        scroll?(id)
        if acting, followers.contains(id) { actions[id]?() }
    }

    /// What OK does on the control under the keyboard.
    @discardableResult func activate() -> Bool {
        guard let focus, frames[focus] != nil, let action = actions[focus] else { return false }
        action()
        return true
    }

    /// The control that an arrow reaches from the one under the keyboard,
    /// or nil at an edge of the settings. Left from the content returns to
    /// the page in use; Right from the column enters the page at its start.
    func neighbour(_ action: RemoteAction) -> String? {
        guard let focus else { return nil }
        if isPage(focus) {
            let pages = pageIDs
            switch action {
            case .up, .down:
                guard let index = pages.firstIndex(of: focus) else { return pages.first }
                let next = index + (action == .down ? 1 : -1)
                return pages.indices.contains(next) ? pages[next] : nil
            case .right: return firstContent
            default: return nil
            }
        }
        guard let from = frames[focus] ?? lastFrame else { return firstContent }
        let others = frames.filter { !isPage($0.key) && $0.key != focus }
        if let next = Self.nearest(from: from, action, among: others) { return next }
        return action == .left ? (pageID.flatMap { frames[$0] == nil ? nil : $0 } ?? pageIDs.first) : nil
    }

    private func isPage(_ id: String) -> Bool { id.hasPrefix(Self.pagePrefix) }
    private var pageIDs: [String] {
        frames.filter { isPage($0.key) }.sorted { $0.value.minY < $1.value.minY }.map(\.key)
    }
    private var firstContent: String? {
        frames.filter { !isPage($0.key) }.min { left, right in
            abs(left.value.minY - right.value.minY) > 2 ? left.value.minY < right.value.minY : left.value.minX < right.value.minX
        }?.key
    }

    /// Up and Down reach the nearest line that way, and on it the control
    /// most in line, the left edges deciding between those that are; Left
    /// and Right stay on the line of the control.
    static func nearest(from: CGRect, _ action: RemoteAction, among candidates: [String: CGRect]) -> String? {
        func across(_ frame: CGRect) -> CGFloat { max(0, frame.minX - from.maxX, from.minX - frame.maxX) }
        switch action {
        case .down, .up:
            let down = action == .down
            let beyond = candidates.filter { down ? $0.value.minY >= from.midY && $0.value.midY > from.midY + 1
                                                  : $0.value.maxY <= from.midY && $0.value.midY < from.midY - 1 }
            guard let edge = down ? beyond.values.map(\.minY).min() : beyond.values.map(\.maxY).max() else { return nil }
            let line = beyond.filter { down ? $0.value.minY <= edge + 6 : $0.value.maxY >= edge - 6 }
            return line.min { left, right in
                let a = across(left.value), b = across(right.value)
                return a != b ? a < b : abs(left.value.minX - from.minX) < abs(right.value.minX - from.minX)
            }?.key
        case .left, .right:
            let right = action == .right
            let beside = candidates.filter {
                $0.value.minY < from.maxY - 1 && $0.value.maxY > from.minY + 1
                    && (right ? $0.value.midX > from.midX + 1 : $0.value.midX < from.midX - 1)
            }
            return beside.min { left, other in
                let a = right ? left.value.minX - from.maxX : from.minX - left.value.maxX
                let b = right ? other.value.minX - from.maxX : from.minX - other.value.maxX
                return a != b ? a < b : abs(left.value.midY - from.midY) < abs(other.value.midY - from.midY)
            }?.key
        default:
            return nil
        }
    }
}

/// Where the controls of the settings stand, for the keyboard of a Mac.
struct DeskTargetFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct DeskTarget: ViewModifier {
    let id: String
    let follows: Bool
    let action: () -> Void
    #if os(macOS)
    @Environment(DeskKeys.self) private var keys: DeskKeys?
    /// A control that cannot be used is passed over, as on a television.
    @Environment(\.isEnabled) private var isEnabled
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        if let keys, isEnabled {
            let _ = keys.register(id, follows: follows, action: action)
            content
                .environment(\.deskTargeted, keys.focus == id)
                .id(id)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: DeskTargetFrames.self, value: [id: geometry.frame(in: .named(DeskKeys.space))])
                    }
                }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// A control of the settings that the keyboard of a Mac reaches: OK on it
    /// does `action`, as a click does; `follows` acts as soon as the keyboard
    /// arrives, as a row of the column shows its page. Outside the settings
    /// of a Mac nothing changes: a television has its own focus.
    func deskTarget(_ id: String, follows: Bool = false, perform action: @escaping () -> Void) -> some View {
        modifier(DeskTarget(id: id, follows: follows, action: action))
    }
}

extension View {
    /// An action of the settings: a key of the desk on a television and on a
    /// Mac, the bordered button of the system on a phone.
    @ViewBuilder func deskKey(prominent: Bool = false) -> some View {
        #if os(tvOS) || os(macOS)
        buttonStyle(DeskKeyStyle(prominent: prominent))
        #else
        if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        #endif
    }
}
