import Foundation
import Combine

@MainActor final class CaseDescriptionModel: ObservableObject {
    @Published var source: CaseDescriptionSource = .iptv
    @Published private(set) var text = ""
    @Published private(set) var status: String?
    @Published private(set) var sourceURL: URL?
    @Published private(set) var title = ""
    @Published private(set) var isLoading = false
    private var generation = UUID()

    func step(_ delta: Int) {
        generation = UUID(); source = source.next(delta: delta)
        text = ""; sourceURL = nil; status = nil
    }
    func reset() {
        generation = UUID(); source = .iptv
        text = ""; title = ""; status = nil; sourceURL = nil; isLoading = false
    }
    func load(item: IPTVItem, details: IPTVDetails) async {
        guard !Task.isCancelled else { return }
        let token = UUID(); generation = token
        let requestedSource = source
        title = CinemaLinks.title(item.name); text = ""; status = nil; sourceURL = nil
        guard source != .iptv else {
            text = details.synopsis?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            status = text.isEmpty ? "Le fournisseur IPTV n’a pas communiqué de description." : "Description du fournisseur IPTV"
            isLoading = false; return
        }
        isLoading = true; status = "Chargement de \(source.title)…"
        defer { if generation == token { isLoading = false } }
        do {
            let result = try await CaseDescriptionService.shared.entry(name: item.name, year: details.year, series: item.kind == .series, source: requestedSource)
            guard !Task.isCancelled, generation == token, source == requestedSource else { return }
            title = result.title; text = result.text; sourceURL = result.sourceURL; status = result.status
        } catch {
            guard !Task.isCancelled, generation == token, source == requestedSource else { return }
            text = ""; status = "\(source.title) est indisponible. Vous pouvez ouvrir la source ou réessayer."
            sourceURL = CinemaLinks.url(for: source == .wikipedia ? .wikipedia : .allocine, name: item.name, year: details.year, series: item.kind == .series)
        }
    }
}
