import SwiftUI

/// The lists of a title and its place in the dock. A local draft:
/// dismissing or cancelling never changes what was saved.
struct FavoriteAssignmentSheet: View {
    let item: IPTVItem
    let open: () -> Void
    let saved: () -> Void
    /// Set when the panel is drawn inside the window. Dismissing a view that
    /// no sheet presents would close the window itself.
    var inlineClose: (() -> Void)? = nil
    /// What of this title the dock can keep: the title itself and, from the
    /// screen of a series, its season or one of its episodes. Empty where
    /// there is no dock.
    var dockChoices: [DockShortcut] = []
    /// The choice shown first: the one whose icon was asked about.
    var dockPreferred: String? = nil
    @EnvironmentObject private var library: IPTVLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []
    @State private var creating = false
    @State private var newName = ""
    @State private var validationError: String?
    @State private var initialized = false
    @FocusState private var nameFocused: Bool
    #if !os(iOS)
    /// Control under the remote or the keys: each one draws its own highlight.
    @FocusState private var focus: String?
    @FocusState private var sectionFocused: Bool
    @State private var dockChoice = 0
    /// Sections chosen for each thing the dock can keep, by its identifier.
    @State private var dockSelected: [String: Set<String>] = [:]
    @State private var creatingSection = false
    @State private var newSection = ""
    /// What is being created is a folder of the dock, not a section; and
    /// the folder it is made in, nil for the bar itself.
    @State private var creatingFolder = false
    @State private var folderParent: String?
    #endif
    #if os(macOS)
    @State private var hovered: String?
    /// The ring of the keys shows once a key has been used.
    @State private var keyboard = false
    #endif

    private var lists: [FavoritePreset] { library.presets.lists(for: item.kind) }

    var body: some View {
        #if os(iOS)
        standard
        #else
        desk
        #endif
    }

    private func toggle(_ preset: FavoritePreset) {
        if !selectedIDs.insert(preset.id).inserted { selectedIDs.remove(preset.id) }
        validationError = nil
    }

    private func initialize() {
        guard !initialized else { return }
        selectedIDs = Set(lists.filter { $0.itemIDs.contains(item.id) }.map(\.id))
        #if !os(iOS)
        for choice in dockChoices { dockSelected[choice.id] = library.dockShelf.sections(holding: choice.id) }
        dockChoice = dockChoices.firstIndex { $0.id == dockPreferred } ?? 0
        #endif
        initialized = true
    }

    #if !os(iOS)
    // MARK: Desk: the same panel on a television and on a Mac

    /// The sections of the bar, then its folders, each followed by those
    /// it holds.
    private var sections: [DockSection] { library.dockShelf.tree.map(\.section) }
    private var choice: DockShortcut? { dockChoices.indices.contains(dockChoice) ? dockChoices[dockChoice] : nil }
    /// A folder is named with those above it: « Films › Action ».
    private func sectionTitle(_ section: DockSection) -> String {
        section.isFolder ? library.dockShelf.path(to: section.id).map(\.name).joined(separator: " › ") : section.name
    }
    private func sectionMark(_ section: DockSection) -> String? {
        section.isDefault ? "dock.rectangle" : section.isFolder ? (section.symbol ?? "folder.fill") : nil
    }
    /// Where a new folder may be made: the bar, or a folder that is not too deep.
    private var folderParents: [String?] {
        [nil] + library.dockShelf.tree.filter { $0.section.isFolder && $0.depth + 1 < DockShelf.folderDepth }.map { Optional($0.section.id) }
    }
    private var folderParentTitle: String {
        folderParent.flatMap { library.dockShelf.section(id: $0) }.map(sectionTitle) ?? "Le dock"
    }
    private func cycleFolderParent() {
        let options = folderParents
        let index = options.firstIndex(of: folderParent) ?? 0
        folderParent = options[(index + 1) % options.count]
        validationError = nil
    }
    private func toggleCreation(folder: Bool) {
        if creatingSection && creatingFolder == folder { creatingSection = false }
        else { creatingSection = true; creatingFolder = folder }
        validationError = nil
        #if os(macOS)
        sectionFocused = creatingSection
        #endif
    }

