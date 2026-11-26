import SwiftUI

// MARK: - Controls of the settings
//
// A television draws the pickers and the switches of the system at its own
// size, cuts their values when they are many and leaves their names out. The
// desk draws them itself there: keys that are read from a sofa, never cut,
// with a ring under the remote. Elsewhere the controls of the system remain.

/// One setting among a few values.
struct DeskChoice<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        #if os(tvOS)
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

#if os(tvOS)
private extension DeskChoice {
    func key(_ index: Int) -> some View {
        let option = options[index]
        let selected = option.value == selection
        return Button { selection = option.value } label: { DeskChoiceKey(title: option.title, selected: selected) }
            .buttonStyle(DeskFocusStyle(radius: Desk.pt(22)))
            .accessibilityLabel(title + " : " + option.title)
            .accessibilityValue(selected ? "Sélectionné" : "")
            .accessibilityAddTraits(selected ? .isSelected : [])
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
        #if os(tvOS)
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
        #else
        Toggle(title, isOn: $isOn)
        #endif
    }
}

extension View {
    /// An action of the settings: a key of the desk on a television, the
    /// bordered button of the system elsewhere.
    @ViewBuilder func deskKey(prominent: Bool = false) -> some View {
        #if os(tvOS)
        buttonStyle(DeskKeyStyle(prominent: prominent))
        #else
        if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        #endif
    }
}
