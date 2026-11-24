import SwiftUI

/// A local draft: dismissing or cancelling never changes saved memberships.
struct FavoriteAssignmentSheet: View {
    let item: IPTVItem
    let open: () -> Void
    let saved: () -> Void
    @EnvironmentObject private var library: IPTVLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []
    @State private var creating = false
    @State private var newName = ""
    @State private var validationError: String?
    @State private var initialized = false
    @FocusState private var nameFocused: Bool

    private var lists: [FavoritePreset] { library.presets.lists(for: item.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Favoris et listes").font(.title2.bold())
            Text(item.name).font(.headline).lineLimit(3)
            Text("Choisissez vos listes, puis confirmez l’enregistrement.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(lists) { preset in
                        Button {
                            if !selectedIDs.insert(preset.id).inserted { selectedIDs.remove(preset.id) }
                            validationError = nil
                        } label: {
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
                Button(item.isSeriesCollection ? "Ouvrir le coffret" : "Lire") {
                    dismiss(); open()
                }.buttonStyle(.bordered)
                Spacer(minLength: 8)
                Button("Annuler", role: .cancel) { dismiss() }.fluxShortcut(cancel: true)
                Button("Enregistrer", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(creating && newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).fluxSheetSize(width: 620, height: 570)
            .onAppear {
                guard !initialized else { return }
                selectedIDs = Set(lists.filter { $0.itemIDs.contains(item.id) }.map(\.id))
                initialized = true
            }
    }

    private func commit() {
        guard library.assignFavorites(item, to: selectedIDs, creating: creating ? newName : nil) else {
            validationError = "Choisissez un nom unique de 1 à 60 caractères. Si une liste a changé, fermez puis rouvrez ce panneau."
            return
        }
        saved(); dismiss()
    }
}