    /// The controls, row by row, for the arrows of a keyboard. A remote
    /// finds them by where they stand.
    private var grid: [[String]] {
        var rows = lists.indices.map { ["list-\($0)"] } + [["create"]]
        if !dockChoices.isEmpty {
            if dockChoices.count > 1 { rows.append(dockChoices.indices.map { "dock-choice-\($0)" }) }
            rows += sections.indices.map { ["dock-\($0)"] } + [["dock-create"], ["dock-create-folder"]]
            if creatingSection && creatingFolder && folderParents.count > 1 { rows.append(["dock-parent"]) }
        }
        return rows + [["open", "cancel", "save"]]
    }

    private var desk: some View {
        VStack(alignment: .leading, spacing: Desk.pt(12)) {
            VStack(alignment: .leading, spacing: Desk.pt(4)) {
                Text(dockChoices.isEmpty ? "Favoris et listes" : "Favoris, listes et dock").font(Desk.font(.title2, .bold))
                Text(item.name).font(Desk.font(.headline)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                Text(dockChoices.isEmpty ? "Choisissez vos listes, puis enregistrez."
                     : "Choisissez vos listes et sa place dans le dock, puis enregistrez.")
                    .font(Desk.font(.callout)).foregroundStyle(.secondary)
            }
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: Desk.pt(7)) {
                        if !dockChoices.isEmpty { heading("LISTES") }
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
                            #if os(macOS)
                            nameFocused = creating
                            #endif
                        }
                        if creating {
                            field("Nom de la nouvelle liste", text: $newName, focused: $nameFocused, identifier: "favorite-name")
                            Text("Le contenu sera également ajouté à cette nouvelle liste.")
                                .font(Desk.font(.caption)).foregroundStyle(.secondary)
                        }
                        if !dockChoices.isEmpty { dockRows }
                    }
                    // Room for the highlight of the first and the last row.
                    .padding(.horizontal, Desk.pt(6)).padding(.vertical, Desk.pt(6))
                }
                #if os(tvOS)
                .focusSection()
                #else
                .onChange(of: focus) { _, id in
                    if let id, keyboard { reader.scrollTo(id, anchor: .center) }
                }
                #endif
            }
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
                    .disabled(unnamed)
            }
            #if os(tvOS)
            .focusSection()
            // The foot is entered on Enregistrer, which ends the panel:
            // the lists and the sections above make a long column, and
            // the nearest key under it is not the one that is wanted.
            .defaultFocus($focus, "save", priority: .userInitiated)
            #endif
        }
        .padding(Desk.pt(22))
        .frame(width: Desk.pt(dockChoices.isEmpty ? 520 : 560))
        .frame(maxHeight: Desk.pt(dockChoices.isEmpty ? 500 : 640))
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white)
        #if os(macOS)
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .space, .escape]) { press in key(press) }
        #endif
        .onAppear {
            initialize()
            // The remote starts on the first list, where the choice is made.
            Task { @MainActor in await Task.yield(); focus = lists.isEmpty ? "create" : "list-0" }
        }
    }

    /// A new list or a new section waits for its name.
    private var unnamed: Bool {
        (creating && newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || (creatingSection && newSection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// The sections of the dock that keep this title, as the lists above
    /// keep it: chosen here, created and named here.
    @ViewBuilder private var dockRows: some View {
        heading("DOCK").padding(.top, Desk.pt(10))
        if dockChoices.count > 1 {
            // A series, one of its seasons or one of its episodes.
            HStack(spacing: Desk.pt(8)) {
                ForEach(Array(dockChoices.enumerated()), id: \.element.id) { index, option in
                    chip("dock-choice-\(index)", title: chipTitle(option), chosen: index == dockChoice,
                         kept: !(dockSelected[option.id] ?? []).isEmpty) {
                        dockChoice = index; validationError = nil
                    }
                }
            }
        }
        if let choice {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                let chosen = dockSelected[choice.id]?.contains(section.id) == true
                row("dock-\(index)", symbol: chosen ? "checkmark.circle.fill" : "circle",
                    tint: chosen ? .cyan : .secondary, title: sectionTitle(section),
                    mark: sectionMark(section)) {
                    var set = dockSelected[choice.id] ?? []
                    if !set.insert(section.id).inserted { set.remove(section.id) }
                    dockSelected[choice.id] = set
                    validationError = nil
                }
                .accessibilityValue(chosen ? "Sélectionnée" : "Non sélectionnée")
            }
            let section = creatingSection && !creatingFolder, folder = creatingSection && creatingFolder
            row("dock-create", symbol: section ? "minus.circle" : "plus.circle", tint: .secondary,
                title: section ? "Annuler la nouvelle section" : "Créer une section du dock", mark: nil) {
                toggleCreation(folder: false)
            }
            row("dock-create-folder", symbol: folder ? "minus.circle" : "folder.badge.plus", tint: .secondary,
                title: folder ? "Annuler le nouveau dossier" : "Créer un dossier du dock", mark: nil) {
                toggleCreation(folder: true)
            }
            if creatingSection {
                field(creatingFolder ? "Nom du dossier" : "Nom de la section", text: $newSection, focused: $sectionFocused,
                      identifier: "favorite-section-name")
            }
            if folder && folderParents.count > 1 {
                // In the bar, or in a folder: OK goes from one to the next.
                row("dock-parent", symbol: "arrow.turn.down.right", tint: .secondary,
                    title: "Dans : \(folderParentTitle)", mark: folderParent == nil ? "dock.rectangle" : "folder.fill") {
                    cycleFolderParent()
                }
            }
            Text(folder ? "« \(choice.title) » ira dans ce dossier : une icône du dock, qui s’ouvre en éventail."
                 : section ? "« \(choice.title) » ira dans cette section, à part dans le dock."
                 : "Une section se tient à part dans le dock, entre deux séparateurs ; un dossier y est une seule icône, qui s’ouvre en éventail.")
                .font(Desk.font(.caption)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chipTitle(_ option: DockShortcut) -> String {
        switch option.target {
        case .channel: "La chaîne"
        case .film: "Le film"
        case .series: "La série"
        case .season: option.season.map { "Saison \($0)" } ?? "La saison"
        case .episode: option.badge.map { $0.replacingOccurrences(of: "·", with: " ") } ?? "L’épisode"
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(Desk.font(.caption2, .semibold)).tracking(1.5).foregroundStyle(.secondary)
            .padding(.horizontal, Desk.pt(4))
    }

    private func lit(_ id: String) -> Bool {
        #if os(macOS)
        (keyboard && focus == id) || hovered == id
        #else
        focus == id
        #endif
    }

    private func field(_ prompt: String, text: Binding<String>, focused: FocusState<Bool>.Binding, identifier: String) -> some View {
        HStack(spacing: Desk.pt(10)) {
            Image(systemName: "pencil").font(Desk.font(.callout)).foregroundStyle(.secondary)
            #if os(tvOS)
            // Under the remote the system draws the field light: its prompt
            // then needs a dark ink to stay readable.
            TextField(prompt, text: text,
                      prompt: Text(prompt).foregroundStyle(focused.wrappedValue ? Color.black.opacity(0.55) : Color.white.opacity(0.55)))
                .textFieldStyle(.plain).font(Desk.font(.body)).focused(focused)
            #else
            TextField(prompt, text: text, prompt: Text(prompt).foregroundStyle(Color.white.opacity(0.55)))
                .textFieldStyle(.plain).font(Desk.font(.body)).focused(focused)
                .onSubmit { focus = "save" }
                .padding(.vertical, Desk.pt(8))
            #endif
        }
        .padding(.leading, Desk.pt(14)).padding(.trailing, Desk.pt(4)).padding(.vertical, Desk.pt(4))
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: Desk.pt(14), style: .continuous))
        .accessibilityIdentifier(identifier)
    }

    private func row(_ id: String, symbol: String, tint: Color, title: String, mark: String?,
                     action: @escaping () -> Void) -> some View {
        let focused = lit(id)
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
        .modifier(PanelFocus(focus: $focus, id: id))
        #if os(macOS)
        .onHover { inside in hovered = inside ? id : (hovered == id ? nil : hovered) }
        #endif
        .id(id)
        .accessibilityIdentifier("favorite-\(id)")
        #if os(tvOS) && FLUX_CATALOG_UI_TESTING
        .background(TVCatalogControlFrameProbe(identifier: "favorite-\(id)").allowsHitTesting(false))
        #endif
    }

    /// One of the things the dock can keep of a series. A dot marks the
    /// ones that a section already keeps.
    private func chip(_ id: String, title: String, chosen: Bool, kept: Bool, action: @escaping () -> Void) -> some View {
        let focused = lit(id)
        let shape = Capsule()
        return Button(action: action) {
            HStack(spacing: Desk.pt(6)) {
                if kept {
                    Circle().fill(chosen ? Color(red: 0, green: 0.48, blue: 0.62) : Color.cyan)
                        .frame(width: Desk.pt(8), height: Desk.pt(8))
                }
                Text(title).font(Desk.font(.callout, chosen ? .bold : .medium)).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, Desk.pt(16)).padding(.vertical, Desk.pt(9))
            .foregroundStyle(chosen ? .black : .white)
            .background(chosen ? AnyShapeStyle(Color.white.opacity(0.92)) : AnyShapeStyle(Color.white.opacity(focused ? 0.18 : 0.07)), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(focused ? 0.9 : 0.14), lineWidth: focused ? 3 : 1).padding(focused ? -3 : 0).allowsHitTesting(false))
            .contentShape(shape)
        }
        .buttonStyle(FluxBareButtonStyle())
        .modifier(PanelFocus(focus: $focus, id: id))
        #if os(macOS)
        .onHover { inside in hovered = inside ? id : (hovered == id ? nil : hovered) }
        #endif
        .id(id)
        .accessibilityIdentifier("favorite-\(id)")
        .accessibilityValue(chosen ? "Sélectionné" : "")
        #if os(tvOS) && FLUX_CATALOG_UI_TESTING
        .background(TVCatalogControlFrameProbe(identifier: "favorite-\(id)").allowsHitTesting(false))
        #endif
    }

    private func pill(_ id: String, title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        FavoritePill(title: title, prominent: prominent, focused: lit(id), action: action)
            .modifier(PanelFocus(focus: $focus, id: id))
            #if os(macOS)
            .onHover { inside in hovered = inside ? id : (hovered == id ? nil : hovered) }
            #endif
            .accessibilityIdentifier("favorite-\(id)")
    }

    #if os(macOS)
    /// The arrows walk the panel as the remote of a television does; Return
    /// and Space press what they are on. A field being typed keeps its keys.
    private func key(_ press: KeyPress) -> KeyPress.Result {
        if nameFocused || sectionFocused {
            guard press.key == .escape else { return .ignored }
            if nameFocused { creating = false; focus = "create" }
            else { creatingSection = false; focus = creatingFolder ? "dock-create-folder" : "dock-create" }
            return .handled
        }
        if press.key == .escape { finish(); return .handled }
        let rows = grid
        guard let current = focus, let r = rows.firstIndex(where: { $0.contains(current) }),
              let c = rows[r].firstIndex(of: current) else {
            keyboard = true; focus = rows.first?.first
            return .handled
        }
        switch press.key {
        case .upArrow, .downArrow:
            let target = max(0, min(rows.count - 1, r + (press.key == .upArrow ? -1 : 1)))
            // The foot is entered on Enregistrer, the end of the panel.
            if target != r { focus = target == rows.count - 1 ? "save" : rows[target][min(c, rows[target].count - 1)] }
        case .leftArrow: focus = rows[r][max(0, c - 1)]
        case .rightArrow: focus = rows[r][min(rows[r].count - 1, c + 1)]
        default:
            guard keyboard else { keyboard = true; return .handled }
            activate(current)
        }
        keyboard = true
        return .handled
    }

    /// What OK does on a control of the panel.
    private func activate(_ id: String) {
        func index(_ prefix: String) -> Int? { id.hasPrefix(prefix) ? Int(id.dropFirst(prefix.count)) : nil }
        if let i = index("list-"), lists.indices.contains(i) { toggle(lists[i]) }
        else if let i = index("dock-choice-"), dockChoices.indices.contains(i) { dockChoice = i; validationError = nil }
        else if let i = index("dock-"), sections.indices.contains(i), let choice {
            var set = dockSelected[choice.id] ?? []
            if !set.insert(sections[i].id).inserted { set.remove(sections[i].id) }
            dockSelected[choice.id] = set; validationError = nil
        }
        else if id == "create" { creating.toggle(); validationError = nil; nameFocused = creating }
        else if id == "dock-create" { toggleCreation(folder: false) }
        else if id == "dock-create-folder" { toggleCreation(folder: true) }
        else if id == "dock-parent" { cycleFolderParent() }
        else if id == "open" { finish(); open() }
        else if id == "cancel" { finish() }
        else if id == "save", !unnamed { commit() }
    }
    #endif
    #endif

    #if os(iOS)
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
    #endif

    private func commit() {
        let listName = creating ? newName : nil
        // The lists and the dock take the whole choice or nothing: both are
        // tried on a copy before either is written.
        var draft = library.presets
        guard draft.assign(item, to: selectedIDs, creating: listName) else {
            validationError = "Choisissez un nom unique de 1 à 60 caractères. Si une liste a changé, fermez puis rouvrez ce panneau."
            return
        }
        #if !os(iOS)
        var shelf = library.dockShelf
        var changes: [(DockShortcut, Set<String>, String?)] = []
        // A new folder is made in the bar, or in the folder chosen for it.
        let parent = creatingFolder ? folderParent : nil
        for (index, option) in dockChoices.enumerated() {
            let chosen = dockSelected[option.id] ?? []
            let sectionName = creatingSection && index == dockChoice ? newSection : nil
            guard shelf.assign(option, to: chosen, creating: sectionName, folded: creatingFolder, in: parent) else {
                validationError = "Choisissez un nom de 1 à 40 caractères, sans « / », que rien ne porte déjà au même endroit. Si le dock a changé, fermez puis rouvrez ce panneau."
                return
            }
            if sectionName != nil || chosen != library.dockShelf.sections(holding: option.id) { changes.append((option, chosen, sectionName)) }
        }
        #endif
        guard library.assignFavorites(item, to: selectedIDs, creating: listName) else { return }
        #if !os(iOS)
        for (option, chosen, sectionName) in changes {
            _ = library.assignDock(option, to: chosen, creating: sectionName, folded: creatingFolder, in: parent)
        }
        #endif
        saved(); finish()
    }

    private func finish() {
        if let inlineClose { inlineClose() } else { dismiss() }
    }
}

#if !os(iOS)
/// A control of the panel takes the remote of a television, and on a Mac
/// the keys that walk the panel.
private struct PanelFocus: ViewModifier {
    let focus: FocusState<String?>.Binding
    let id: String

    func body(content: Content) -> some View {
        #if os(tvOS)
        content.focused(focus, equals: id).focusEffectDisabled()
        #else
        content.focusable().focused(focus, equals: id).focusEffectDisabled()
        #endif
    }
}

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
