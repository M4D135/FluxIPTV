import SwiftUI
import AVKit

private enum UIColors {
    static let background = Color(red: 0.065, green: 0.080, blue: 0.115)
    static let sidebar = Color(red: 0.085, green: 0.103, blue: 0.143)
    static let list = Color(red: 0.095, green: 0.115, blue: 0.160)
    static let accent = Color(red: 0.21, green: 0.78, blue: 0.96)
    static let selected = Color(red: 0.18, green: 0.31, blue: 0.43)
}

struct ContentView: View {
    @EnvironmentObject private var library: IPTVLibrary
    @EnvironmentObject private var playback: PlaybackController
    @State private var addingSource = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 245)
                .background(UIColors.sidebar)
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            channelColumn
                .frame(width: 345)
                .background(UIColors.list)
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            playerColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(UIColors.background)
        }
        .frame(minWidth: 1020, minHeight: 620)
        .sheet(isPresented: $addingSource) {
            AddSourceSheet().environmentObject(library)
        }
        .alert("Flux IPTV", isPresented: Binding(
            get: { library.alertMessage != nil },
            set: { if !$0 { library.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { library.alertMessage = nil }
        } message: {
            Text(library.alertMessage ?? "")
        }
        .onChange(of: library.selectedSourceID) { _, _ in
            playback.stop()
        }
        .onChange(of: library.selectedItemID) { _, _ in
            guard let item = library.selectedItem else {
                playback.stop()
                return
            }
            do {
                let url = try library.playbackURL(for: item)
                playback.play(item, url: url)
            } catch {
                playback.stop()
                library.alertMessage = error.localizedDescription
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(UIColors.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("FLUX").font(.system(size: 22, weight: .bold, design: .rounded)).tracking(3)
                    Text("IPTV POUR MAC").font(.system(size: 9, weight: .semibold))
                        .tracking(2.2).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, 18)

            VStack(alignment: .leading, spacing: 8) {
                Text("BIBLIOTHÈQUE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5).foregroundStyle(.secondary)
                    .padding(.horizontal, 18)

                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(library.sources) { source in
                            Button {
                                Task { await library.selectSource(source.id) }
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: source.symbol)
                                        .frame(width: 20).foregroundStyle(UIColors.accent)
                                    Text(source.name).lineLimit(1)
                                    Spacer(minLength: 3)
                                    if library.selectedSourceID == source.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(UIColors.accent)
                                    }
                                }
                                .padding(.horizontal, 13).padding(.vertical, 11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(library.selectedSourceID == source.id
                                            ? UIColors.selected : .clear, in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Supprimer la source", role: .destructive) {
                                    if library.selectedSourceID == source.id { playback.stop() }
                                    library.removeSource(source)
                                }
                            }
                        }
                    }.padding(.horizontal, 9)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 10) {
                Button { addingSource = true } label: {
                    Label("Ajouter une source", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("n", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(UIColors.accent)
                .foregroundStyle(.black)

                Text("Xtream Codes  ·  M3U")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    private var channelColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(library.selectedSource?.name ?? "Chaînes")
                            .font(.title3.weight(.semibold)).lineLimit(1)
                        Text(library.isLoading ? "Chargement du catalogue…" : "\(library.filteredItems.count) éléments")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: library.reloadSelected) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Actualiser la source")
                    .disabled(library.selectedSourceID == nil || library.isLoading)
                }
                TextField("Rechercher une chaîne…", text: $library.search)
                    .textFieldStyle(.roundedBorder)
                Picker("Contenu", selection: $library.contentKind) {
                    ForEach(IPTVMediaKind.allCases, id: \.self) { kind in
                        Text(kind.frenchTitle).tag(kind)
                    }
                }
                .labelsHidden().pickerStyle(.segmented)

                Toggle(isOn: $library.favoritesOnly) {
                    Label("Favoris seulement", systemImage: "star.fill")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
            }
            .padding(16)
            Divider().overlay(.white.opacity(0.08))

            if library.isLoading {
                Spacer()
                ProgressView("Chargement du catalogue…")
                Spacer()
            } else if library.filteredItems.isEmpty {
                Spacer()
                ContentUnavailableView(
                    library.sources.isEmpty ? "Ajoutez votre première source" : "Aucun élément",
                    systemImage: library.sources.isEmpty ? "play.rectangle.on.rectangle" : "line.3.horizontal.decrease.circle",
                    description: Text(library.sources.isEmpty
                        ? "Importez une playlist M3U ou renseignez un serveur Xtream Codes."
                        : "Changez de filtre ou actualisez la playlist.")
                )
                Spacer()
            } else {
                channelRows
            }
        }
    }

    private var channelRows: some View {
        let available = library.filteredItems
        let grouped = Dictionary(grouping: available, by: \.group)
        let titles = grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 5, pinnedViews: [.sectionHeaders]) {
                ForEach(titles, id: \.self) { title in
                    Section {
                        ForEach(grouped[title] ?? []) { item in
                            channelRow(item)
                        }
                    } header: {
                        HStack {
                            Text(title.uppercased()).font(.system(size: 10, weight: .semibold))
                                .tracking(1.2).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(grouped[title]?.count ?? 0)").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(UIColors.list)
                    }
                }
            }
            .padding(.vertical, 7)
        }
    }

    private func channelRow(_ item: IPTVItem) -> some View {
        HStack(spacing: 4) {
            Button { library.selectedItemID = item.id } label: {
                HStack(spacing: 11) {
                    ChannelArtwork(url: item.logoURL)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        Text(item.kind == .live ? "DIRECT" : "FILM")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { library.toggleFavorite(item) } label: {
                Image(systemName: library.favorites.contains(item.id) ? "star.fill" : "star")
                    .foregroundStyle(library.favorites.contains(item.id) ? .yellow : .secondary)
                    .frame(width: 30, height: 36)
            }
            .buttonStyle(.plain)
            .help("Ajouter ou retirer des favoris")
        }
        .padding(.trailing, 8)
        .background(library.selectedItemID == item.id ? UIColors.selected : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 8)
    }

    private var playerColumn: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack {
                Label("LECTEUR", systemImage: "play.rectangle")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                if playback.playingItem != nil {
                    Button { playback.stop(); library.selectedItemID = nil } label: {
                        Label("Arrêter", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let item = playback.playingItem {
                VideoPlayer(player: playback.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(.black, in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10)))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 9) {
                        Text(item.kind == .live ? "EN DIRECT" : "VIDÉO À LA DEMANDE")
                            .font(.system(size: 10, weight: .bold)).tracking(1.3)
                            .foregroundStyle(UIColors.accent)
                        Text("·").foregroundStyle(.secondary)
                        Text(item.group).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(item.name).font(.title.weight(.semibold)).lineLimit(2)
                    if let error = playback.playbackError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.callout)
                        Text("Essayez le format HLS si le serveur le propose, ou un flux compatible AVPlayer.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer()
                VStack(spacing: 17) {
                    Image(systemName: "play.tv")
                        .font(.system(size: 66, weight: .ultraLight))
                        .foregroundStyle(UIColors.accent.opacity(0.65))
                    Text("Votre écran vous attend")
                        .font(.title2.weight(.semibold))
                    Text("Sélectionnez une chaîne ou un film dans la liste pour lancer la lecture.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
            HStack(spacing: 9) {
                Image(systemName: "lock.shield")
                Text("Vos identifiants Xtream sont conservés dans le Trousseau macOS.")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(27)
    }
}

private struct ChannelArtwork: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit().padding(5)
        } placeholder: {
            Image(systemName: "tv")
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(.secondary)
        }
        .frame(width: 46, height: 40)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
    }
}
