import Foundation

/// Layout shared by the printed sleeve, UV picking and remote navigation.
/// Coordinates are normalized from the top-left, independently of viewport size.
public enum CaseFaceLayout {
    public enum Action: Hashable, Sendable {
        case flip, rotate, play, favorite, trailer, close, previous, next
        case details, description, episodes, previousSeason, nextSeason, previousPage, nextPage, retry, episode(Int)
    }
    public struct Region: Equatable, Sendable {
        public let action: Action
        public let rect: CGRect
        public init(_ action: Action, _ rect: CGRect) { self.action=action; self.rect=rect }
    }
    public enum Page: Hashable, Sendable { case front, details, episodes }
    public static let episodePageSize = 4
    private static func region(_ action: Action, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Region {
        Region(action, CGRect(x:x,y:y,width:w,height:h))
    }
    public static func regions(_ page: Page, series: Bool, trailer: Bool, episodeCount: Int = 0, retry: Bool = false) -> [Region] {
        let footer = [region(.previous,0.04,0.92,0.20,0.06),region(.close,0.26,0.92,0.48,0.06),region(.next,0.76,0.92,0.20,0.06)]
        switch page {
        case .front:
            return [region(series ? .episodes : .play,0.04,0.79,0.58,0.06),region(.favorite,0.64,0.79,0.32,0.06),region(.flip,0.04,0.86,0.54,0.05),region(.rotate,0.60,0.86,0.36,0.05)] + footer
        case .details:
            var a = [region(series ? .episodes : .play,0.04,0.74,0.58,0.06),region(.favorite,0.64,0.74,0.32,0.06)]
            if trailer { a.append(region(.trailer,0.04,0.81,0.92,0.05)) }
            return a + [region(.flip,0.04,0.87,0.54,0.04),region(.rotate,0.60,0.87,0.36,0.04)] + footer
        case .episodes:
            var a = [region(.previousSeason,0.04,0.16,0.22,0.05),region(.nextSeason,0.74,0.16,0.22,0.05)]
            for i in 0..<min(episodePageSize,max(0,episodeCount)) {
                a.append(region(.episode(i),0.04,0.23+Double(i)*0.133,0.92,0.123))
            }
            if retry { a.append(region(.retry,0.22,0.47,0.56,0.08)) }
            return a + [region(.previousPage,0.04,0.78,0.23,0.06),region(.nextPage,0.73,0.78,0.23,0.06),region(.details,0.04,0.85,0.92,0.06)] + footer
        }
    }
    public static func action(at uv: CGPoint, in regions: [Region]) -> Action? { regions.first { $0.rect.contains(uv) }?.action }
    public static func face(yaw: Double, pitch: Double) -> Page? {
        let z=cos(yaw * .pi/180)*cos(pitch * .pi/180)
        return abs(z)<0.18 ? nil : (z<0 ? .details : .front)
    }
    public static func nextFocus(from current: Action?, by delta: Int, regions: [Region]) -> Action? {
        let actions=regions.map(\.action)
        guard !actions.isEmpty else {return nil}
        guard let current,let i=actions.firstIndex(of:current) else {return delta<0 ? actions.last:actions.first}
        return actions[(i+delta%actions.count+actions.count)%actions.count]
    }
}

public enum CaseRenderQuality: String, CaseIterable, Identifiable, Sendable {
    case economy, balanced, cinema
    public var id: String {rawValue}
    public var title: String {switch self {case .economy:"Éco";case .balanced:"HD équilibré";case .cinema:"Cinéma HD+"}}
    public var sleeveWidth: Int {switch self {case .economy:640;case .balanced:1024;case .cinema:1536}}
    public var sleeveHeight: Int {sleeveWidth*3/2}
    /// Front and back of a closed movie sleeve.
    public var textureBytes: Int {sleeveWidth*sleeveHeight*4*2}
    /// Front, synopsis, episode tray and one small spine for an open collector.
    public var collectorTextureBytes: Int {sleeveWidth*sleeveHeight*4*3+160*1536*4}
    public var fps: Int {self == .economy ? 30:60}
    public var cornerSegments: Int {self == .economy ? 2:4}
}
