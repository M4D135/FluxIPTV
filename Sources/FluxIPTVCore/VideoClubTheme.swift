import Foundation

/// One theme changes architecture, palette, lighting and case material together.
/// The live-TV recipe is a living room, never a video store.
public enum VideoClubTheme: String, CaseIterable, Codable, Sendable {
    case neo90, midnight, vintage70, artDeco, zen, future
    public var title: String {
        switch self { case .neo90: "Néo 80–90"; case .midnight: "Cinéma de minuit"; case .vintage70: "Années 70"; case .artDeco: "Palace Art déco"; case .zen: "Scandinave"; case .future: "Futur néon" }
    }
    public var subtitle: String {
        switch self { case .neo90: "Néon cyan et rose · bois foncé · VHS"; case .midnight: "Graphite · velours · lumière bleue"; case .vintage70: "Noyer · ambre · orange brûlé"; case .artDeco: "Laiton · vert bouteille · lignes dorées"; case .zen: "Chêne · pierre · lumière naturelle"; case .future: "Titane · indigo · lumière froide" }
    }
    public typealias V = ProceduralCinema.V
    public var palette: (wall: V, wood: V, accent: V, second: V, caseEdge: V) {
        switch self {
        case .neo90: (V(0.12,0.055,0.20),V(0.29,0.13,0.085),V(0.08,0.86,0.96),V(0.97,0.19,0.55),V(0.16,0.095,0.24))
        case .midnight: (V(0.055,0.07,0.105),V(0.13,0.15,0.18),V(0.36,0.66,1),V(0.47,0.22,0.45),V(0.10,0.12,0.17))
        case .vintage70: (V(0.27,0.15,0.075),V(0.44,0.24,0.095),V(1,0.64,0.23),V(0.75,0.23,0.11),V(0.24,0.14,0.06))
        case .artDeco: (V(0.045,0.17,0.14),V(0.12,0.19,0.16),V(0.95,0.73,0.32),V(0.28,0.63,0.49),V(0.14,0.18,0.10))
        case .zen: (V(0.34,0.37,0.39),V(0.60,0.46,0.29),V(0.90,0.80,0.65),V(0.40,0.63,0.62),V(0.30,0.27,0.21))
        case .future: (V(0.075,0.10,0.21),V(0.23,0.28,0.39),V(0.38,0.83,1),V(0.51,0.31,1),V(0.14,0.20,0.31))
        }
    }
    /// Bounded, deterministic solids. No imported models or textures.
    public func room(kind: IPTVMediaKind) -> [ProceduralCinema.Face] {
        let p = palette
        var result: [ProceduralCinema.Face] = []
        func box(_ x: Double,_ y: Double,_ z: Double,_ w: Double,_ h: Double,_ d: Double,_ tint: V) {
            guard w>0,h>0,d>0 else {return}
            let lo=V(x-w/2,y-h/2,z-d/2),hi=V(x+w/2,y+h/2,z+d/2)
            let v=[V(lo.x,lo.y,lo.z),V(hi.x,lo.y,lo.z),V(hi.x,hi.y,lo.z),V(lo.x,hi.y,lo.z),V(lo.x,lo.y,hi.z),V(hi.x,lo.y,hi.z),V(hi.x,hi.y,hi.z),V(lo.x,hi.y,hi.z)]
            for f in [[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[0,1,5,4],[3,7,6,2]] {
                result.append(.init(a:v[f[0]],b:v[f[1]],c:v[f[2]],color:tint));result.append(.init(a:v[f[0]],b:v[f[2]],c:v[f[3]],color:tint))
            }
        }
        box(0,0,11,22,12,0.25,p.wall)
        box(0,-3.1,7.5,24,0.24,12,p.wood*0.45)
        if kind == .live {
            // Large recessed display, console, wall panels and low sofa silhouettes.
            box(0,0.8,10.5,9.7,5.4,0.25,p.wood)
            box(0,0.8,10.3,9.2,5.0,0.20,V(0.018,0.022,0.032))
            box(0,-2.14,9.5,10.5,0.65,1.8,p.wood)
            box(0,3.65,10.45,10.8,0.075,0.09,p.accent)
            for side in [-1.0,1.0] {
                box(side*6.5,0,10.4,0.22,6.4,0.28,p.second)
                box(side*6.25,-1.5,9.1,1.45,2.0,0.85,p.caseEdge)
                box(side*6.25,-0.6,8.9,1.25,0.22,0.4,p.accent*0.75)
            }
            box(0,-2.92,3.7,7.2,0.35,1.9,p.caseEdge)
        } else if kind == .movie {
            // Cinema lobby: an entrance, lit poster cases, velvet panels and a
            // carpet lead toward the auditorium. Series shelving stays separate.
            let velvet=V(0.30,0.035,0.065)
            box(0,-2.95,6.5,6.5,0.09,10.0,velvet)
            box(0,0.32,10.50,5.0,5.8,0.30,p.wood)
            box(0,0.18,10.25,4.45,5.35,0.32,V(0.017,0.018,0.026))
            for side in [-1.0,1.0] {
                box(side*2.46,0.20,9.98,0.15,5.55,0.18,p.accent*0.7)
                box(side*1.78,0.10,9.98,0.66,5.15,0.25,velvet)
                for bay in 0..<2 {
                    let x=side*(4.2+Double(bay)*3.0)
                    box(x,0.4,10.12,2.25,3.72,0.32,p.accent*0.62)
                    box(x,0.4,9.91,2.04,3.48,0.12,V(0.025,0.025,0.04))
                    box(x,0.4,9.80,1.87,3.27,0.06,bay == 0 ? p.second*0.45:p.accent*0.30)
                    box(x,2.38,10.0,2.40,0.10,0.23,p.accent)
                }
                for n in 0..<3 {
                    box(side*3.0,-2.23,3.0+Double(n)*2.0,0.09,1.4,0.09,p.accent*0.55)
                    box(side*3.0,-1.53,3.0+Double(n)*2.0,0.23,0.16,0.23,p.accent)
                }
            }
            box(0,3.30,10.0,5.4,0.18,0.30,p.accent)
            box(0,3.66,10.0,5.0,0.12,0.27,p.second)
        } else {
            let shelves = self == .artDeco || self == .vintage70 ? 4 : 3
            let height = self == .vintage70 ? 1.08 : 1.32
            for bay in -2...2 {
                let x=Double(bay)*3.55
                box(x,0.25,9.9,3.4,5.6,0.18,p.wood*0.55)
                for row in 0...shelves {
                    let y = -2.62+Double(row)*height
                    box(x,y,9.20,3.4,0.12,1.35,p.wood)
                    box(x,y+0.09,8.51,3.37,0.045,0.07,row%2==0 ? p.accent:p.second)
                    if row<shelves {
                        for slot in 0..<6 {
                            let hue = (slot+row+bay+12)%3
                            let c = hue == 0 ? p.second*0.68 : hue == 1 ? p.caseEdge : p.accent*0.38
                            box(x-1.32+Double(slot)*0.50,y+0.60,9.1,0.37,0.94,0.49,c)
                        }
                    }
                }
                box(x-1.71,0.22,9.28,0.12,5.6,1.2,p.wood)
            }
            box(0,3.42,8.9,18.4,0.18,0.25,p.accent)
            box(0,3.86,9.0,18.4,0.07,0.25,p.second)
        }
        // Distinct architectural signatures, not a palette swap alone.
        // Keep all additions bounded and use the same closed-box primitive.
        switch self {
        case .neo90:
            // Neon ceiling strips, alternating arcade-style accents.
            for side in [-1.0,1.0] {
                box(side*7.8,3.2,7.2,0.08,0.09,4.0,p.accent)
                box(side*8.2,2.75,8.9,0.09,2.2,0.09,p.second)
            }
        case .midnight:
            // Dark cinema acoustic panels.
            for n in -8...8 { box(Double(n)*0.86,0.2,10.64,0.12,5.3,0.14,p.caseEdge) }
        case .vintage70:
            // Walnut cabinetry and a row of warm globe-like lamp housings.
            for n in -2...2 { box(Double(n)*2.7,3.55,8.1,0.72,0.32,0.72,p.accent) }
        case .artDeco:
            // Tiered pilasters and thin brass bands.
            for side in [-1.0,1.0] {
                for n in 0..<3 { box(side*(6.6+Double(n)*0.34),0.4,8.8,0.13,5.5-Double(n)*0.7,0.27,p.accent) }
            }
        case .zen:
            // Oak vertical slats with restrained framing.
            for n in -8...8 { box(Double(n)*0.9,0.15,10.62,0.14,5.4,0.12,p.wood) }
        case .future:
            // Light guides in perspective, hanging technological rails.
            for side in [-1.0,1.0] {
                box(side*5.4,3.45,7.5,0.09,0.12,4.8,p.accent)
                box(side*6.4,3.45,7.9,0.13,0.18,3.6,p.second)
            }
        }
        return result
    }
}
