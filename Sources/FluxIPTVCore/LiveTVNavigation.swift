/// Keyboard/gamepad navigation across the TV sidebar and virtual channel grid.
/// Channel positions are indexed; navigation never builds 24,000 focus views.
public enum LiveTVNavigation {
    public static func move(from current: String?, action: RemoteAction, channels: CatalogSlice,
                            columns: Int, sidebarIDs: [String], preferredSidebarID: String?, preferredChannelID: String? = nil,
                            prefix: [[String]]) -> String? {
        if let current, let sidebarIndex = sidebarIDs.firstIndex(of: current) {
            switch action {
            case .right: return channels.item(id: preferredChannelID)?.id ?? channels.items.first?.id ?? prefix.last?.first ?? current
            case .up:
                return sidebarIndex > 0 ? sidebarIDs[sidebarIndex - 1] : prefix.last?.first ?? current
            case .down: return sidebarIDs[min(sidebarIDs.count - 1, sidebarIndex + 1)]
            default: return current
            }
        }
        if action == .left, let index = channels.index(of: current), index.isMultiple(of: max(1, columns)),
           let first = sidebarIDs.first {
            return preferredSidebarID.flatMap { sidebarIDs.contains($0) ? $0 : nil } ?? first
        }
        return channels.move(from: current, action: action, prefix: prefix, columns: columns)
    }
}
