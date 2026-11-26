import SwiftUI

/// A local draft: dismissing or cancelling never changes saved memberships.
struct FavoriteAssignmentSheet: View {
    let item: IPTVItem
    let open: () -> Void
    let saved: () -> Void
    /// Set when the panel is drawn inside the window. Dismissing a view that
    /// no sheet presents would close the window itself.
    var inlineClose: (() -> Void)? = nil
    @EnvironmentObject private var library: IPTVLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []
    @State private var creating = false
    @State private var newName = ""
    @State private var validationError: String?
    @State private var initialized = false
    @FocusState private var nameFocused: Bool
    #if os(tvOS)
    /// Control under the remote: each one draws its own highlight.
    @FocusState private var focus: String?
    #endif

    private var lists: [FavoritePreset] { library.presets.lists(for: item.kind) }

    var body: some View {
        #if os(tvOS)
        television
        #else
        standard
        #endif
    }

    private func toggle(_ preset: FavoritePreset) {
        if !selectedIDs.insert(preset.id).inserted { selectedIDs.remove(preset.id) }
        validationError = nil
    }

    private func initialize() {
        guard !initialized else { return }
        selectedIDs = Set(lists.filter { $0.itemIDs.contains(item.id) }.map(\.id))
        initialized = true
    }

    #if os(tvOS)
    // MARK: Television: the sizes of the desk, a highlight on every control

