import Foundation

/// A panel of a desk screen that folds away to a strip along its edge, and
/// unfolds from it (0.9.12): "faut un tableau et pour l'aperçu faut pouvoir
/// le replier du coup, pareil pour liste de gauche, et aussi pour film serie,
/// pouvoir replier les panels" (David, 28/11).
public enum DeskPanel: String, CaseIterable, Sendable {
    /// The navigation column, on the left of each section.
    case column
    /// The preview of a channel, on the right of the television.
    case preview

    /// Whether a section of `kind` has this panel: the preview belongs to the channels.
    public func exists(in kind: IPTVMediaKind) -> Bool { self == .column || kind == .live }

    /// The key at the top of the open panel.
    public var foldID: String { "desk-\(rawValue)-fold" }
    /// The key of the strip that stands for the folded panel.
    public var unfoldID: String { "desk-\(rawValue)-unfold" }
    public var foldTitle: String { self == .column ? "Replier la colonne" : "Replier l’aperçu" }
    public var unfoldTitle: String { self == .column ? "Afficher la colonne" : "Afficher l’aperçu" }
    /// The symbol of both keys: the side of the window the panel stands on.
    public var symbol: String { self == .column ? "sidebar.left" : "sidebar.right" }
}

/// The panels folded away, section by section, kept in one preference. An
/// open panel is the default: nothing is folded until it is asked.
public struct DeskFolds: RawRepresentable, Equatable, Sendable {
    public static let storageKey = "fluxiptv.desk.folds.v1"

    /// "column-live", "preview-live", "column-movie", "column-series".
    public private(set) var folded: Set<String>

    public init() { folded = [] }

    /// What another version wrote and this one does not know is left out.
    public init?(rawValue: String) {
        let known = Set(IPTVMediaKind.allCases.flatMap { kind in
            DeskPanel.allCases.filter { $0.exists(in: kind) }.map { Self.token($0, kind) }
        })
        folded = Set(rawValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter(known.contains))
    }

    public var rawValue: String { folded.sorted().joined(separator: ",") }

    public func isFolded(_ panel: DeskPanel, in kind: IPTVMediaKind) -> Bool {
        panel.exists(in: kind) && folded.contains(Self.token(panel, kind))
    }

    /// The same folds, with `panel` of the section of `kind` folded or open.
    /// A panel the section does not have stays as it is.
    public func setting(_ panel: DeskPanel, in kind: IPTVMediaKind, folded fold: Bool) -> DeskFolds {
        guard panel.exists(in: kind) else { return self }
        var copy = self
        if fold { copy.folded.insert(Self.token(panel, kind)) } else { copy.folded.remove(Self.token(panel, kind)) }
        return copy
    }

    private static func token(_ panel: DeskPanel, _ kind: IPTVMediaKind) -> String { "\(panel.rawValue)-\(kind.rawValue)" }
}

/// The table of the channels (0.9.12): "la colonne c long a parcourir, faut
/// un tableau". As many columns as tiles fit the width the panels leave it,
/// and about forty channels a page, in whole rows.
public enum DeskChannelGrid {
    /// Tiles of at least `tile` wide, `gap` apart, in `width`: between one
    /// and `limit`. A rounding of the scale of the window must not cost a
    /// column, as it does not for the sleeves of the films.
    public static func columns(width: Double, tile: Double, gap: Double, limit: Int = 6) -> Int {
        guard width.isFinite, tile > 0 else { return 1 }
        let fit = (width + gap) / (tile + gap) + 0.02
        guard fit.isFinite else { return 1 }
        return max(1, min(max(1, limit), Int(fit.rounded(.down))))
    }

    /// About forty channels, as the single column held, in rows that are
    /// all full: the last row of a page does not stop short of its keys.
    /// Eight rows at least, so that a wide table does not turn its pages
    /// every few presses.
    public static func pageSize(columns: Int) -> Int {
        let width = max(1, columns)
        let rows = max(8, Int((40.0 / Double(width)).rounded(.up)))
        return width * rows
    }
}
