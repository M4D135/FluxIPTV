import Foundation

/// Concept, not a colour theme. Profiles share catalogue, playback, navigation
/// and the native procedural geometry kernel.
public enum ClubInterfaceProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case neoVideoClub, appleCinema
    public static let storageKey = "fluxiptv.appearance.clubConcept.v1"
    public var id: String { rawValue }
    public var title: String { self == .neoVideoClub ? "Néo Vidéoclub 90" : "Apple Cinema" }
    public var subtitle: String {
        switch self {
        case .neoVideoClub: "Grille vidéoclub, rayonnages physiques, grandes pochettes 3D et lumière néon."
        case .appleCinema: "Grille cinéma épurée, fond panoramique, pochettes 3D aérées et commandes flottantes."
        }
    }
    public var symbol: String { self == .neoVideoClub ? "film.stack" : "sparkles.tv" }
    public var isEditorial: Bool { self == .appleCinema }
    public struct Arrangement: Equatable, Sendable {
        public let neighborScale: Double
        public let neighborX: Double
        public let neighborDepth: Double
        public let neighborAngle: Double
    }
    public var arrangement: Arrangement {
        switch self {
        case .neoVideoClub: Arrangement(neighborScale:0.46,neighborX:1.76,neighborDepth:1.04,neighborAngle:22)
        case .appleCinema: Arrangement(neighborScale:0.43,neighborX:1.67,neighborDepth:1.18,neighborAngle:16)
        }
    }
    /// A full-size central sleeve and at most four smaller, recessed neighbors.
    public func inspectionDistance(aspect: Double, collector: Bool = false, open: Bool = false) -> Double {
        CaseCarousel.distance(aspect:aspect,editorial:isEditorial,collector:collector,open:open)
    }
    public static func neighbors(index: Int, count: Int) -> (previous: Int?, next: Int?) {
        guard count>0,index>=0,index<count else {return (nil,nil)}
        return (index>0 ? index-1:nil,index<count-1 ? index+1:nil)
    }
    /// Native FERRO sweep port generates the curved architectural elements.
    /// The room remains the existing bounded procedural recipe. No web runtime.
    public func stage(theme: VideoClubTheme) -> [ProceduralCinema.Face] {
        typealias V = ProceduralCinema.V
        let p=theme.palette
        switch self {
        case .neoVideoClub:
            let room=theme.room(kind:.movie)
            var mesh=room
            for side: Double in [-1,1] {
                let points: [V] = [V(side*8.0,-2.9,6.7),V(side*8.0,2.7,7.6),V(side*6.8,3.2,8.5),V(side*4.4,3.2,8.7)]
                let tint = side < 0 ? p.accent : p.second
                mesh += ProceduralCinema.tube(points:points,radius:0.045,sides:6,subdivisions:2,color:tint)
            }
            return mesh
        case .appleCinema:
            var mesh:[ProceduralCinema.Face]=[]
            for i in 0..<3 {
                let k=Double(i)
                let path=(0...12).map { j -> V in
                    let angle=Double(j)*Double.pi/12
                    return V(3.4+(3.8+k*0.5)*cos(angle),-3.0+(1.4+k*0.25)*sin(angle),7.5+k*0.8)
                }
                mesh += ProceduralCinema.tube(points:path,radius:0.05+0.02*k,sides:6,subdivisions:2,color:V(0.27,0.32,0.43)*(1-k*0.15))
            }
            return mesh
        }
    }
}