    private var television: some View {
        VStack(alignment: .leading, spacing: Desk.pt(12)) {
            VStack(alignment: .leading, spacing: Desk.pt(4)) {
                Text("Favoris et listes").font(Desk.font(.title2, .bold))
                Text(item.name).font(Desk.font(.headline)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                Text("Choisissez vos listes, puis enregistrez.")
                    .font(Desk.font(.callout)).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Desk.pt(7)) {
                    ForEach(Array(lists.enumerated()), id: \.element.id) { index, preset in
                        let chosen = selectedIDs.contains(preset.id)
                        row("list-\(index)", symbol: chosen ? "checkmark.circle.fill" : "circle",
                            tint: chosen ? .cyan : .secondary, title: preset.name,
                            mark: preset.isDefault ? "star.fill" : nil) { toggle(preset) }
                            .accessibilityValue(chosen ? "Sélectionnée" : "Non sélectionnée")
                    }
                    row("create", symbol: creating ? "minus.circle" : "plus.circle", tint: .secondary,
                        title: creating ? "Annuler la nouvelle liste" : "Créer une nouvelle liste", mark: nil) {
                        creating.toggle(); validationError = nil
                    }
                    if creating {
                        HStack(spacing: Desk.pt(10)) {
                            Image(systemName: "pencil").font(Desk.font(.callout)).foregroundStyle(.secondary)
                            TextField("Nom de la nouvelle liste", text: $newName,
                                      prompt: Text("Nom de la nouvelle liste")
                                        .foregroundStyle(nameFocused ? Color.black.opacity(0.55) : Color.white.opacity(0.55)))
                                .textFieldStyle(.plain).font(Desk.font(.body)).focused($nameFocused)
                        }
                        .padding(.leading, Desk.pt(14)).padding(.trailing, Desk.pt(4)).padding(.vertical, Desk.pt(4))
                        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: Desk.pt(14), style: .continuous))
                        .accessibilityIdentifier("favorite-name")
                        Text("Le contenu sera également ajouté à cette nouvelle liste.")
                            .font(Desk.font(.caption)).foregroundStyle(.secondary)
                    }
                }
                // Room for the highlight of the first and the last row.
                .padding(.horizontal, Desk.pt(6)).padding(.vertical, Desk.pt(6))
            }
            .focusSection()
            if let validationError {
                Text(validationError).font(Desk.font(.callout)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(.white.opacity(0.18))
            HStack(spacing: Desk.pt(10)) {
                pill("open", title: item.isSeriesCollection ? "Voir les saisons" : "Lire") { finish(); open() }
                Spacer(minLength: Desk.pt(8))
                pill("cancel", title: "Annuler") { finish() }
                pill("save", title: "Enregistrer", prominent: true, action: commit)
                    .disabled(creating && newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .focusSection()
        }
        .padding(Desk.pt(22))
        .frame(width: Desk.pt(520))
        .frame(maxHeight: Desk.pt(500))
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white)
        .onAppear {
            initialize()
            // The remote starts on the first list, where the choice is made.
            Task { @MainActor in await Task.yield(); focus = lists.isEmpty ? "create" : "list-0" }
        }
    }

    private func row(_ id: String, symbol: String, tint: Color, title: String, mark: String?,
                     action: @escaping () -> Void) -> some View {
        let focused = focus == id
        let shape = RoundedRectangle(cornerRadius: Desk.pt(14), style: .continuous)
        return Button(action: action) {
            HStack(spacing: Desk.pt(12)) {
                Image(systemName: symbol).font(Desk.font(.title3)).foregroundStyle(tint)
                Text(title).font(Desk.font(.body, .medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if let mark { Image(systemName: mark).font(Desk.font(.callout)).foregroundStyle(.yellow) }
            }
            .padding(.horizontal, Desk.pt(14)).padding(.vertical, Desk.pt(11))
            .background(.white.opacity(focused ? 0.18 : 0.07), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(focused ? 0.9 : 0.12), lineWidth: focused ? 3 : 1).allowsHitTesting(false))
            .contentShape(shape)
        }
        .buttonStyle(FluxBareButtonStyle())
        .focused($focus, equals: id).focusEffectDisabled()
        .accessibilityIdentifier("favorite-\(id)")
        #if FLUX_CATALOG_UI_TESTING
        .background(TVCatalogControlFrameProbe(identifier: "favorite-\(id)").allowsHitTesting(false))
        #endif
    }

    private func pill(_ id: String, title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        FavoritePill(title: title, prominent: prominent, focused: focus == id, action: action)
            .focused($focus, equals: id).focusEffectDisabled()
            .accessibilityIdentifier("favorite-\(id)")
    }
    #endif

    private var standard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Favoris et listes").font(.title2.bold())
            Text(item.name).font(.headline).lineLimit(3)
            Text("Choisissez vos listes, puis confirmez l’enregistrement.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(lists) { preset in
                        Button { toggle(preset) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIDs.contains(preset.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(preset.id) ? Color.cyan : Color.secondary)
                                Text(preset.name).frame(maxWidth: .infinity, alignment: .leading)
                                if preset.isDefault { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                            }.padding(12)
                        }.buttonStyle(.bordered)
                            .accessibilityValue(selectedIDs.contains(preset.id) ? "Sélectionnée" : "Non sélectionnée")
                    }
                    Button {
                        creating.toggle(); validationError = nil
                        nameFocused = creating
                    } label: {
                        Label(creating ? "Annuler la nouvelle liste" : "Créer une nouvelle liste", systemImage: creating ? "minus.circle" : "plus.circle")
                    }.buttonStyle(.bordered)
                    if creating {
                        TextField("Nom de la nouvelle liste", text: $newName)
                            .fluxFieldStyle().focused($nameFocused)
                        Text("Le contenu sera également ajouté à cette nouvelle liste.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }
            if let validationError { Text(validationError).font(.callout).foregroundStyle(.orange) }
            Divider()
            HStack(spacing: 12) {
                Button(item.isSeriesCollection ? "Voir les saisons" : "Lire") {
                    finish(); open()
                }.buttonStyle(.bordered)
                Spacer(minLength: 8)
                Button("Annuler", role: .cancel) { finish() }.fluxShortcut(cancel: true)
                Button("Enregistrer", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(creating && newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).fluxSheetSize(width: inlineClose == nil ? 620 : 540, height: inlineClose == nil ? 570 : 540)
            .onAppear { initialize() }
    }

    private func commit() {
        guard library.assignFavorites(item, to: selectedIDs, creating: creating ? newName : nil) else {
            validationError = "Choisissez un nom unique de 1 à 60 caractères. Si une liste a changé, fermez puis rouvrez ce panneau."
            return
        }
        saved(); finish()
    }

    private func finish() {
        if let inlineClose { inlineClose() } else { dismiss() }
    }
}

#if os(tvOS)
/// Action at the foot of the panel, dimmed while it cannot be used.
private struct FavoritePill: View {
    let title: String
    let prominent: Bool
    let focused: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Desk.pt(15), style: .continuous)
        Button(action: action) {
            Text(title).font(Desk.font(.body, .semibold)).lineLimit(1).fixedSize()
                .padding(.horizontal, Desk.pt(20)).padding(.vertical, Desk.pt(11))
                .background(prominent ? Color.cyan.opacity(focused ? 0.45 : 0.30) : Color.white.opacity(focused ? 0.18 : 0.07), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(focused ? 0.9 : 0.14), lineWidth: focused ? 3 : 1).allowsHitTesting(false))
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(shape)
        }
        .buttonStyle(FluxBareButtonStyle())
    }
}
#endif
