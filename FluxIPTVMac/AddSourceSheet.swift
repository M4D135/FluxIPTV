import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum NewSourceMode: String, CaseIterable, Identifiable {
    case xtream = "Xtream Codes"
    case remote = "URL M3U"
    case file = "Fichier M3U"
    var id: String { rawValue }
}

struct AddSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: IPTVLibrary
    @State private var mode: NewSourceMode = .xtream
    @State private var name = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var remoteURL = ""
    @State private var streamType = "m3u8"
    @State private var chosenFile: URL?
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ajouter une source").font(.title2.weight(.semibold))
                    Text("Aucune playlist ni chaîne n’est fournie avec l’application.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Picker("Type", selection: $mode) {
                ForEach(NewSourceMode.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Form {
                TextField("Nom (facultatif)", text: $name)
                switch mode {
                case .xtream:
                    TextField("Adresse du serveur, ex. https://exemple.fr:8080", text: $server)
                    TextField("Identifiant", text: $username)
                    SecureField("Mot de passe", text: $password)
                    Picker("Format des chaînes", selection: $streamType) {
                        Text("HLS / m3u8 (recommandé)").tag("m3u8")
                        Text("MPEG-TS / ts").tag("ts")
                    }
                case .remote:
                    TextField("URL de la playlist M3U", text: $remoteURL)
                case .file:
                    HStack(spacing: 12) {
                        Text(chosenFile?.lastPathComponent ?? "Aucun fichier sélectionné")
                            .foregroundStyle(chosenFile == nil ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer()
                        Button("Parcourir…", action: pickFile)
                    }
                }
            }
            .formStyle(.grouped)

            Label("Privilégiez HTTPS : sur HTTP, les identifiants et les URL de lecture peuvent circuler en clair.",
                  systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(saving ? "Ajout…" : "Ajouter") {
                    saving = true
                    Task {
                        do {
                            switch mode {
                            case .xtream:
                                try await library.addXtream(name: name, server: server,
                                                            username: username, password: password,
                                                            liveExtension: streamType)
                            case .remote:
                                try await library.addM3UURL(name: name, address: remoteURL)
                            case .file:
                                guard let chosenFile else { throw FormError.selectFile }
                                try await library.addM3UFile(name: name, fileURL: chosenFile)
                            }
                            dismiss()
                        } catch {
                            errorText = error.localizedDescription
                        }
                        saving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(saving)
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Choisir une playlist M3U"
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u") ?? .plainText,
                                     UTType(filenameExtension: "m3u8") ?? .plainText,
                                     .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            chosenFile = panel.url
        }
    }

    private enum FormError: LocalizedError {
        case selectFile
        var errorDescription: String? { "Choisissez un fichier M3U avant de continuer." }
    }
}
