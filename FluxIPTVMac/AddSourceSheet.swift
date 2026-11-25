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
    /// Set when the form is drawn inside the window. Dismissing a view that no
    /// sheet presents would close the window itself.
    var inlineClose: (() -> Void)? = nil
    init(existing: IPTVSource? = nil, onSaved: @escaping () -> Void = {}, inlineClose: (() -> Void)? = nil) {
        self.existing = existing
        self.onSaved = onSaved
        self.inlineClose = inlineClose
    }
    private var inline: Bool { inlineClose != nil }
    private func finish() {
        if let inlineClose { inlineClose() } else { dismiss() }
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
        Group {
            #if os(tvOS)
            televisionForm
            #else
            if inline { form.frame(maxWidth: 760, alignment: .leading) }
            else { ScrollView { form }.fluxSheetSize(width: sourceWidth, height: 650) }
            #endif
        }
        .preferredColorScheme(.dark)
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

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 28, weight: .medium)).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 4) {
                    Text(existing == nil ? "Charger une liste" : "Modifier la source").font(.title2.weight(.semibold))
                    Text("Connectez votre propre abonnement ou playlist IPTV.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if existing == nil {
                Picker("Type", selection: $mode) {
                    ForEach(NewSourceMode.allCases) { kind in Text(kind.rawValue).tag(kind) }
                }
                #if os(macOS)
                // In the window, the three kinds stay visible side by side.
                .pickerStyle(.segmented)
                #endif
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
                    if saving { attempt?.cancel() } else { finish() }
                }.fluxShortcut(cancel: true)
                Spacer()
                if saving {
                    ProgressView()
                        #if !os(tvOS)
                        .controlSize(.small)
                        #endif
                    Text("Vérification…").font(.caption).foregroundStyle(.secondary)
                }
                Button(existing == nil ? "Vérifier et ajouter" : "Vérifier et enregistrer", action: submit)
                    .fluxShortcut().buttonStyle(.borderedProminent).disabled(saving || !valid)
            }
        }
        .padding(sourcePadding)
    }

    #if os(tvOS)
    // MARK: Television: the whole screen, nothing to scroll

    /// What the form is for and the kind of source on the left; the fields
    /// and the two actions on the right. Everything is on screen at once: a
    /// remote never has to scroll a form to find its button.
    private var televisionForm: some View {
        HStack(alignment: .top, spacing: 56) {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "server.rack").font(.system(size: 58, weight: .medium)).foregroundStyle(.cyan)
                Text(existing == nil ? "Charger une liste" : "Modifier la source")
                    .font(.system(size: 50, weight: .bold)).lineLimit(2).minimumScaleFactor(0.8)
                Text("Connectez votre propre abonnement ou playlist IPTV.")
                    .font(.system(size: 27)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if existing == nil {
                    Text("TYPE DE SOURCE").font(.system(size: 21, weight: .semibold)).tracking(2)
                        .foregroundStyle(.secondary).padding(.top, 18)
                    Picker("Type", selection: $mode) {
                        ForEach(NewSourceMode.allCases) { kind in Text(kind.rawValue).tag(kind) }
                    }
                    .pickerStyle(.segmented).labelsHidden().disabled(saving)
                }
                if needsUnlock {
                    Text("Ressaisissez vos identifiants ou récupérez-les depuis le Trousseau. Vos favoris seront conservés.")
                        .font(.system(size: 23)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let existing, existing.credentialStorage != .localPrivate {
                        Button { unlockExplicitly() } label: { Label("Récupérer depuis le Trousseau", systemImage: "lock.open") }
                    }
                    Toggle("Autoriser le Trousseau à l’enregistrement", isOn: $allowKeychainPrompt)
                }
                Spacer(minLength: 0)
                Label("En HTTP, les identifiants ne sont pas chiffrés sur le réseau.", systemImage: "lock.shield")
                    .font(.system(size: 22)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 560, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 14) {
                Group { televisionFields }.disabled(saving)
                Spacer(minLength: 0)
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 23)).foregroundStyle(.orange).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14).background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                }
                HStack(spacing: 24) {
                    Button(saving ? "Interrompre" : "Annuler", role: .cancel) {
                        if saving { attempt?.cancel() } else { finish() }
                    }
                    .accessibilityIdentifier("source-cancel")
                    Spacer(minLength: 0)
                    if saving {
                        ProgressView()
                        Text("Vérification…").font(.system(size: 23)).foregroundStyle(.secondary)
                    }
                    Button(existing == nil ? "Vérifier et ajouter" : "Vérifier et enregistrer", action: submit)
                        .disabled(saving || !valid)
                        .accessibilityIdentifier("source-submit")
                        #if FLUX_CATALOG_UI_TESTING
                        .background(TVCatalogControlFrameProbe(identifier: "source-submit").allowsHitTesting(false))
                        #endif
                }
            }
            .padding(34)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .fluxGlass(radius: 36)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                FluxBackdrop()
                LinearGradient(colors: [.black.opacity(0.30), .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
            }.ignoresSafeArea()
        }
        .onExitCommand { if saving { attempt?.cancel() } else { finish() } }
    }

    @ViewBuilder private var televisionFields: some View {
        televisionField("Nom de la source (facultatif)") {
            TextField("Ex. Mon abonnement", text: $name).focused($focused, equals: .name)
        }
        switch mode {
        case .xtream:
            televisionField("Serveur", hint: "Adresse complète, avec le port si nécessaire. Sans protocole : HTTPS.") {
                TextField("https://serveur.exemple:8080", text: $server)
                    .focused($focused, equals: .server).onSubmit { focused = .username }
                    .accessibilityIdentifier("source-server")
                    #if FLUX_CATALOG_UI_TESTING
                    .background(TVCatalogControlFrameProbe(identifier: "source-server").allowsHitTesting(false))
                    #endif
            }
            televisionField("Identifiant") {
                TextField("Votre identifiant", text: $username)
                    .focused($focused, equals: .username).onSubmit { focused = .password }
            }
            televisionField("Mot de passe") {
                HStack(spacing: 16) {
                    Group {
                        if showPassword { TextField("Votre mot de passe", text: $password) }
                        else { SecureField("Votre mot de passe", text: $password) }
                    }
                    .focused($focused, equals: .password)
                    Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }
                        .accessibilityLabel(showPassword ? "Masquer le mot de passe" : "Afficher le mot de passe")
                }
            }
            televisionField("Format TV") {
                Picker("Format TV", selection: $streamType) {
                    Text("HLS (.m3u8) — recommandé").tag("m3u8")
                    Text("MPEG-TS (.ts)").tag("ts")
                }
                .pickerStyle(.segmented).labelsHidden()
            }
        case .remote:
            televisionField("URL de la playlist M3U") {
                TextField("https://serveur.exemple/playlist.m3u", text: $remoteURL).focused($focused, equals: .remote)
                    .accessibilityIdentifier("source-server")
                    #if FLUX_CATALOG_UI_TESTING
                    .background(TVCatalogControlFrameProbe(identifier: "source-server").allowsHitTesting(false))
                    #endif
            }
        }
    }

    private func televisionField<Content: View>(_ title: String, hint: String? = nil,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 23, weight: .semibold)).foregroundStyle(.secondary)
            content()
            if let hint {
                Text(hint).font(.system(size: 20)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
    #endif

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.callout.weight(.medium))
            content()
        }
    }

    private var sourceWidth: CGFloat {
        #if os(tvOS)
        1080
        #else
        680
        #endif
    }
    private var sourcePadding: CGFloat {
        #if os(tvOS)
        42
        #else
        26
        #endif
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
                finish()
            } catch {
                if Task.isCancelled { errorText = "Vérification interrompue. Vous pouvez réessayer." }
                else { errorText = IPTVLibrary.safeSourceError(error); if error is KeychainError || error is PrivateCredentialStoreError { needsUnlock = true } }
            }
        }
    }

}
