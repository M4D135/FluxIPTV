/// Keyboard and remote navigation for the desk layout: a navigation column,
/// a virtual grid with its toolbar rows above, and an optional row of actions
/// on the far side of the grid. A move that cannot leave an edge returns the
/// identifier it received, so the caller can hand the direction to the dock.
public enum DeskNavigation {
    public static func move(from current: String?, action: RemoteAction, items: CatalogSlice, columns: Int,
                            sidebarIDs: [String], preferredSidebarID: String?, preferredItemID: String?,
                            toolbar: [[String]], trailingIDs: [String] = [], headerIDs: [String] = []) -> String? {
        let rows = toolbar.filter { !$0.isEmpty }
        let all = items.items
        let width = max(1, columns)
        let gridEntry = items.item(id: preferredItemID)?.id ?? all.first?.id
        let sidebarEntry = preferredSidebarID.flatMap { sidebarIDs.contains($0) ? $0 : nil } ?? sidebarIDs.first

        // Controls of the top row that stand above the column lead down into
        // it, and the top of the column leads back up to them.
        if let current, headerIDs.contains(current), action == .down, let first = sidebarIDs.first { return first }

        if let current, let index = sidebarIDs.firstIndex(of: current) {
            switch action {
            case .up: return index > 0 ? sidebarIDs[index - 1] : headerIDs.first ?? current
            case .down: return sidebarIDs[min(sidebarIDs.count - 1, index + 1)]
            case .right: return gridEntry ?? rows.first?.first ?? trailingIDs.first ?? current
            default: return current
            }
        }

        if let current, let index = trailingIDs.firstIndex(of: current) {
            switch action {
            case .left: return index > 0 ? trailingIDs[index - 1] : gridEntry ?? rows.last?.last ?? sidebarEntry ?? current
            case .right: return trailingIDs[min(trailingIDs.count - 1, index + 1)]
            default: return current
            }
        }

        if let index = items.index(of: current) {
            let row = index / width, column = index % width
            switch action {
            case .left:
                return column == 0 ? sidebarEntry ?? all[index].id : all[index - 1].id
            case .right:
                let atEnd = column == width - 1 || index == all.count - 1
                if !atEnd { return all[index + 1].id }
                if let first = trailingIDs.first { return first }
                // Reading order: the end of a row of a grid leads to the start
                // of the next one, as a line of a page does (David, 26/11). A
                // list of one column keeps Right for the edge.
                return width > 1 && index + 1 < all.count ? all[index + 1].id : all[index].id
            case .up:
                if row > 0 { return all[index - width].id }
                return rows.last.map { $0[min(column, $0.count - 1)] } ?? all[index].id
            case .down:
                if index + width < all.count { return all[index + width].id }
                // A shorter last row stays reachable from the row above it.
                return row < (all.count - 1) / width ? all[all.count - 1].id : all[index].id
            default: return all[index].id
            }
        }

        if let current, let row = rows.firstIndex(where: { $0.contains(current) }),
           let column = rows[row].firstIndex(of: current) {
            switch action {
            case .left: return column > 0 ? rows[row][column - 1] : sidebarEntry ?? current
            case .right: return column + 1 < rows[row].count ? rows[row][column + 1] : trailingIDs.first ?? current
            case .up: return row > 0 ? rows[row - 1][min(column, rows[row - 1].count - 1)] : current
            case .down:
                if row + 1 < rows.count { return rows[row + 1][min(column, rows[row + 1].count - 1)] }
                return all.isEmpty ? current : all[min(column, min(width, all.count) - 1)].id
            default: return current
            }
        }

        return gridEntry ?? rows.first?.first ?? sidebarEntry ?? trailingIDs.first
    }
}
