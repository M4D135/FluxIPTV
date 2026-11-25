import Foundation

/// A bounded row of physical season cases. Indices always refer to the source
/// season array, so a sliding visible window never changes navigation identity.
public struct SeriesSeasonRackLayout: Equatable, Sendable {
    public struct Slot: Equatable, Sendable {
        public let index: Int
        public let seasonNumber: Int
        public let x: Float
        public let z: Float
    }

    public static let maximumVisibleSeasons = 8
    public let selectedIndex: Int
    public let visibleRange: Range<Int>
    public let totalCount: Int
    public let slots: [Slot]
    public let halfWidth: Float
    public let halfHeight: Float
    public let halfDepth: Float
    public let caseScale: Float
    public let caseThickness: Float
    public let caseDepth: Float
    public let baseCaseZ: Float
    public let selectionAdvance: Float
    public let wall: Float
    public let clearance: Float

    public init(seasonNumbers: [Int], selectedIndex: Int, format: CasePackageFormat) {
        totalCount = seasonNumbers.count
        self.selectedIndex = seasonNumbers.isEmpty ? 0 : max(0, min(selectedIndex, seasonNumbers.count - 1))
        let count = min(Self.maximumVisibleSeasons, seasonNumbers.count)
        let start = max(0, min(self.selectedIndex - count / 2, seasonNumbers.count - count))
        visibleRange = start..<(start + count)

        wall = 0.065
        clearance = 0.025
        halfHeight = format.halfHeight
        caseScale = (halfHeight - wall - clearance) / format.halfHeight
        caseThickness = 2 * format.halfDepth() * caseScale
        caseDepth = 2 * format.halfWidth * caseScale
        selectionAdvance = format == .vhs ? 0.42 : 0.36
        let gap: Float = 0.032
        let width = Float(count) * caseThickness + Float(max(0, count - 1)) * gap
        halfWidth = max(caseThickness, width) / 2 + wall + clearance
        // The root's symmetric bounds include the selected case's full pullout.
        // Its printed back stays at precisely -halfDepth for preview projection.
        halfDepth = (caseDepth + wall + clearance + selectionAdvance) / 2
        baseCaseZ = -halfDepth + wall + clearance + caseDepth / 2

        let chosen = self.selectedIndex, baseZ = baseCaseZ, advance = selectionAdvance, thickness = caseThickness
        slots = visibleRange.enumerated().map { offset, index in
            Slot(index: index, seasonNumber: seasonNumbers[index],
                 x: (Float(offset) - Float(count - 1) / 2) * (thickness + gap),
                 z: baseZ + (index == chosen ? advance : 0))
        }
    }
}
