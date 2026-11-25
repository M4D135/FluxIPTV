import CoreGraphics
import CoreText
import Foundation
import QuartzCore
import SceneKit

/// Physical slipcase containing a bounded row of individual season cases.
/// The front (+z) shows their labelled spines; the back (-z) accepts the normal
/// synopsis texture and its live trailer overlay from the owning case scene.
@MainActor final class SeriesSeasonRack {
    let node = SCNNode()
    let backMaterial = SCNMaterial()
    var previewSurface: SCNNode { node }
    private(set) var halfWidth: Float = 1
    private(set) var halfHeight: Float = 1.5
    private(set) var halfDepth: Float = 1.3

    private struct Snapshot: Equatable {
        let indices: [Int]
        let numbers: [Int]
        let total: Int
        let format: CasePackageFormat
        let quality: CaseRenderQuality
        let theme: VideoClubTheme
        let artworkID: ObjectIdentifier?
    }
    private var snapshot: Snapshot?
    private var seasonNodes: [Int: SCNNode] = [:]
    private var hitIndices: [ObjectIdentifier: Int] = [:]
    private var previousSelection: Int?

    init() {
        node.name = "series-season-rack"
        backMaterial.lightingModel = .physicallyBased
        backMaterial.roughness.contents = 0.48
        backMaterial.diffuse.contents = CGColor(gray: 0.08, alpha: 1)
        backMaterial.isDoubleSided = false
    }

    func update(seasonNumbers: [Int], selectedIndex: Int, format: CasePackageFormat,
                artwork: CGImage?, motion: Bool, theme: VideoClubTheme,
                quality: CaseRenderQuality = .balanced) {
        let layout = SeriesSeasonRackLayout(seasonNumbers: seasonNumbers, selectedIndex: selectedIndex, format: format)
        halfWidth = layout.halfWidth
        halfHeight = layout.halfHeight
        halfDepth = layout.halfDepth
        node.isHidden = layout.slots.isEmpty
        let next = Snapshot(indices: layout.slots.map(\.index), numbers: layout.slots.map(\.seasonNumber),
                            total: seasonNumbers.count, format: format, quality: quality, theme: theme,
                            artworkID: artwork.map { ObjectIdentifier($0) })
        let rebuild = snapshot != next
        if rebuild {
            // Only season count/window, artwork, quality, format or theme can
            // rebuild geometry. Ordinary rotation and selection reuse it.
            node.childNodes.forEach { $0.removeFromParentNode() }
            seasonNodes.removeAll(keepingCapacity: true)
            hitIndices.removeAll(keepingCapacity: true)
            snapshot = next
            if !layout.slots.isEmpty { build(layout: layout, format: format, artwork: artwork, theme: theme, quality: quality) }
        }

        let animate = !rebuild && motion && previousSelection != nil && previousSelection != layout.selectedIndex
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animate ? 0.18 : 0
        SCNTransaction.disableActions = !animate
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        for slot in layout.slots {
            seasonNodes[slot.index]?.position = SCNVector3(slot.x, 0, slot.z)
        }
        SCNTransaction.commit()
        previousSelection = layout.selectedIndex
    }

    /// Returns the original array index, including for bevels and child labels.
    func seasonIndex(for hitNode: SCNNode) -> Int? {
        var current: SCNNode? = hitNode
        while let candidate = current, candidate !== node {
            if let index = hitIndices[ObjectIdentifier(candidate)] { return index }
            current = candidate.parent
        }
        return nil
    }

