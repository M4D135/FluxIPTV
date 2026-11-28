import SwiftUI

struct PresetEditor: Identifiable {
    let id = UUID()
    let kind: IPTVMediaKind
    let existing: FavoritePreset?
    var initialItem: IPTVItem? = nil
}

struct PresetNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let editor: PresetEditor
    let save: (String) -> Bool
    @State private var name = ""
    @State private var invalidName = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(editor.existing == nil ? "Nouvelle liste" : "Renommer la liste")
                .font(.title2.weight(.semibold))
            Text(editor.kind.frenchTitle).foregroundStyle(.secondary)
            TextField("Nom de la liste", text: $name)
                .fluxFieldStyle()
                .focused($nameFocused)
                .onSubmit(commit)
            if invalidName {
                Text("Choisissez un nom unique de 1 à 60 caractères pour ce type de contenu.")
                    .foregroundStyle(.orange).font(.caption)
            }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.fluxShortcut(cancel: true)
                Button(editor.existing == nil ? "Créer" : "Enregistrer", action: commit)
                    .fluxShortcut()
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .fluxSheetSize(width: 450)
        .onAppear { name = editor.existing?.name ?? ""; nameFocused = true }
    }

    private func commit() {
        if save(name) { dismiss() } else { invalidName = true }
    }
}
