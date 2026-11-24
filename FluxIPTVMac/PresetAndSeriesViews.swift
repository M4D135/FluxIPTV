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

struct SeriesEpisodesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: IPTVLibrary
    let series: IPTVItem
    let play: (IPTVItem) -> Void
    @State private var seasons: [IPTVSeason] = []
    @State private var selectedSeason: Int?
    @State private var loading = true
    @State private var failed = false
    @State private var reload = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                AsyncImage(url: series.logoURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "film.stack").font(.largeTitle).foregroundStyle(.secondary)
                }
                .frame(width: 74, height: 95)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) {
                    Text(series.name).font(.title2.weight(.semibold))
                    Text(series.group).foregroundStyle(.secondary)
                    if !loading && !failed {
                        Text("\(seasons.count) saisons · \(seasons.reduce(0) { $0 + $1.episodes.count }) épisodes")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Fermer") { dismiss() }.fluxShortcut(cancel: true)
            }
            Divider()
            if loading {
                Spacer(); ProgressView("Chargement des épisodes…").frame(maxWidth: .infinity); Spacer()
            } else if failed {
                ContentUnavailableView("Impossible de charger les épisodes", systemImage: "wifi.exclamationmark",
                    description: Text("Le fournisseur ne répond pas ou son API séries n’est pas compatible."))
                Button("Réessayer") { reload = UUID() }.frame(maxWidth: .infinity)
            } else if seasons.isEmpty {
                ContentUnavailableView("Aucun épisode disponible", systemImage: "film.stack")
            } else {
                Picker("Saison", selection: $selectedSeason) {
                    ForEach(seasons) { season in
                        Text(season.number == 0 ? "Épisodes spéciaux" : "Saison \(season.number)").tag(Optional(season.number))
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(seasons.first(where: { $0.number == selectedSeason })?.episodes ?? []) { episode in
                            Button {
                                play(episode)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "play.circle.fill").foregroundStyle(.cyan)
                                    Text(episode.name).lineLimit(2)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .padding(24)
        .fluxSheetSize(width: 850, height: 650)
        .task(id: reload) { await loadEpisodes() }
    }

    @MainActor private func loadEpisodes() async {
        loading = true
        failed = false
        do {
            let result = try await library.seasons(for: series)
            try Task.checkCancellation()
            seasons = result
            selectedSeason = seasons.first?.number
            loading = false
        } catch is CancellationError {
            // A dismissed sheet or a changed source must not publish a stale error.
        } catch {
            if !Task.isCancelled { failed = true; loading = false }
        }
    }
}