    private func build(layout: SeriesSeasonRackLayout, format: CasePackageFormat,
                       artwork: CGImage?, theme: VideoClubTheme, quality: CaseRenderQuality) {
        let colors = theme.palette
        let shell = material(color: color(colors.caseEdge * 0.48), roughness: 0.62)
        let lining = material(color: CGColor(gray: 0.035, alpha: 1), roughness: 0.76)
        let accent = material(color: color(colors.accent * 0.72), roughness: 0.44)
        let cover = material(image: coverTexture(artwork: artwork, format: format, theme: theme, quality: quality), roughness: 0.38)
        let plastic = material(color: CGColor(gray: format == .vhs ? 0.025 : 0.055, alpha: 1), roughness: 0.40)
        let h = layout.halfHeight, w = layout.halfWidth, d = layout.halfDepth
        let wall = layout.wall
        let shellDepth = layout.caseDepth + wall + layout.clearance + 0.025
        let shellZ = -d + shellDepth / 2
        let shellFrontZ = -d + shellDepth

        box(name: "rack-back-board", width: 2*w, height: 2*h, length: wall,
            position: SCNVector3(0, 0, -d + wall/2), material: shell)
        box(name: "rack-left-wall", width: wall, height: 2*h, length: shellDepth,
            position: SCNVector3(-w + wall/2, 0, shellZ), material: shell)
        box(name: "rack-right-wall", width: wall, height: 2*h, length: shellDepth,
            position: SCNVector3(w - wall/2, 0, shellZ), material: shell)
        box(name: "rack-floor", width: 2*w - 2*wall, height: wall, length: shellDepth,
            position: SCNVector3(0, -h + wall/2, shellZ), material: lining)
        box(name: "rack-roof", width: 2*w - 2*wall, height: wall, length: shellDepth,
            position: SCNVector3(0, h - wall/2, shellZ), material: shell)
        box(name: "rack-top-print-rule", width: 2*w, height: 0.022, length: 0.018,
            position: SCNVector3(0, h - 0.027, shellFrontZ), material: accent)

        let back = SCNNode(geometry: printedPlane(width:2*(w-format.bevel),height:2*(h-format.bevel)))
        back.name = "rack-printed-back"
        back.geometry?.materials = [backMaterial]
        back.position = SCNVector3(0, 0, -d - 0.002)
        back.eulerAngles.y = .pi
        node.addChildNode(back)

        // The slipcase side uses only the supplied series artwork; a missing
        // image produces a quiet printed cover with a format label.
        for side in [Float(-1), Float(1)] {
            let sideCover = SCNNode(geometry: SCNPlane(width: CGFloat(shellDepth - 2*format.bevel), height: CGFloat(2*(h-format.bevel))))
            sideCover.name = "rack-side-cover"
            sideCover.geometry?.materials = [cover]
            sideCover.position = SCNVector3(side * (w + 0.002), 0, shellZ)
            sideCover.eulerAngles = SCNVector3(0,side * Float.pi / 2,0)
            node.addChildNode(sideCover)
        }

        let mesh = ProceduralCase.premiumMesh(cornerSegments: quality.cornerSegments, format: format)
        let template = geometry(mesh)
        for slot in layout.slots {
            let spine = material(image: spineTexture(season: slot.seasonNumber, artwork: artwork, format: format, theme: theme,
                                                     height: quality == .economy ? 512 : 768), roughness: 0.46)
            let seasonGeometry = SCNGeometry(sources: template.sources, elements: template.elements)
            seasonGeometry.materials = [cover, cover, plastic, spine]
            let season = SCNNode(geometry: seasonGeometry)
            season.name = "rack-season-\(slot.index)"
            season.eulerAngles.y = .pi / 2
            season.scale = SCNVector3(layout.caseScale, layout.caseScale, layout.caseScale)
            season.position = SCNVector3(slot.x, 0, slot.z)
            node.addChildNode(season)
            seasonNodes[slot.index] = season
            hitIndices[ObjectIdentifier(season)] = slot.index
        }

        let footer = SCNNode(geometry: SCNPlane(width: CGFloat(2*w - 0.055), height: 0.12))
        footer.name = "rack-season-range"
        footer.geometry?.materials = [material(image: rangeTexture(layout: layout, format: format), roughness: 0.68)]
        footer.position = SCNVector3(0, -h + 0.073, shellFrontZ + 0.012)
        node.addChildNode(footer)
    }

