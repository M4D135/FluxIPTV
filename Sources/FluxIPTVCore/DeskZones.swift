import Foundation

/// Parts of a desk screen that a remote reaches as a whole. A long list keeps
/// what stands above and below it out of reach of the arrows alone: Back
/// first shows the zones, then one arrow enters the neighbouring one.
public enum DeskZone: String, CaseIterable, Sendable {
    /// Back, home, search, reload and pages, along the top of the window.
    case top
    /// Navigation column: countries or languages, scopes, lists, categories.
    case column
    /// Channels, sleeves or seasons.
    case content
    /// Actions beside the preview of a channel.
    case actions
    /// Destination bar.
    case dock

    public static let backKey = "fluxiptv.desk.backShowsZones.v1"
    /// Controls of the top zone, shared with the keyboard and remote focus.
    public static let backID = "desk-back"
    public static let homeID = "desk-home"
    public static let searchID = "search-field"

    public var title: String {
        switch self {
        case .top: "Haut"
        case .column: "Colonne"
        case .content: "Contenu"
        case .actions: "Aperçu"
        case .dock: "Dock"
        }
    }
}

public enum DeskZoneMap {
    /// Zone reached from `zone` in one direction, among those the screen
    /// offers; the same zone when nothing lies that way.
    public static func move(from zone: DeskZone, action: RemoteAction, available: [DeskZone],
                            dock: FluxDockPosition) -> DeskZone {
        candidates(zone, action, dock).first(where: available.contains) ?? zone
    }

    /// Next or previous zone in reading order, wrapping at the ends. An
    /// unknown zone starts from the first or the last one.
    public static func cycle(from zone: DeskZone?, forward: Bool, available: [DeskZone]) -> DeskZone? {
        let order = DeskZone.allCases.filter(available.contains)
        guard !order.isEmpty else { return nil }
        guard let zone, let index = order.firstIndex(of: zone) else { return forward ? order.first : order.last }
        return order[((index + (forward ? 1 : -1)) % order.count + order.count) % order.count]
    }

    /// The top band spans the window; the column, the content and the actions
    /// stand side by side under it; the bar is on the edge the user chose.
    private static func candidates(_ zone: DeskZone, _ action: RemoteAction, _ dock: FluxDockPosition) -> [DeskZone] {
        let below = dock == .corner || dock == .bottom
        switch (zone, action) {
        case (.top, .down): return [.content, .column, .actions] + (below ? [.dock] : [])
        case (.top, .up): return dock == .top ? [.dock] : []
        case (.top, .left): return dock == .leading ? [.dock] : []
        case (.top, .right): return dock == .trailing ? [.dock] : []

        case (.column, .up): return [.top] + (dock == .top ? [.dock] : [])
        case (.column, .right): return [.content, .actions] + (dock == .trailing ? [.dock] : [])
        case (.column, .down): return below ? [.dock] : []
        case (.column, .left): return dock == .leading ? [.dock] : []

        case (.content, .up): return [.top] + (dock == .top ? [.dock] : [])
        case (.content, .left): return [.column] + (dock == .leading ? [.dock] : [])
        case (.content, .right): return [.actions] + (dock == .trailing ? [.dock] : [])
        case (.content, .down): return below ? [.dock] : []

        case (.actions, .up): return [.top] + (dock == .top ? [.dock] : [])
        case (.actions, .left): return [.content, .column] + (dock == .leading ? [.dock] : [])
        case (.actions, .right): return dock == .trailing ? [.dock] : []
        case (.actions, .down): return below ? [.dock] : []

        case (.dock, _):
            switch dock {
            case .corner:
                if action == .up { return [.column, .content, .actions, .top] }
                return action == .right ? [.content, .actions, .column, .top] : []
            case .bottom: return action == .up ? [.content, .column, .actions, .top] : []
            case .top: return action == .down ? [.top, .content, .column, .actions] : []
            case .leading: return action == .right ? [.column, .content, .actions, .top] : []
            case .trailing: return action == .left ? [.actions, .content, .column, .top] : []
            }
        default: return []
        }
    }
}
