import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import UniformTypeIdentifiers

private enum NewSourceMode: String, CaseIterable, Identifiable {
    case xtream = "Xtream Codes"
    case remote = "URL M3U"
    #if !os(tvOS)
    case file = "Fichier M3U"
    #endif
    var id: String { rawValue }
}

struct AddSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: IPTVLibrary
    var existing: IPTVSource? = nil
    var onSaved: () -> Void = {}
    init(existing: IPTVSource? = nil, onSaved: @escaping () -> Void = {}) {
        self.existing = existing
        self.onSaved = onSaved
    }

    @State private var mode: NewSourceMode = .xtream
    @State private var name = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var remoteURL = ""
    @State private var streamType = "m3u8"
    @State private var chosenFile: URL?
    @State private var importingFile = false
    @State private var showPassword = false
    @State private var allowKeychainPrompt = false
    @State private var storage: CredentialStorageMode = .keychain
    @State private var needsUnlock = false
    @State private var saving = false
    @State private var errorText: String?
    @State private var attempt: Task<Void, Never>?
    @FocusState private var focused: Field?
    private enum Field: Hashable { case name, server, username, password, remote }

    private var valid: Bool {
        switch mode {
        case .xtream: return (try? XtreamLogin(server: server, username: username, password: password)) != nil
        case .remote: return (try? IPTVURL.validated(remoteURL)) != nil
        #if !os(tvOS)
        case .file: return chosenFile != nil
        #endif
        }
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 28, weight: .medium)).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 4) {
                    Text(existing == nil ? "Ajouter une source" : "Modifier la source").font(.title2.weight(.semibold))
                    Text("Connectez votre propre abonnement ou playlist IPTV.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if existing == nil {
                Picker("Type", selection: $mode) {
                    ForEach(NewSourceMode.allCases) { kind in Text(kind.rawValue).tag(kind) }
                }
                .labelsHidden().disabled(saving)
            }
            if needsUnlock {
                Text("Ressaisissez vos identifiants ou récupérez-les depuis l’ancien Trousseau. Vos favoris seront conservés.").font(.caption).foregroundStyle(.secondary)
                if let existing, existing.credentialStorage != .localPrivate {
                    Button { unlockExplicitly() } label: { Label("Récupérer depuis le Trousseau (autorisation macOS)", systemImage: "lock.open") }.buttonStyle(.bordered)
                }
            }
            Divider()
            // Fixed vertical stack, rather than a grouped Form whose scrolling height could clip fields in a sheet.
            VStack(alignment: .leading, spacing: 13) {
                field("Nom de la source (facultatif)") {
                    TextField("Ex. Mon abonnement", text: $name).focused($focused, equals: .name)
                }
                switch mode {
                case .xtream:
                    HStack {
                        Text("Serveur").font(.callout.weight(.medium))
                        Spacer()
                        #if !os(tvOS)
                        Button(action: pasteXtream) { Label("Coller un lien Xtream", systemImage: "doc.on.clipboard") }
                            .buttonStyle(.bordered).font(.caption)
                        #endif
                    }
                    TextField("https://serveur.exemple:8080", text: $server)
                        .focused($focused, equals: .server)
                        .onSubmit { focused = .username }
                    Text("Adresse complète, avec le port si nécessaire. Sans protocole : HTTPS.")
                        .font(.caption).foregroundStyle(.secondary)
                    field("Identifiant") {
                        TextField("Votre identifiant", text: $username)
                            .focused($focused, equals: .username).onSubmit { focused = .password }
                    }
                    field("Mot de passe") {
                        HStack(spacing: 8) {
                            Group {
                                if showPassword {
                                    TextField("Votre mot de passe", text: $password)
                                } else {
                                    SecureField("Votre mot de passe", text: $password)
                                }
                            }
                            .focused($focused, equals: .password)
                            .onSubmit { if valid { submit() } }
                            Button { showPassword.toggle(); focused = .password } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .frame(width: 28, height: 23)
                            }.buttonStyle(.bordered)
                            .accessibilityLabel(showPassword ? "Masquer le mot de passe" : "Afficher le mot de passe")
                        }
                    }
                    Picker("Format TV", selection: $streamType) {
                        Text("HLS (.m3u8) — recommandé").tag("m3u8")
                        Text("MPEG-TS (.ts)").tag("ts")
                    }
                case .remote:
                    field("URL de la playlist M3U") {
                        TextField("https://serveur.exemple/playlist.m3u", text: $remoteURL).focused($focused, equals: .remote)
                    }
                #if !os(tvOS)
                case .file:
                    field("Playlist locale") {
                        HStack(spacing: 12) {
                            Text(chosenFile?.lastPathComponent ?? "Aucun fichier sélectionné").lineLimit(1)
                            Spacer(); Button("Parcourir…") { importingFile = true }
                        }
                    }
                #endif
                }
            }
            .fluxFieldStyle()
            .disabled(saving)
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.circle.fill")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            }
            #if os(macOS)
            if mode == .xtream || mode == .remote {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mémorisation des identifiants").font(.callout.weight(.semibold))
                    Picker("Stockage", selection: $storage) {
                        Text("Trousseau Apple").tag(CredentialStorageMode.keychain)
                        Text("Sur ce Mac, sans Trousseau").tag(CredentialStorageMode.localPrivate)
                    }.pickerStyle(.radioGroup)
                    if storage == .localPrivate {
                        Label("Aucune demande du Trousseau à l’ouverture ni après recompilation. Les identifiants sont enregistrés dans un fichier privé de votre compte (non chiffré, permissions 600). Toute personne ou app ayant accès à votre compte peut potentiellement les lire. Le Trousseau reste plus sûr.", systemImage: "exclamationmark.shield")
                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Toggle("Autoriser une demande macOS lors de l’enregistrement", isOn: $allowKeychainPrompt).font(.caption)
                    }
                }.disabled(saving)
            }
            #else
            if needsUnlock { Toggle("Autoriser le Trousseau lors de l’enregistrement", isOn: $allowKeychainPrompt).font(.caption) }
            #endif
            Label("En HTTP, les identifiants ne sont pas chiffrés sur le réseau.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Button(saving ? "Interrompre" : "Annuler", role: .cancel) {
                    if saving { attempt?.cancel() } else { dismiss() }
                }.fluxShortcut(cancel: true)
                Spacer()
                if saving { ProgressView().controlSize(.small); Text("Vérification…").font(.caption).foregroundStyle(.secondary) }
                Button(existing == nil ? "Vérifier et ajouter" : "Vérifier et enregistrer", action: submit)
                    .fluxShortcut().buttonStyle(.borderedProminent).disabled(saving || !valid)
            }
        }
        .padding(26)
        }
        .fluxSheetSize(width: 680, height: 650)
        #if !os(tvOS)
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [UTType(filenameExtension: "m3u") ?? .plainText, UTType(filenameExtension: "m3u8") ?? .plainText, .plainText]) { result in
            switch result {
            case .success(let url): chosenFile = url; errorText = nil
            case .failure: errorText = "Impossible d’ouvrir ce fichier."
            }
        }
        #endif
        #if !os(tvOS)
        .interactiveDismissDisabled(saving)
        #endif
        .onAppear(perform: initialize)
        .onChange(of: mode) { _, value in
            errorText = nil; showPassword = false
            focused = value == .xtream ? .server : value == .remote ? .remote : .name
        }
        .onDisappear { attempt?.cancel() }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.callout.weight(.medium))
            content()
        }
    }

    private func initialize() {
        if let existing {
            name = existing.name
            #if os(macOS)
            storage = existing.credentialStorage ?? .keychain
            #endif
            mode = existing.kind == .m3uURL ? .remote : .xtream
            do { fill(try library.xtreamSecret(for: existing)); needsUnlock = false }
            catch { needsUnlock = true; errorText = IPTVLibrary.safeSourceError(error) }
        }
        focused = .server
    }

    private func fill(_ saved: IPTVSecret) {
        if mode == .remote { remoteURL = saved.endpoint }
        else { server = saved.endpoint; username = saved.username; password = saved.password; streamType = saved.liveExtension }
    }
    private func unlockExplicitly() {
        guard let existing else { return }
        do { fill(try library.xtreamSecret(for: existing,interactive:true)); needsUnlock = false; errorText = nil }
        catch { errorText = IPTVLibrary.safeSourceError(error) }
    }
    #if !os(tvOS)
    private func pasteXtream() {
        #if os(macOS)
        let pasted = NSPasteboard.general.string(forType: .string)
        #else
        let pasted = UIPasteboard.general.string
        #endif
        guard let text = pasted else {
            errorText = "Le presse-papiers ne contient pas de lien."; return
        }
        do {
            let login = try XtreamLogin(server: text)
            server = login.server.absoluteString; username = login.username; password = login.password
            showPassword = false; errorText = nil; focused = .username
        } catch {
            errorText = "Collez un lien Xtream complet avec les paramètres username et password, ou remplissez les champs séparément."
        }
    }

    #endif

    private func submit() {
        guard !saving, valid else { return }
        saving = true; errorText = nil; focused = nil; showPassword = false
        attempt = Task { @MainActor in
            defer { saving = false; attempt = nil }
            do {
                switch mode {
                case .xtream:
                    try await library.addXtream(name: name, server: server, username: username, password: password,
                                                liveExtension: streamType, replacing: existing, allowKeychainPrompt: allowKeychainPrompt, storage: storage)
                case .remote: try await library.addM3UURL(name: name, address: remoteURL, replacing: existing, allowKeychainPrompt: allowKeychainPrompt, storage: storage)
                #if !os(tvOS)
                case .file:
                    guard let chosenFile else { throw IPTVError.invalidPlaylist }
                    try await library.addM3UFile(name: name, fileURL: chosenFile)
                #endif
                }
                onSaved()
                dismiss()
            } catch {
                if Task.isCancelled { errorText = "Vérification interrompue. Vous pouvez réessayer." }
                else { errorText = IPTVLibrary.safeSourceError(error); if error is KeychainError || error is PrivateCredentialStoreError { needsUnlock = true } }
            }
        }
    }

}