    /// Explicit top-left UVs match the synopsis layout, projection and picking.
    private func printedPlane(width:Float,height:Float)->SCNGeometry {
        let w=width/2,h=height/2
        let points=[SCNVector3(-w,h,0),SCNVector3(w,h,0),SCNVector3(w,-h,0),SCNVector3(-w,-h,0)]
        let normals=Array(repeating:SCNVector3(0,0,1),count:4)
        let uvs=[CGPoint(x:0,y:0),CGPoint(x:1,y:0),CGPoint(x:1,y:1),CGPoint(x:0,y:1)]
        let indices:[UInt32]=[0,3,2,0,2,1]
        let element=SCNGeometryElement(data:indices.withUnsafeBytes{Data($0)},primitiveType:.triangles,primitiveCount:2,bytesPerIndex:4)
        return SCNGeometry(sources:[SCNGeometrySource(vertices:points),SCNGeometrySource(normals:normals),SCNGeometrySource(textureCoordinates:uvs)],elements:[element])
    }

    private func box(name: String, width: Float, height: Float, length: Float,
                     position: SCNVector3, material: SCNMaterial) {
        let geometry = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0.009)
        geometry.chamferSegmentCount = 2
        geometry.materials = [material]
        let child = SCNNode(geometry: geometry)
        child.name = name
        child.position = position
        node.addChildNode(child)
    }

    private func material(color: CGColor, roughness: Double) -> SCNMaterial {
        let value = SCNMaterial()
        value.lightingModel = .physicallyBased
        value.diffuse.contents = color
        value.roughness.contents = roughness
        value.metalness.contents = 0
        value.isDoubleSided = false
        return value
    }

    private func material(image: CGImage?, roughness: Double) -> SCNMaterial {
        let value = material(color: CGColor(gray: 0.13, alpha: 1), roughness: roughness)
        if let image { value.diffuse.contents = image }
        return value
    }

    private func color(_ value: VideoClubTheme.V) -> CGColor {
        CGColor(red: CGFloat(value.x), green: CGFloat(value.y), blue: CGFloat(value.z), alpha: 1)
    }

    private func geometry(_ mesh: [ProceduralCase.Triangle]) -> SCNGeometry {
        var points: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = []
        var elements: [SCNGeometryElement] = []
        for surface in ProceduralCase.Surface.allCases {
            var indices: [UInt32] = []
            for triangle in mesh where triangle.surface == surface {
                for vertex in triangle.vertices {
                    indices.append(UInt32(points.count))
                    points.append(SCNVector3(vertex.position.x, vertex.position.y, vertex.position.z))
                    normals.append(SCNVector3(vertex.normal.x, vertex.normal.y, vertex.normal.z))
                    // On the left spine, increasing local z becomes increasing
                    // screen x after the quarter-turn that presents the row.
                    let u = surface == .spine ? 1-vertex.uv.x : vertex.uv.x
                    uvs.append(CGPoint(x: CGFloat(u), y: CGFloat(vertex.uv.y)))
                }
            }
            elements.append(SCNGeometryElement(data: indices.withUnsafeBytes { Data($0) }, primitiveType: .triangles,
                                               primitiveCount: indices.count/3, bytesPerIndex: 4))
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: points), SCNGeometrySource(normals: normals),
                                     SCNGeometrySource(textureCoordinates: uvs)], elements: elements)
    }

    private func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private func drawText(_ string: String, size: CGFloat, center: CGPoint, color: CGColor, in context: CGContext) {
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
        let text = NSAttributedString(string: string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ])
        let line = CTLineCreateWithAttributedString(text)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textPosition = CGPoint(x: center.x - width/2, y: center.y - size*0.34)
        CTLineDraw(line, context)
    }

    private func drawArtwork(_ artwork: CGImage, in rect: CGRect, context: CGContext) {
        let scale = min(rect.width/CGFloat(artwork.width), rect.height/CGFloat(artwork.height))
        let size = CGSize(width: CGFloat(artwork.width)*scale, height: CGFloat(artwork.height)*scale)
        context.saveGState()
        context.clip(to: rect)
        context.interpolationQuality = .high
        context.draw(artwork, in: CGRect(x: rect.midX-size.width/2, y: rect.midY-size.height/2, width: size.width, height: size.height))
        context.restoreGState()
    }

    private func coverTexture(artwork: CGImage?, format: CasePackageFormat, theme: VideoClubTheme, quality: CaseRenderQuality) -> CGImage? {
        let height = quality == .economy ? 512 : 768
        let width = Int(Float(height)*format.faceWidth/format.faceHeight)
        guard let c = context(width: width, height: height) else { return nil }
        let w = CGFloat(width), h = CGFloat(height)
        c.setFillColor(color(theme.palette.wall * 0.32))
        c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if let artwork { drawArtwork(artwork, in: CGRect(x: 8, y: 36, width: w-16, height: h-72), context: c) }
        drawText("COFFRET · \(format.title)", size: 18, center: CGPoint(x: w/2, y: 18), color: CGColor(gray: 0.92, alpha: 1), in: c)
        return c.makeImage()
    }

    private func spineTexture(season: Int, artwork: CGImage?, format: CasePackageFormat, theme: VideoClubTheme, height: Int) -> CGImage? {
        guard let c = context(width: 128, height: height) else { return nil }
        c.scaleBy(x: 1, y: CGFloat(height)/768)
        let dark = CGColor(gray: 0.10, alpha: 1)
        c.setFillColor(CGColor(red: 0.85, green: 0.86, blue: 0.83, alpha: 1))
        c.fill(CGRect(x: 0, y: 0, width: 128, height: 768))
        c.setFillColor(color(theme.palette.accent * 0.65))
        c.fill(CGRect(x: 0, y: 750, width: 128, height: 18))
        c.fill(CGRect(x: 4, y: 4, width: 3, height: 742))
        drawText(format.title, size: 24, center: CGPoint(x: 64, y: 711), color: dark, in: c)
        let number = String(season)
        drawText(number, size: number.count > 2 ? 36 : 54, center: CGPoint(x: 64, y: 640), color: dark, in: c)
        c.saveGState()
        c.translateBy(x: 66, y: 405)
        c.rotate(by: -.pi/2)
        drawText(season == 0 ? "SPÉCIAUX" : "SAISON \(season)", size: 35, center: .zero, color: dark, in: c)
        c.restoreGState()
        if let artwork { drawArtwork(artwork, in: CGRect(x: 12, y: 39, width: 104, height: 166), context: c) }
        drawText("FLUX", size: 17, center: CGPoint(x: 64, y: 20), color: dark, in: c)
        return c.makeImage()
    }

    private func rangeTexture(layout: SeriesSeasonRackLayout, format: CasePackageFormat) -> CGImage? {
        guard let c = context(width: 1024, height: 64) else { return nil }
        c.setFillColor(CGColor(gray: 0.035, alpha: 1))
        c.fill(CGRect(x: 0, y: 0, width: 1024, height: 64))
        let label: String
        if layout.totalCount > layout.slots.count {
            label = "\(format.title) · \(layout.visibleRange.lowerBound+1)–\(layout.visibleRange.upperBound) / \(layout.totalCount) SAISONS"
        } else {
            label = "COFFRET \(format.title) · \(layout.totalCount) \(layout.totalCount == 1 ? "SAISON" : "SAISONS")"
        }
        drawText(label, size: 27, center: CGPoint(x: 512, y: 32), color: CGColor(gray: 0.92, alpha: 1), in: c)
        return c.makeImage()
    }
}
