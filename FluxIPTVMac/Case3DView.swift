import SwiftUI
import AVFoundation
import SceneKit
import CoreText
import CoreGraphics
#if os(macOS)
import AppKit
private typealias CaseColor = NSColor
#else
import UIKit
private typealias CaseColor = UIColor
#endif

/// The sleeve keeps complete front artwork. Back preview/description panels
/// and the collector episode tray share UV layouts with native hit testing.
struct CasePrintData: Equatable, Sendable {
    var page: CaseFaceLayout.Page = .details
    var episodes: [IPTVItem] = []
    var season: Int? = nil
    var pageIndex = 0
    var pageCount = 1
    var status: String? = nil
    var retry = false
    var favorite = false
    var position = 0
    var count = 0
    var trailerAvailable = false
    var episodeProgress: [String:Double] = [:]
    var descriptionText: String? = nil
    var previewStatus = ""
}

@MainActor final class CaseHitBridge: ObservableObject {
    var pick: ((CGPoint) -> (ProceduralCase.Surface, CGPoint)?)?
    var pickNeighbor: ((CGPoint) -> Int?)?
    @Published var previewProjection: CasePreviewProjection?
    @Published var previewBackFacing = false
    @Published var previewContentUVFrame = CaseBackMediaLayout.frame
}

struct Case3DView: View {
    let item: IPTVItem
    let details: IPTVDetails
    let printData: CasePrintData
    let focused: CaseFaceLayout.Action?
    let yaw: Double
    let pitch: Double
    let motion: Bool
    let bridge: CaseHitBridge
    let padInput: (CasePadInput) -> Void
    let padEnabled: Bool
    var previousItem: IPTVItem? = nil
    var nextItem: IPTVItem? = nil
    var previousFarItem: IPTVItem? = nil
    var nextFarItem: IPTVItem? = nil
    var selectedTheme: VideoClubTheme? = nil
    var previewStill: CGImage? = nil
    var previewPlayer: AVPlayer? = nil
    var previewPlaying = false
    var concept: ClubInterfaceProfile = .neoVideoClub
    @State private var neighborArt: [String:FluxBitmap] = [:]
    @AppStorage(MediaThemePreferences.cinemaKey) private var cinemaTheme: VideoClubTheme = .neo90
    @AppStorage(MediaThemePreferences.seriesKey) private var seriesTheme: VideoClubTheme = .neo90
    private var theme:VideoClubTheme {selectedTheme ?? (item.kind == .series ? seriesTheme:cinemaTheme)}
    @AppStorage("fluxiptv.appearance.caseQuality") private var quality: CaseRenderQuality = .balanced
    @AppStorage(FluxAppearance.artworkKey) private var artwork = true
    @State private var bitmap: FluxBitmap?
    @State private var bitmapURL: URL?
    @State private var episodeArt: [String:FluxBitmap] = [:]
    private var artID: String { (artwork ? (item.logoURL?.absoluteString ?? "") : "") + "|" + quality.rawValue }
    private var episodeKey: String { artwork && printData.page == .episodes ? printData.episodes.map(\.id).joined(separator:"|") : "" }
    private var neighborItems:[IPTVItem] {[previousItem,nextItem,previousFarItem,nextFarItem].compactMap{$0}}
    private var neighborKey: String { neighborItems.map{$0.id+"="+($0.logoURL?.absoluteString ?? "")}.joined(separator:"|")+"|"+String(artwork) }
    private var leftArtwork:CGImage? { artwork ? previousItem.flatMap{neighborArt[$0.id]?.image}:nil }
    private var rightArtwork:CGImage? { artwork ? nextItem.flatMap{neighborArt[$0.id]?.image}:nil }
    private var farLeftArtwork:CGImage? { artwork ? previousFarItem.flatMap{neighborArt[$0.id]?.image}:nil }
    private var farRightArtwork:CGImage? { artwork ? nextFarItem.flatMap{neighborArt[$0.id]?.image}:nil }
    var body: some View {
        CaseSceneSurface(item:item,details:details,printData:printData,artwork:artwork && bitmapURL == item.logoURL ? bitmap?.image:nil,episodeArt:episodeArt,focused:focused,yaw:yaw,pitch:pitch,motion:motion,theme:theme,quality:quality,bridge:bridge,padInput:padInput,padEnabled:padEnabled,previousItem:previousItem,nextItem:nextItem,previousFarItem:previousFarItem,nextFarItem:nextFarItem,leftArtwork:leftArtwork,rightArtwork:rightArtwork,farLeftArtwork:farLeftArtwork,farRightArtwork:farRightArtwork,previewStill:previewStill,previewPlayer:previewPlayer,previewPlaying:previewPlaying,concept:concept)
            .task(id:artID) {
                guard artwork,let url=item.logoURL else {bitmap=nil;bitmapURL=nil;return}
                bitmap=ArtworkLoader.cached(url,caseHD:true) ?? ArtworkLoader.cached(url)
                bitmapURL=url
                if quality != .economy && ArtworkLoader.cached(url,caseHD:true) == nil {
                    try? await Task.sleep(nanoseconds:180_000_000)
                    guard !Task.isCancelled else{return}
                    let loaded=await ArtworkLoader.load(url,caseHD:true)
                    guard !Task.isCancelled else{return};if let loaded {bitmap=loaded;bitmapURL=url}
                } else if bitmap == nil {
                    let loaded=await ArtworkLoader.load(url)
                    guard !Task.isCancelled else{return};bitmap=loaded;bitmapURL=url
                }
            }
            .task(id:episodeKey) {
                episodeArt=[:]
                guard !episodeKey.isEmpty else{return}
                let entries=printData.episodes
                let cached=Dictionary(entries.compactMap{ entry in entry.logoURL.flatMap{ArtworkLoader.cached($0)}.map{(entry.id,$0)} },uniquingKeysWith:{first,_ in first})
                episodeArt=cached
                let loaded=await withTaskGroup(of:(String,FluxBitmap?).self,returning:[String:FluxBitmap].self) { group in
                    for entry in entries where cached[entry.id] == nil {if let url=entry.logoURL {group.addTask { (entry.id,await ArtworkLoader.load(url)) }}}
                    var all=cached
                    for await (id,art) in group {if let art {all[id]=art}}
                    return all
                }
                guard !Task.isCancelled else{return};episodeArt=loaded
            }
            .task(id:neighborKey) {
                guard artwork else {neighborArt=[:];return}
                let items=neighborItems
                var images=Dictionary(items.compactMap{item in item.logoURL.flatMap{ArtworkLoader.cached($0)}.map{(item.id,$0)}},uniquingKeysWith:{first,_ in first})
                neighborArt=images
                for item in items where images[item.id] == nil {
                    if let url=item.logoURL,let image=await ArtworkLoader.load(url) {images[item.id]=image}
                    guard !Task.isCancelled else{return}
                }
                guard !Task.isCancelled else{return};neighborArt=images
            }
            .accessibilityHidden(true)
    }
}

private enum SleeveTexture {
    static func context(_ w:Int,_ h:Int)->CGContext? {
        CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)
    }
    private static func ink(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat,_ a:CGFloat=1)->CGColor {CGColor(red:r,green:g,blue:b,alpha:a)}
    static func normalMap()->CGImage? {
        let size=128,bytes=ProceduralCase.grainNormalMap(size:size)
        guard let provider=CGDataProvider(data:Data(bytes) as CFData) else{return nil}
        return CGImage(width:size,height:size,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:size*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.noneSkipLast.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)
    }
    /// Static, synthetic light probe: broad softboxes and coloured rim lights.
    /// A tiny environment texture feeds PBR reflections; no cubemap capture per frame.
    static func environment(_ theme:VideoClubTheme)->CGImage? {
        let w=256,h=128;guard let c=context(w,h) else{return nil}
        let a=theme.palette.accent,b=theme.palette.second
        c.setFillColor(ink(0.13,0.15,0.19));c.fill(CGRect(x:0,y:0,width:w,height:h))
        func softbox(_ center:CGPoint,_ radius:CGFloat,_ color:CGColor) {
            guard let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[color,ink(0.1,0.11,0.14,0)] as CFArray,locations:[0,1]) else{return}
            c.drawRadialGradient(g,startCenter:center,startRadius:0,endCenter:center,endRadius:radius,options:[])
        }
        softbox(CGPoint(x:72,y:96),58,ink(1,0.98,0.91))
        softbox(CGPoint(x:192,y:72),43,ink(CGFloat(a.x),CGFloat(a.y),CGFloat(a.z)))
        softbox(CGPoint(x:237,y:27),42,ink(CGFloat(b.x),CGFloat(b.y),CGFloat(b.z)))
        c.setFillColor(ink(0.94,0.97,1,0.84));c.fill(CGRect(x:62,y:83,width:27,height:31))
        return c.makeImage()
    }
    static func focusTexture()->CGImage? {
        // A fine high-resolution rim remains a hairline when the same material
        // is stretched onto the description panel; it must never cover its text.
        guard let c=context(1024,512) else{return nil}
        c.setStrokeColor(ink(0.46,0.96,1,0.88));c.setLineWidth(3)
        c.addPath(CGPath(roundedRect:CGRect(x:3,y:3,width:1018,height:506),cornerWidth:20,cornerHeight:20,transform:nil));c.strokePath()
        return c.makeImage()
    }
    static func shadowTexture()->CGImage? {
        guard let c=context(128,128),let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[ink(0,0,0,0.7),ink(0,0,0,0.35),ink(0,0,0,0)] as CFArray,locations:[0,0.55,1]) else{return nil}
        c.drawRadialGradient(g,startCenter:CGPoint(x:64,y:64),startRadius:8,endCenter:CGPoint(x:64,y:64),endRadius:64,options:[])
        return c.makeImage()
    }
    static func render(item:IPTVItem,details:IPTVDetails,page:CaseFaceLayout.Page,data:CasePrintData,artwork:FluxBitmap?,episodeArt:[String:FluxBitmap],theme:VideoClubTheme,quality:CaseRenderQuality,surfaceAspect:Double?=nil)->CGImage? {
        let format=CasePackageFormat.resolve(year:details.year ?? item.details.year)
        let aspect=surfaceAspect ?? Double(format.faceWidth/format.faceHeight)
        // Fit the physical sleeve ratio inside the existing texture budget.
        // The supplied artwork keeps its proportions on both DVD and VHS.
        let width=min(quality.sleeveWidth,Int(Double(quality.sleeveHeight)*aspect))
        let height=min(quality.sleeveHeight,Int(Double(width)/aspect))
        guard let c=context(width,height) else{return nil}
        let w=CGFloat(width),h=CGFloat(height)
        let W:CGFloat=1024,H:CGFloat=1024/CGFloat(aspect)
        c.scaleBy(x:w/W,y:h/H)
        let accent=theme.palette.accent
        let gold=ink(CGFloat(accent.x),CGFloat(accent.y),CGFloat(accent.z))
        let white=ink(0.95,0.96,0.98),muted=ink(0.72,0.77,0.84)
        func box(_ r:CGRect)->CGRect {CGRect(x:r.minX*W,y:(1-r.maxY)*H,width:r.width*W,height:r.height*H)}
        func fill(_ r:CGRect,_ color:CGColor) {c.setFillColor(color);c.fill(box(r))}
        func text(_ value:String,_ size:CGFloat,_ r:CGRect,_ color:CGColor=CGColor(gray:1,alpha:1),bold:Bool=false,center:Bool=false) {
            let rect=box(r);guard !value.isEmpty,rect.width>0,rect.height>0 else{return}
            let font=CTFontCreateWithName((bold ? "HelveticaNeue-Bold":"HelveticaNeue") as CFString,size,nil)
            let attr=NSAttributedString(string:value,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):color])
            if center {
                let line=CTLineCreateWithAttributedString(attr)
                let trunc=CTLineCreateTruncatedLine(line,Double(rect.width-14),.end,nil) ?? line
                let measured=CGFloat(CTLineGetTypographicBounds(trunc,nil,nil,nil))
                c.textPosition=CGPoint(x:rect.midX-measured/2,y:rect.midY-size*0.33);CTLineDraw(trunc,c)
            } else {
                let frame=CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attr),CFRange(location:0,length:0),CGPath(rect:rect,transform:nil),nil)
                CTFrameDraw(frame,c)
            }
        }
        func image(_ image:CGImage,_ r:CGRect,fit:Bool=false) {
            let rect=box(r),scale=fit ? min(rect.width/CGFloat(image.width),rect.height/CGFloat(image.height)):max(rect.width/CGFloat(image.width),rect.height/CGFloat(image.height))
            let iw=CGFloat(image.width)*scale,ih=CGFloat(image.height)*scale
            c.saveGState();c.clip(to:rect);c.interpolationQuality = .high
            c.draw(image,in:CGRect(x:rect.midX-iw/2,y:rect.midY-ih/2,width:iw,height:ih));c.restoreGState()
        }
        let bg=theme.palette.wall
        let colors=[ink(CGFloat(bg.x)*0.62+0.035,CGFloat(bg.y)*0.62+0.035,CGFloat(bg.z)*0.62+0.045),ink(0.014,0.021,0.037)] as CFArray
        if let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1]) {c.drawLinearGradient(g,start:CGPoint(x:0,y:H),end:.zero,options:[])}
        // Printed gold/cyan hairlines and series-specific label. These are ink, not overlays.
        if page != .front {
            fill(CGRect(x:0.025,y:0.018,width:0.95,height:0.002),gold)
            text((item.isSeriesCollection ? data.season.map{"SÉRIE · SAISON \($0)"} ?? "SÉRIE":"CINÉMA")+"  /  "+format.title,24,CGRect(x:0.04,y:0.025,width:0.92,height:0.027),gold,bold:true)
        }
        let metadata=[details.year,details.duration,details.rating,details.genre].compactMap{$0}.filter{ !$0.isEmpty }.joined(separator:"  •  ")
        if page == .front {
            // Preserve the full supplied artwork, including any original lettering.
            if let artwork { image(artwork.image,CGRect(x:0,y:0,width:1,height:1),fit:true) }
            else {text(item.name,74,CGRect(x:0.07,y:0.30,width:0.86,height:0.40),white,bold:true)}
            return c.makeImage()
        } else if page == .details {
            let previewRect=CaseBackMediaLayout.frame
            fill(previewRect,ink(0.008,0.012,0.020))
            text(data.previewStatus.isEmpty ? "APERÇU":data.previewStatus,23,previewRect,muted,center:true)
            c.setStrokeColor(ink(0.47,0.53,0.61,0.7));c.setLineWidth(2);c.stroke(box(previewRect))
            let filmTitle=item.isSeriesCollection ? (data.page == .episodes ? "▶  LIRE L’ÉPISODE":"▸  VOIR LES ÉPISODES"):"▶  REGARDER LE FILM"
            for (rect,title) in [(CaseBackMediaLayout.trailer,"↑  BANDE-ANNONCE"),(CaseBackMediaLayout.film,filmTitle)] {
                c.setFillColor(ink(0.14,0.18,0.24));c.addPath(CGPath(roundedRect:box(rect),cornerWidth:13,cornerHeight:13,transform:nil));c.fillPath()
                text(title,23,rect,white,bold:true,center:true)
            }
            text(String(item.name.prefix(110)),44,CGRect(x:0.04,y:0.485,width:0.92,height:0.084),white,bold:true)
            text(metadata.isEmpty ? item.group:metadata,23,CGRect(x:0.04,y:0.574,width:0.92,height:0.042),gold,bold:true)
            let descriptionRect=CaseBackMediaLayout.descriptionFrame
            c.setFillColor(ink(0.055,0.074,0.10));c.addPath(CGPath(roundedRect:box(descriptionRect),cornerWidth:18,cornerHeight:18,transform:nil));c.fillPath()
            c.setStrokeColor(ink(0.38,0.45,0.54,0.72));c.setLineWidth(1.8);c.addPath(CGPath(roundedRect:box(descriptionRect),cornerWidth:18,cornerHeight:18,transform:nil));c.strokePath()
            text("DESCRIPTION",23,CGRect(x:0.13,y:0.64,width:0.74,height:0.033),gold,bold:true,center:true)
            let description=(data.descriptionText ?? details.synopsis ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
            let descriptionBody=description.isEmpty ? "Le fournisseur IPTV n’a pas communiqué de description.":description
            text(String(descriptionBody.prefix(880))+(descriptionBody.count>880 ? "…":""),descriptionBody.count>520 ? 22:26,CGRect(x:0.062,y:0.686,width:0.876,height:0.178),white)
            if let director=details.director {text("RÉALISATION  /  "+String(director.prefix(130)),20,CGRect(x:0.04,y:0.919,width:0.92,height:0.028),muted)}
            if let cast=details.cast {text("DISTRIBUTION  /  "+String(cast.prefix(180)),20,CGRect(x:0.04,y:0.953,width:0.92,height:0.038),muted)}
        } else {
            text(String(item.name.prefix(100)),42,CGRect(x:0.04,y:0.062,width:0.92,height:0.08),white,bold:true)
            text(data.season.map{"SAISON \($0)"} ?? "ÉPISODES",28,CGRect(x:0.27,y:0.16,width:0.46,height:0.05),gold,bold:true,center:true)
            if let status=data.status {text(status,30,CGRect(x:0.04,y:0.29,width:0.92,height:0.13),muted,center:true)}
            text("\(data.pageIndex+1) / \(max(1,data.pageCount))",24,CGRect(x:0.30,y:0.78,width:0.40,height:0.06),gold,center:true)
        }
        let regions=CaseFaceLayout.regions(page,series:item.isSeriesCollection,trailer:data.trailerAvailable,episodeCount:data.episodes.count,retry:data.retry)
        func label(_ action:CaseFaceLayout.Action)->String {
            switch action {
            case .play:return "▶   REGARDER"
            case .episodes:return "▸   ÉPISODES"
            case .favorite:return data.favorite ? "★   FAVORI":"☆   FAVORI"
            case .flip:return page == .front ? "↻   VOIR LE VERSO":"↻   VOIR LE RECTO"
            case .rotate:return "360°"
            case .trailer:return "▶ BANDE-ANNONCE"
            case .previous:return "‹  PRÉC."
            case .next:return "SUIV.  ›"
            case .close:return "REPOSER   \(data.position+1)/\(max(1,data.count))"
            case .previousSeason,.previousPage:return "‹"
            case .nextSeason,.nextPage:return "›"
            case .details:return "‹  FICHE CINÉMA"
            case .description:return "DESCRIPTION"
            case .retry:return "RÉESSAYER"
            case .episode:return ""
            }
        }
        for region in regions {
            // Only episode content cards are part of the physical sleeve.
            guard case .episode = region.action else {continue}
            let r=region.rect,rect=box(r),primary=region.action == .play || region.action == .episodes
            c.setFillColor(primary ? ink(CGFloat(accent.x)*0.30,CGFloat(accent.y)*0.30,CGFloat(accent.z)*0.30):ink(0.10,0.14,0.20,0.95))
            let path=CGPath(roundedRect:rect,cornerWidth:13,cornerHeight:13,transform:nil)
            c.addPath(path);c.fillPath();c.setStrokeColor(primary ? gold:ink(0.40,0.48,0.58,0.66));c.setLineWidth(primary ? 2.8:1.4);c.addPath(path);c.strokePath()
            if case let .episode(index)=region.action,data.episodes.indices.contains(index) {
                let ep=data.episodes[index],thumb=CGRect(x:r.minX+0.011,y:r.minY+0.009,width:0.235,height:r.height-0.018)
                if let art=episodeArt[ep.id] ?? artwork {image(art.image,thumb)} else {fill(thumb,ink(0.16,0.21,0.30));text("▶",40,thumb,gold,center:true)}
                let badge=String(format:"S%02d  E%02d",ep.seasonNumber ?? data.season ?? 0,ep.episodeNumber ?? index+1)
                text(badge,23,CGRect(x:r.minX+0.26,y:r.minY+0.011,width:0.64,height:0.024),gold,bold:true)
                let progress=max(0,min(1,data.episodeProgress[ep.id] ?? 0))
                text(String(ep.name.prefix(100)),29,CGRect(x:r.minX+0.26,y:r.minY+0.041,width:0.64,height:0.062),white,bold:true)
                if progress > 0 {
                    fill(CGRect(x:r.minX+0.26,y:r.maxY-0.012,width:0.64,height:0.004),ink(0.28,0.31,0.35))
                    fill(CGRect(x:r.minX+0.26,y:r.maxY-0.012,width:0.64*progress,height:0.004),gold)
                }
            } else {text(label(region.action),primary ? 32:24,r,primary ? gold:white,bold:true,center:true)}
        }
        return c.makeImage()
    }
    static func spine(item:IPTVItem,format:CasePackageFormat,theme:VideoClubTheme)->CGImage? {
        guard let c=context(160,1536) else{return nil}
        let color=theme.palette.caseEdge
        c.setFillColor(ink(CGFloat(color.x),CGFloat(color.y),CGFloat(color.z)));c.fill(CGRect(x:0,y:0,width:160,height:1536))
        c.setFillColor(ink(0.75,0.79,0.83,0.45));c.fill(CGRect(x:12,y:22,width:136,height:4));c.fill(CGRect(x:12,y:1510,width:136,height:4))
        let badgeFont=CTFontCreateWithName("HelveticaNeue-Bold" as CFString,36,nil)
        let badge=NSAttributedString(string:format.title,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):badgeFont,NSAttributedString.Key(kCTForegroundColorAttributeName as String):ink(0.96,0.97,0.99)])
        let badgeLine=CTLineCreateWithAttributedString(badge)
        c.textPosition=CGPoint(x:(160-CGFloat(CTLineGetTypographicBounds(badgeLine,nil,nil,nil)))/2,y:58);CTLineDraw(badgeLine,c)
        c.saveGState();c.translateBy(x:80,y:1490);c.rotate(by:-.pi/2)
        let font=CTFontCreateWithName("HelveticaNeue-Bold" as CFString,48,nil)
        let str=NSAttributedString(string:String(item.name.prefix(80)),attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):ink(0.98,0.98,0.98)])
        let line=CTLineCreateWithAttributedString(str),truncated=CTLineCreateTruncatedLine(line,1320,.end,nil) ?? line
        c.textPosition=CGPoint(x:0,y:-17);CTLineDraw(truncated,c);c.restoreGState()
        return c.makeImage()
    }
}

/// Native gesture surface. The AppKit local monitor receives scroll events
/// before SwiftUI's transparent hit-test overlay or the hidden catalogue.
@MainActor private final class CaseMetalView: SCNView {
    var resized: ((CGSize)->Void)?
    var padInput: ((CasePadInput)->Void)?
    var padEnabled=false {
        didSet {
            #if os(tvOS)
            remotePan?.isEnabled=padEnabled
            #endif
        }
    }
    private var lastSize=CGSize.zero
    private func sizeChanged() {
        if lastSize != bounds.size {lastSize=bounds.size;resized?(lastSize)}
    }
    #if os(macOS)
    private var scrollMonitor:Any?
    private var scrollActive=false
    private var ownsMomentum=false
    private var idleEnd:Task<Void,Never>?
    private var lastScrollTime:TimeInterval=0
    override func layout() {super.layout();sizeChanged()}
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removePadInput()
        guard window != nil else{return}
        scrollMonitor=NSEvent.addLocalMonitorForEvents(matching:.scrollWheel) { [weak self] event in
            guard let self else{return event}
            return self.routeScroll(event)
        }
    }
    private func routeScroll(_ event:NSEvent)->NSEvent? {
        guard padEnabled,let window,event.window === window,event.hasPreciseScrollingDeltas else{return event}
        // Consume only events belonging to this held-case surface. Never take
        // over a regular wheel or a scroll on the virtual remote side panel.
        let inside=bounds.contains(convert(event.locationInWindow,from:nil))
        if !event.momentumPhase.isEmpty {
            guard ownsMomentum else{return event}
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {ownsMomentum=false}
            // The model has its own bounded settling motion; native momentum
            // must not turn the case a second time after the fingers lift.
            return nil
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            if scrollActive {endScroll()}
            ownsMomentum=false
            guard inside else{return event}
            ownsMomentum=true
            if event.phase.contains(.mayBegin) {return nil}
        }
        guard inside || scrollActive else{ownsMomentum=false;return event}
        if event.phase.contains(.cancelled) {endScroll(cancelled:true);return nil}
        let dx=Double(event.scrollingDeltaX),dy = -Double(event.scrollingDeltaY)
        if dx != 0 || dy != 0 {
            scrollActive=true;ownsMomentum=true
            padInput?(.delta(dx,dy))
        }
        if event.phase.contains(.ended) {endScroll();return nil}
        if scrollActive {
            // Some precise devices send phase-less events; close their gesture
            // after inactivity, not with a repeating timer.
            lastScrollTime=ProcessInfo.processInfo.systemUptime
            if idleEnd == nil {
                idleEnd=Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds:100_000_000)
                        guard !Task.isCancelled,let self else{return}
                        if ProcessInfo.processInfo.systemUptime-self.lastScrollTime >= 0.18 {self.endScroll();return}
                    }
                }
            }
        }
        return nil
    }
    private func endScroll(cancelled:Bool=false) {
        idleEnd?.cancel();idleEnd=nil
        if scrollActive {scrollActive=false;padInput?(cancelled ? .cancel:.finish)}
    }
    func removePadInput() {
        if let scrollMonitor {NSEvent.removeMonitor(scrollMonitor);self.scrollMonitor=nil}
        // Do not mutate SwiftUI state when the representable is dismantled.
        idleEnd?.cancel();idleEnd=nil;scrollActive=false;ownsMomentum=false
    }
    #elseif os(tvOS)
    private weak var gestureWindow:UIWindow?
    private var remotePan:UIPanGestureRecognizer?
    override func layoutSubviews() {super.layoutSubviews();sizeChanged()}
    override func didMoveToWindow() {
        super.didMoveToWindow()
        removePadInput()
        guard let window else{return}
        // The SwiftUI focus button can be a sibling of the SCNView, so listen
        // on its window only while this single held object exists.
        let pan=UIPanGestureRecognizer(target:self,action:#selector(handleRemotePan(_:)))
        pan.allowedTouchTypes=[NSNumber(value:UITouch.TouchType.indirect.rawValue)]
        pan.allowedPressTypes=[]
        pan.cancelsTouchesInView=true
        pan.isEnabled=padEnabled
        gestureWindow=window;remotePan=pan;window.addGestureRecognizer(pan)
    }
    @objc private func handleRemotePan(_ pan:UIPanGestureRecognizer) {
        guard padEnabled,window === gestureWindow else{return}
        let t=pan.translation(in:self)
        switch pan.state {
        case .began,.changed:padInput?(.translation(Double(t.x),Double(t.y)))
        case .ended:padInput?(.finishTranslation(Double(t.x),Double(t.y)))
        case .cancelled,.failed:padInput?(.cancel)
        default:break
        }
    }
    func removePadInput() {
        if let remotePan {gestureWindow?.removeGestureRecognizer(remotePan)}
        remotePan=nil;gestureWindow=nil
    }
    #else
    override func layoutSubviews() {super.layoutSubviews();sizeChanged()}
    func removePadInput() {}
    #endif
}

/// Fitting happens after SceneKit applies the current animation pose. Keeping
/// this delegate independent of SwiftUI's actor also avoids publishing view
/// state from the render thread. Only this root changes; the camera and shelf
/// are immutable throughout a turn/open animation.
private final class CaseForegroundFramer: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    struct Bounds {
        let node: SCNNode
        let minimum: SCNVector3
        let maximum: SCNVector3
    }
    private struct Configuration {
        let distance: Double
        let aspect: Double
        let bounds: [Bounds]
    }
    private let root: SCNNode
    private let lock = NSLock()
    private var configuration: Configuration?

    init(root: SCNNode) { self.root = root; super.init() }

    func configure(distance: Double, aspect: Double, bounds: [Bounds]) {
        lock.lock()
        configuration = Configuration(distance: distance, aspect: aspect, bounds: bounds)
        lock.unlock()
    }
    func clear() { lock.lock(); configuration = nil; lock.unlock() }

    func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
        fit(presentation: true)
    }

    func fit(presentation: Bool) {
        lock.lock(); let value = configuration; lock.unlock()
        guard let value else { return }
        // Never hold the configuration lock across SceneKit calls. The render
        // thread can run concurrently with a viewport/format update on main.
        let target = presentation ? root.presentation : root
        let points = value.bounds.flatMap { bounds -> [SIMD3<Double>] in
            let node = presentation ? bounds.node.presentation : bounds.node
            var points: [SIMD3<Double>] = []
            for x in [bounds.minimum.x, bounds.maximum.x] {
                for y in [bounds.minimum.y, bounds.maximum.y] {
                    for z in [bounds.minimum.z, bounds.maximum.z] {
                        let point = node.convertPosition(SCNVector3(x,y,z), to: target)
                        points.append(SIMD3(Double(point.x),Double(point.y),Double(point.z)))
                    }
                }
            }
            return points
        }
        let fit = CaseCarousel.fitHeld(points: points, cameraDistance: value.distance, aspect: value.aspect)
        // Leave a settled scene idle; assigning an identical transform from a
        // render callback could otherwise request another needless frame.
        guard abs(Double(root.scale.x)-fit.scale)>0.000002 ||
              abs(Double(root.position.x)-fit.x)>0.000002 ||
              abs(Double(root.position.y)-fit.y)>0.000002 else{return}
        let scale = Float(fit.scale)
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        root.scale = SCNVector3(scale,scale,scale)
        root.position = SCNVector3(Float(fit.x),Float(fit.y),0)
        SCNTransaction.commit()
    }
}

@MainActor private final class CaseScene {
    weak var bridge: CaseHitBridge?
    let view: CaseMetalView
    let scene = SCNScene(), model = SCNNode(), body = SCNNode()
    private let heldRoot = SCNNode(), shelfRoot = SCNNode()
    private lazy var foregroundFramer = CaseForegroundFramer(root: heldRoot)
    let front = SCNMaterial(), back = SCNMaterial(), inside = SCNMaterial(), edge = SCNMaterial(), spine = SCNMaterial()
    let highlight = SCNNode(), camera = SCNNode()
    let previewImageNode = SCNNode(), previewVideoNode = SCNNode(), previewBorder = SCNNode()
    private var oldPreviewStill: CGImage?, oldPreviewPlayer: AVPlayer?
    private var oldPreviewShowing = false
    private var previewVideoActive = false
    let lidHinge = SCNNode(), lid = SCNNode()
    let leftModel = SCNNode(), rightModel = SCNNode(), farLeftModel = SCNNode(), farRightModel = SCNNode()
    let leftCover = SCNMaterial(), rightCover = SCNMaterial(), farLeftCover = SCNMaterial(), farRightCover = SCNMaterial()
    private var neighborNodes: [SCNNode] { [farLeftModel,leftModel,rightModel,farRightModel] }
    private var neighborCovers: [SCNMaterial] { [farLeftCover,leftCover,rightCover,farRightCover] }
    private var lastNeighbors: [String] = []
    private var oldNeighborPackages: [String] = []
    private var neighborQuality: CaseRenderQuality?
    private var oldNeighborArt: [CGImage?] = []
    private var oldConcept: ClubInterfaceProfile?
    private var isCollector = false, collectorOpen = false
    private var packageFormat: CasePackageFormat = .dvd
    private var previewFacing = CasePreviewFacing()
    private var hasPose = false
    private var caseDepth: Float { packageFormat.halfDepth(collector:isCollector) }
    private var printedWidth: CGFloat { CGFloat(packageFormat.faceWidth) }
    private var printedHeight: CGFloat { CGFloat(packageFormat.faceHeight) }
    private var previewSurface: SCNNode { collectorOpen ? lid:body }
    private var previewDepth: Float { collectorOpen ? 0.07:caseDepth }
    private var itemID: String?, displayedDetails: IPTVDetails?, displayedPrint: CasePrintData?
    private var oldArtwork: CGImage?, oldEpisodeArt: [String:FluxBitmap] = [:]
    private var oldYaw: Double = 0, oldPitch: Double = 0, oldTheme: VideoClubTheme?, oldQuality: CaseRenderQuality?
    private var oldFocus: CaseFaceLayout.Action?, oldFocusPage: CaseFaceLayout.Page?
    private var pauseRender: Task<Void,Never>?, textureTask: Task<Void,Never>?, textureToken = UUID()
    private var projectionTask: Task<Void,Never>?
    private var lastRenderPulse: TimeInterval = 0
    private var dirtyFront = true, dirtyBack = true, dirtyInside = true, dirtySpine = true

    init() {
        view = CaseMetalView(frame:.zero,options:[SCNView.Option.preferredRenderingAPI.rawValue:SCNRenderingAPI.metal.rawValue])
        view.backgroundColor = .clear
        view.rendersContinuously = false; view.isPlaying = false; view.allowsCameraControl = false
        view.preferredFramesPerSecond = 60; view.antialiasingMode = .multisampling2X
        view.scene = scene; scene.rootNode.addChildNode(heldRoot); heldRoot.addChildNode(model); model.addChildNode(body)
        scene.rootNode.addChildNode(shelfRoot)
        model.addChildNode(lidHinge); lidHinge.addChildNode(lid); lidHinge.isHidden = true
        lidHinge.position = SCNVector3(-0.953,0,0.34)
        lid.position = SCNVector3(0.953,0,0); lid.scale = SCNVector3(1,1,0.45)
        for node in neighborNodes { node.isHidden = true; shelfRoot.addChildNode(node) }
        for cover in neighborCovers {
            cover.lightingModel = .physicallyBased; cover.roughness.contents = 0.45
            cover.diffuse.mipFilter = .linear; cover.diffuse.minificationFilter = .linear
            cover.diffuse.contents = CaseColor(white:0.13,alpha:1)
        }
        camera.camera = SCNCamera(); camera.camera?.fieldOfView = 35; camera.camera?.projectionDirection = .vertical
        camera.camera?.zNear = 0.05
        camera.position = SCNVector3(0,0,6); scene.rootNode.addChildNode(camera); view.pointOfView = camera
        func light(_ type:SCNLight.LightType,_ intensity:CGFloat,_ position:SCNVector3,_ color:CaseColor) {
            let node = SCNNode(); node.light = SCNLight(); node.light?.type = type
            node.light?.intensity = intensity; node.light?.color = color; node.position = position
            scene.rootNode.addChildNode(node)
        }
        light(.ambient,180,SCNVector3(0,0,0),CaseColor(white:0.9,alpha:1))
        light(.omni,540,SCNVector3(-3,4,5),CaseColor(red:1,green:0.95,blue:0.88,alpha:1))
        light(.omni,340,SCNVector3(3,2,-4),CaseColor(red:0.62,green:0.83,blue:1,alpha:1))
        let grain = SleeveTexture.normalMap()
        for material in [front,back,inside,edge,spine] {
            material.lightingModel = .physicallyBased; material.isDoubleSided = false
            material.metalness.contents = 0.0; material.roughness.contents = 0.40
            material.normal.contents = grain; material.normal.intensity = 0.16
            material.normal.wrapS = .repeat; material.normal.wrapT = .repeat
            material.normal.mipFilter = .linear; material.normal.minificationFilter = .linear
            material.normal.contentsTransform = SCNMatrix4MakeScale(5,8,1)
            material.diffuse.mipFilter = .linear; material.diffuse.minificationFilter = .linear
            material.diffuse.magnificationFilter = .linear
        }
        front.roughness.contents = 0.29; back.roughness.contents = 0.33; inside.roughness.contents = 0.52
        edge.roughness.contents = 0.52; edge.normal.intensity = 0.55
        edge.normal.contentsTransform = SCNMatrix4MakeScale(2,16,1); spine.normal.intensity = 0.24
        let sheen = SCNMaterial(); sheen.lightingModel = .constant
        sheen.diffuse.contents = SleeveTexture.focusTexture(); sheen.isDoubleSided = false; sheen.writesToDepthBuffer = false
        let plane = SCNPlane(width:1,height:1); plane.firstMaterial = sheen
        highlight.geometry = plane; highlight.isHidden = true; highlight.renderingOrder = 2; body.addChildNode(highlight)
        for node in [previewImageNode,previewVideoNode] {
            let plane=SCNPlane(width:1,height:1), material=SCNMaterial()
            material.lightingModel = .constant;material.isDoubleSided=false
            material.diffuse.mipFilter = .linear;material.diffuse.minificationFilter = .linear
            material.writesToDepthBuffer=false;plane.firstMaterial=material
            node.geometry=plane;node.isHidden=true;node.renderingOrder=3
            node.eulerAngles=SCNVector3(0,Float.pi,0);body.addChildNode(node)
        }
        let borderPlane=SCNPlane(width:1,height:1);borderPlane.firstMaterial=sheen
        previewBorder.geometry=borderPlane;previewBorder.isHidden=true;previewBorder.renderingOrder=4
        previewBorder.eulerAngles=SCNVector3(0,Float.pi,0);body.addChildNode(previewBorder)
        let shadow = SCNNode(geometry:SCNPlane(width:3.5,height:4.2))
        let shadowMaterial = SCNMaterial(); shadowMaterial.lightingModel = .constant
        shadowMaterial.diffuse.contents = SleeveTexture.shadowTexture(); shadowMaterial.writesToDepthBuffer = false
        shadow.geometry?.firstMaterial = shadowMaterial; shadow.position = SCNVector3(0,-0.12,-0.9)
        shadow.renderingOrder = -1; shelfRoot.addChildNode(shadow)
        view.delegate = foregroundFramer
        view.resized = { [weak self] size in self?.layoutScene(size) }
    }
    private func layoutNeighbors(_ size:CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let aspect=Double(size.width/size.height),editorial=oldConcept?.isEditorial ?? false
        let placements = CaseCarousel.placements(aspect:aspect,editorial:editorial)
        let shelf=CaseCarousel.shelfTransform(aspect:aspect,editorial:editorial)
        let scale=Float(shelf.scale)
        shelfRoot.scale=SCNVector3(scale,scale,scale)
        shelfRoot.position=SCNVector3(0,0,Float(shelf.z))
        for (node,placement) in zip(neighborNodes,placements) {
            node.position = SCNVector3(Float(placement.x),Float(placement.y),Float(-placement.depth))
            let scale = Float(placement.scale); node.scale = SCNVector3(scale,scale,scale)
            node.eulerAngles = SCNVector3(0,Float(placement.angle * .pi/180),0)
        }
    }
    private func layoutScene(_ size:CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        // This reference camera depends only on viewport and shelf style.
        // Opening a season, changing DVD/VHS or rotating never reframes it.
        let distance=CaseCarousel.distance(aspect:Double(size.width/size.height),editorial:oldConcept?.isEditorial ?? false)
        SCNTransaction.begin(); SCNTransaction.disableActions=true
        camera.position = SCNVector3(0,0,Float(distance))
        layoutNeighbors(size)
        SCNTransaction.commit()
        configureForegroundFit(size)
        foregroundFramer.fit(presentation:false)
        updateSampling(oldQuality ?? .balanced,size:size); pulse()
    }
    private func configureForegroundFit(_ size:CGSize) {
        guard size.width>0,size.height>0 else{return}
        let bounds=(isCollector ? [body,lid]:[body]).compactMap { node -> CaseForegroundFramer.Bounds? in
            guard let geometry=node.geometry else{return nil}
            let bounds=geometry.boundingBox
            // Printed preview/focus planes sit just above the plastic shell.
            let minimum=SCNVector3(bounds.min.x,bounds.min.y,bounds.min.z-0.015)
            let maximum=SCNVector3(bounds.max.x,bounds.max.y,bounds.max.z+0.015)
            return CaseForegroundFramer.Bounds(node:node,minimum:minimum,maximum:maximum)
        }
        foregroundFramer.configure(distance:Double(camera.position.z),aspect:Double(size.width/size.height),bounds:bounds)
    }
    private func updateSampling(_ quality:CaseRenderQuality,size:CGSize) {
        #if os(macOS)
        let scale = view.window?.backingScaleFactor ?? 1
        #else
        let scale = view.contentScaleFactor
        #endif
        let pixels = size.width * size.height * scale * scale
        let budget: CGFloat = quality == .cinema ? 4_200_000 : 2_200_000
        view.antialiasingMode = quality != .economy && pixels > 0 && pixels <= budget ? .multisampling2X : .none
    }
    private func geometry(_ mesh:[ProceduralCase.Triangle],materials:[SCNMaterial]) -> SCNGeometry {
        var points:[SCNVector3] = [], normals:[SCNVector3] = [], uvs:[CGPoint] = [], elements:[SCNGeometryElement] = []
        for surface in ProceduralCase.Surface.allCases {
            var indices:[UInt32] = []
            for triangle in mesh where triangle.surface == surface {
                for vertex in triangle.vertices {
                    indices.append(UInt32(points.count))
                    points.append(SCNVector3(vertex.position.x,vertex.position.y,vertex.position.z))
                    normals.append(SCNVector3(vertex.normal.x,vertex.normal.y,vertex.normal.z))
                    uvs.append(CGPoint(x:CGFloat(vertex.uv.x),y:CGFloat(vertex.uv.y)))
                }
            }
            elements.append(SCNGeometryElement(data:indices.withUnsafeBytes{Data($0)},primitiveType:.triangles,primitiveCount:indices.count/3,bytesPerIndex:4))
        }
        let value = SCNGeometry(sources:[SCNGeometrySource(vertices:points),SCNGeometrySource(normals:normals),SCNGeometrySource(textureCoordinates:uvs)],elements:elements)
        value.materials = materials
        return value
    }
    private func rebuildMesh(_ quality:CaseRenderQuality) {
        body.geometry = geometry(ProceduralCase.premiumMesh(cornerSegments:quality.cornerSegments,format:packageFormat,collector:isCollector),materials:[isCollector ? inside:front,back,edge,spine])
        lid.geometry = geometry(ProceduralCase.premiumMesh(cornerSegments:quality.cornerSegments,format:packageFormat,halfDepth:0.07),materials:[front,back,edge,spine])
        lidHinge.isHidden = !isCollector
        let hingeX=packageFormat.halfWidth-packageFormat.bevel
        lidHinge.position=SCNVector3(-hingeX,0,caseDepth+0.04)
        lid.position=SCNVector3(hingeX,0,0)
    }
    private func pulse() {
        lastRenderPulse = ProcessInfo.processInfo.systemUptime; view.isPlaying = true
        if projectionTask == nil {
            projectionTask = Task { @MainActor [weak self] in
                repeat {
                    // Publishing outside updateNSView/updateUIView avoids a
                    // nested SwiftUI layout while tracking the short 3D motion.
                    try? await Task.sleep(nanoseconds: 33_000_000)
                    guard !Task.isCancelled, let self else { return }
                    self.publishPreviewProjection()
                    if ProcessInfo.processInfo.systemUptime - self.lastRenderPulse >= 0.38 {
                        self.projectionTask = nil
                        return
                    }
                } while !Task.isCancelled
            }
        }
        guard pauseRender == nil else { return }
        pauseRender = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds:120_000_000)
                guard !Task.isCancelled, let self else { return }
                if ProcessInfo.processInfo.systemUptime - self.lastRenderPulse >= 0.38 {
                    self.view.isPlaying = self.previewVideoActive; self.pauseRender = nil; return
                }
            }
        }
    }
    private func publishPreviewProjection() {
        guard let bridge, view.bounds.width > 0, view.bounds.height > 0 else { return }
        let rect = CaseBackMediaLayout.videoFrame(width:printedWidth,height:printedHeight)
        if bridge.previewContentUVFrame != rect {bridge.previewContentUVFrame=rect}
        let target=previewSurface.presentation, depth=previewDepth
        let normal=target.convertVector(SCNVector3(0,0,-1),to:nil)
        let backCenter=target.convertPosition(SCNVector3(0,0,-depth-0.007),to:nil)
        let eye=camera.presentation.convertPosition(SCNVector3(0,0,0),to:nil)
        let dx=Double(eye.x-backCenter.x),dy=Double(eye.y-backCenter.y),dz=Double(eye.z-backCenter.z)
        let nx=Double(normal.x),ny=Double(normal.y),nz=Double(normal.z)
        let length=sqrt((dx*dx+dy*dy+dz*dz)*(nx*nx+ny*ny+nz*nz))
        let facing=previewFacing.update(backFacing:length>1e-12 ? (dx*nx+dy*ny+dz*nz)/length:0)
        if bridge.previewBackFacing != facing {bridge.previewBackFacing=facing}
        // SceneKit's view-coordinate Y convention differs across renderers.
        // Calibrate against the actual camera instead of guessing from the OS.
        let center = view.projectPoint(camera.presentation.convertPosition(SCNVector3(0,0,-2), to:nil))
        let up = view.projectPoint(camera.presentation.convertPosition(SCNVector3(0,0.2,-2), to:nil))
        let downwardsY = up.y < center.y
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let local = SCNVector3(Float(-(x-0.5)*printedWidth), Float((0.5-y)*printedHeight), -depth-0.007)
            let world = target.convertPosition(local, to: nil)
            let screen = view.projectPoint(world)
            return CGPoint(x: CGFloat(screen.x), y: downwardsY ? CGFloat(screen.y) : view.bounds.height-CGFloat(screen.y))
        }
        let projection = CasePreviewProjection(
            topLeft: point(rect.minX,rect.minY), topRight: point(rect.maxX,rect.minY),
            bottomRight: point(rect.maxX,rect.maxY), bottomLeft: point(rect.minX,rect.maxY),
            viewport: view.bounds.size)
        if bridge.previewProjection != projection { bridge.previewProjection = projection }
    }
    private func hitPoint(_ point:CGPoint) -> CGPoint {
        #if os(macOS)
        return CGPoint(x:point.x,y:view.isFlipped ? point.y:view.bounds.height-point.y)
        #else
        return point
        #endif
    }
    func hit(_ point:CGPoint) -> (ProceduralCase.Surface,CGPoint)? {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        for result in view.hitTest(hitPoint(point),options:[.searchMode:SCNHitTestSearchMode.all.rawValue,.ignoreHiddenNodes:true]) {
            if neighborNodes.contains(where:{$0 === result.node}) { return nil }
            if [highlight,previewImageNode,previewVideoNode,previewBorder].contains(where:{$0 === result.node}) {continue}
            guard result.node === body || result.node === lid else { continue }
            if let surface = ProceduralCase.Surface(rawValue:result.geometryIndex) {
                // The opened cover carries the synopsis. Episode hit regions are
                // only on the collector's inner tray, never through its lid.
                if result.node === lid && collectorOpen { return (.back,result.textureCoordinates(withMappingChannel:0)) }
                return (surface,result.textureCoordinates(withMappingChannel:0))
            }
        }
        return nil
    }
    func hitNeighbor(_ point:CGPoint) -> Int? {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        for result in view.hitTest(hitPoint(point),options:[.searchMode:SCNHitTestSearchMode.all.rawValue,.ignoreHiddenNodes:true]) {
            if result.node === body || result.node === lid { return nil }
            if let index = neighborNodes.firstIndex(where:{$0 === result.node}) { return CaseCarousel.offsets[index] }
        }
        return nil
    }
    func updateNeighbors(previous:IPTVItem?,next:IPTVItem?,previousFar:IPTVItem?,nextFar:IPTVItem?,left:CGImage?,right:CGImage?,farLeft:CGImage?,farRight:CGImage?,concept:ClubInterfaceProfile,motion:Bool) {
        let items = [previousFar,previous,next,nextFar], artwork = [farLeft,left,right,farRight]
        let ids = items.map{$0?.id ?? ""}
        let packages=items.map{CasePackageFormat.resolve(year:$0?.details.year).rawValue+String($0?.isSeriesCollection ?? false)}
        let quality=oldQuality ?? .balanced
        let changedArt = artwork.enumerated().contains { index,image in index >= oldNeighborArt.count || oldNeighborArt[index] !== image }
        let changedShape=packages != oldNeighborPackages || neighborQuality != quality
        guard ids != lastNeighbors || changedArt || changedShape || oldConcept != concept else { return }
        let conceptChanged = oldConcept != concept
        SCNTransaction.begin(); SCNTransaction.animationDuration = motion && oldConcept != nil ? 0.24 : 0
        oldConcept = concept; layoutNeighbors(view.bounds.size)
        for index in 0..<4 {
            neighborNodes[index].isHidden = items[index] == nil
            if changedShape {
                let format=CasePackageFormat.resolve(year:items[index]?.details.year)
                neighborNodes[index].geometry=geometry(ProceduralCase.premiumMesh(cornerSegments:quality.cornerSegments,format:format,collector:items[index]?.isSeriesCollection ?? false),materials:[neighborCovers[index],edge,edge,edge])
            }
            if let image=artwork[index] {neighborCovers[index].diffuse.contents=image}
            else {neighborCovers[index].diffuse.contents=CaseColor(white:0.13,alpha:1)}
        }
        SCNTransaction.commit()
        lastNeighbors = ids; oldNeighborArt = artwork;oldNeighborPackages=packages;neighborQuality=quality
        if conceptChanged { layoutScene(view.bounds.size) }
        pulse()
    }
    private func updateFocus(_ focus:CaseFaceLayout.Action?,page:CaseFaceLayout.Page?,data:CasePrintData,item:IPTVItem) {
        highlight.isHidden=true;previewBorder.isHidden=true
        guard let focus,let page else{return}
        if (page == .details || collectorOpen) && (focus == .trailer || focus == .play || focus == .description) {
            if highlight.parent !== previewSurface {highlight.removeFromParentNode();previewSurface.addChildNode(highlight)}
            let rect=focus == .description ? CaseBackMediaLayout.descriptionFrame:(focus == .trailer ? CaseBackMediaLayout.frame:CaseBackMediaLayout.film)
            if let plane=highlight.geometry as? SCNPlane {
                plane.width=rect.width*printedWidth;plane.height=rect.height*printedHeight
                highlight.position=SCNVector3(Float(-(rect.midX-0.5)*printedWidth),Float((0.5-rect.midY)*printedHeight),-previewDepth-0.009)
                highlight.eulerAngles=SCNVector3(0,Float.pi,0);highlight.isHidden=false
                let frame=CaseBackMediaLayout.frame
                if let border=previewBorder.geometry as? SCNPlane {border.width=frame.width*printedWidth;border.height=frame.height*printedHeight}
                previewBorder.position=SCNVector3(Float(-(frame.midX-0.5)*printedWidth),Float((0.5-frame.midY)*printedHeight),-previewDepth-0.009)
                previewBorder.isHidden=focus == .description
            }
            return
        }
        guard case .episode=focus,
              let rect=CaseFaceLayout.regions(page,series:item.isSeriesCollection,trailer:data.trailerAvailable,episodeCount:data.episodes.count,retry:data.retry).first(where:{$0.action==focus})?.rect,
              let plane=highlight.geometry as? SCNPlane else{return}
        if highlight.parent !== body {highlight.removeFromParentNode();body.addChildNode(highlight)}
        plane.width=rect.width*printedWidth;plane.height=rect.height*printedHeight
        let isBack=page != .front && !collectorOpen,x=(rect.midX-0.5)*printedWidth
        let z:Float=caseDepth+0.004
        highlight.position=SCNVector3(Float(isBack ? -x:x),Float((0.5-rect.midY)*printedHeight),isBack ? -z:z)
        highlight.eulerAngles=SCNVector3(0,isBack ? Float.pi:0,0);highlight.isHidden=false
    }
    func updatePreview(still:CGImage?,player:AVPlayer?,playing:Bool,motion:Bool) {
        let showing=playing && player != nil
        let active=showing && player?.timeControlStatus == .playing
        let changed=oldPreviewStill !== still || oldPreviewPlayer !== player || oldPreviewShowing != showing || previewVideoActive != active
        let rect=CaseBackMediaLayout.frame
        let width=rect.width*printedWidth,height=rect.height*printedHeight
        let depth=previewDepth
        for node in [previewImageNode,previewVideoNode,previewBorder] where node.parent !== previewSurface {
            node.removeFromParentNode();previewSurface.addChildNode(node)
        }
        func place(_ node:SCNNode,_ aspect:CGFloat,_ z:Float) {
            if let plane=node.geometry as? SCNPlane {
                plane.width=min(width,height*aspect);plane.height=min(height,width/max(0.1,aspect))
            }
            node.position=SCNVector3(Float(-(rect.midX-0.5)*printedWidth),Float((0.5-rect.midY)*printedHeight),z)
        }
        if oldPreviewStill !== still {previewImageNode.geometry?.firstMaterial?.diffuse.contents=still;oldPreviewStill=still}
        previewImageNode.isHidden=still == nil
        place(previewImageNode,still.map{CGFloat($0.width)/CGFloat(max(1,$0.height))} ?? 16/9,-depth-0.005)
        if oldPreviewPlayer !== player {previewVideoNode.geometry?.firstMaterial?.diffuse.contents=player;oldPreviewPlayer=player}
        let size=player?.currentItem?.presentationSize ?? .zero
        place(previewVideoNode,size.width>0 && size.height>0 ? size.width/size.height:16/9,-depth-0.006)
        previewVideoNode.isHidden=player == nil
        if changed {
            SCNTransaction.begin();SCNTransaction.animationDuration=motion && showing && !oldPreviewShowing ? 0.5:0
            // Keep the last frame on a paused case, without running SceneKit
            // continuously while AVPlayer has no changing image to deliver.
            previewVideoNode.opacity=showing ? 1:0;SCNTransaction.commit()
            oldPreviewShowing=showing;previewVideoActive=active;pulse()
        }
        if active {view.isPlaying=true}
    }
    func update(item:IPTVItem,details:IPTVDetails,data:CasePrintData,artwork:CGImage?,episodeArt:[String:FluxBitmap],focused:CaseFaceLayout.Action?,yaw:Double,pitch:Double,motion:Bool,theme:VideoClubTheme,quality:CaseRenderQuality) {
        let themeChanged = oldTheme != theme, qualityChanged = oldQuality != quality
        let format=CasePackageFormat.resolve(year:details.year ?? item.details.year)
        let shapeChanged = isCollector != item.isSeriesCollection || packageFormat != format
        let opened = item.isSeriesCollection && data.page == .episodes
        let openingChanged = collectorOpen != opened
        let firstPose = !hasPose
        isCollector = item.isSeriesCollection; collectorOpen = opened;packageFormat=format
        lidHinge.isHidden = !isCollector
        if themeChanged {
            let tint = theme.palette.caseEdge
            edge.diffuse.contents = CaseColor(red:CGFloat(tint.x),green:CGFloat(tint.y),blue:CGFloat(tint.z),alpha:1)
            scene.lightingEnvironment.contents = SleeveTexture.environment(theme); scene.lightingEnvironment.intensity = 0.62
            oldTheme = theme; pulse()
        }
        if qualityChanged || shapeChanged {
            rebuildMesh(quality); view.preferredFramesPerSecond = quality.fps; updateSampling(quality,size:view.bounds.size)
            for material in [front,back] {
                material.clearCoat.contents = quality == .economy ? 0.0 : quality == .cinema ? 0.40 : 0.24
                material.clearCoatRoughness.contents = 0.29
            }
            oldQuality = quality; pulse()
        }
        if openingChanged || shapeChanged || firstPose {
            SCNTransaction.begin(); SCNTransaction.animationDuration = motion && !firstPose ? 0.32 : 0
            lidHinge.eulerAngles = SCNVector3(0,opened ? Float(CaseCarousel.collectorOpeningAngle * .pi/180):0,0)
            model.position = SCNVector3(opened ? 0.75*format.halfWidth:0,0,0)
            SCNTransaction.commit()
        }
        let changedItem = itemID != item.id, changedDetails = displayedDetails != details, changedPrint = displayedPrint != data
        let changedCover = oldArtwork !== artwork
        let changedEpisodeArt = oldEpisodeArt.count != episodeArt.count || episodeArt.contains{oldEpisodeArt[$0.key] !== $0.value}
        dirtyFront = dirtyFront || changedItem || changedCover || themeChanged || qualityChanged || shapeChanged
        dirtyBack = dirtyBack || changedItem || changedDetails || changedCover || themeChanged || qualityChanged || shapeChanged || displayedPrint?.page != data.page || displayedPrint?.season != data.season || displayedPrint?.descriptionText != data.descriptionText || displayedPrint?.previewStatus != data.previewStatus
        dirtyInside = dirtyInside || changedItem || changedPrint || changedEpisodeArt || changedCover || themeChanged || qualityChanged || shapeChanged
        dirtySpine = dirtySpine || changedItem || themeChanged || qualityChanged || shapeChanged
        if changedItem || changedDetails || changedPrint || changedCover || changedEpisodeArt || themeChanged || qualityChanged || shapeChanged {
            textureTask?.cancel(); textureToken = UUID(); let token = textureToken
            oldArtwork = artwork; oldEpisodeArt = episodeArt; displayedDetails = details; displayedPrint = data; itemID = item.id
            if changedItem {
                if let artwork {front.diffuse.contents=artwork}else{front.diffuse.contents=CaseColor(white:0.12,alpha:1)}
                back.diffuse.contents = CaseColor(white:0.10,alpha:1); inside.diffuse.contents = CaseColor(white:0.10,alpha:1)
                spine.diffuse.contents = edge.diffuse.contents; pulse()
            }
            let art = artwork.map(FluxBitmap.init)
            let backAspect=Double(printedWidth/printedHeight)
            let renderFront = dirtyFront, renderBack = dirtyBack, renderInside = dirtyInside && opened, renderSpine = dirtySpine
            textureTask = Task { @MainActor [weak self] in
                let worker = Task.detached(priority:.utility) { () -> (FluxBitmap?,FluxBitmap?,FluxBitmap?,FluxBitmap?) in
                    guard !Task.isCancelled else { return (nil,nil,nil,nil) }
                    let f = renderFront ? SleeveTexture.render(item:item,details:details,page:.front,data:data,artwork:art,episodeArt:[:],theme:theme,quality:quality).map(FluxBitmap.init) : nil
                    guard !Task.isCancelled else { return (nil,nil,nil,nil) }
                    let b = renderBack ? SleeveTexture.render(item:item,details:details,page:.details,data:data,artwork:art,episodeArt:[:],theme:theme,quality:quality,surfaceAspect:backAspect).map(FluxBitmap.init) : nil
                    guard !Task.isCancelled else { return (nil,nil,nil,nil) }
                    let inner = renderInside ? SleeveTexture.render(item:item,details:details,page:.episodes,data:data,artwork:art,episodeArt:episodeArt,theme:theme,quality:quality).map(FluxBitmap.init) : nil
                    let s = renderSpine ? SleeveTexture.spine(item:item,format:format,theme:theme).map(FluxBitmap.init) : nil
                    return (f,b,inner,s)
                }
                let (f,b,inner,s) = await withTaskCancellationHandler(operation:{await worker.value},onCancel:{worker.cancel()})
                guard let self, !Task.isCancelled, self.textureToken == token else { return }
                if let f { self.front.diffuse.contents = f.image; self.dirtyFront = false }
                if let b { self.back.diffuse.contents = b.image; self.dirtyBack = false }
                if let inner { self.inside.diffuse.contents = inner.image; self.dirtyInside = false }
                if let s { self.spine.diffuse.contents = s.image; self.dirtySpine = false }
                self.pulse()
            }
        }
        let face:CaseFaceLayout.Page? = CaseFaceLayout.face(yaw:yaw,pitch:pitch).map{ $0 == .front ? (opened ? .episodes:.front):.details }
        if oldFocus != focused || oldFocusPage != face || changedPrint || changedItem || qualityChanged || shapeChanged {
            updateFocus(focused,page:face,data:data,item:item); oldFocus = focused; oldFocusPage = face; pulse()
        }
        if firstPose || oldYaw != yaw || oldPitch != pitch {
            // A newly attached scene already represents the current case pose.
            // Returning from fullscreen must not animate it through the front.
            pulse(); SCNTransaction.begin(); SCNTransaction.animationDuration = motion && !firstPose ? 0.24 : 0
            model.eulerAngles = SCNVector3(Float(pitch * .pi/180),Float(yaw * .pi/180),0)
            SCNTransaction.commit(); oldYaw = yaw; oldPitch = pitch;hasPose=true
        }
        if shapeChanged || qualityChanged || firstPose { layoutScene(view.bounds.size) }
        if !motion || firstPose { foregroundFramer.fit(presentation:false) }
    }
    func release() {
        view.removePadInput(); view.padInput = nil; view.padEnabled = false
        textureTask?.cancel(); textureToken = UUID(); pauseRender?.cancel(); view.resized = nil
        projectionTask?.cancel(); projectionTask=nil; bridge=nil
        previewVideoNode.geometry?.firstMaterial?.diffuse.contents=nil
        oldPreviewPlayer=nil;oldPreviewStill=nil;oldPreviewShowing=false;previewVideoActive=false
        foregroundFramer.clear(); view.delegate=nil
        view.isPlaying = false; view.scene = nil; view.pointOfView = nil
    }
}

#if os(macOS) && FLUX_CASE_TESTING
/// Native smoke tests drive the same coordinator as the representable. These
/// hooks neither replace its meshes/materials nor ship in the application.
extension CaseScene {
    var fixtureTexturesReady: Bool {
        !dirtyFront && !dirtyBack && !dirtySpine && (!collectorOpen || !dirtyInside)
    }
    var fixturePreviewOnLid: Bool {
        collectorOpen && previewSurface === lid && previewImageNode.parent === lid &&
        previewVideoNode.parent === lid && previewBorder.parent === lid
    }
    func fixtureRefreshProjection() { publishPreviewProjection() }
    private func fixtureCorners(_ node:SCNNode)->[SCNVector3] {
        guard let geometry=node.geometry else{return []}
        let bounds=geometry.boundingBox,target=node.presentation
        return [bounds.min.x,bounds.max.x].flatMap {x in
            [bounds.min.y,bounds.max.y].flatMap {y in
                [bounds.min.z,bounds.max.z].map {z in target.convertPosition(SCNVector3(x,y,z),to:nil)}
            }
        }
    }
    private func fixtureProjectedBounds(_ points:[SCNVector3])->CGRect {
        let projected=points.map{view.projectPoint($0)}
        guard let first=projected.first else{return .zero}
        let minX=projected.map(\.x).min() ?? first.x,maxX=projected.map(\.x).max() ?? first.x
        let minY=projected.map(\.y).min() ?? first.y,maxY=projected.map(\.y).max() ?? first.y
        return CGRect(x:Double(minX),y:Double(minY),width:Double(maxX-minX),height:Double(maxY-minY))
    }
    var fixtureCameraDistance:Double {Double(camera.presentation.position.z)}
    var fixtureNeighborBounds:[CGRect] {
        neighborNodes.filter{!$0.isHidden}.map{fixtureProjectedBounds(fixtureCorners($0))}
    }
    var fixtureHeldBounds:CGRect {
        fixtureProjectedBounds((isCollector ? [body,lid]:[body]).flatMap{fixtureCorners($0)})
    }
    var fixtureDepthClearance:Double {
        let held=(isCollector ? [body,lid]:[body]).flatMap{fixtureCorners($0)}.map{Double($0.z)}.min() ?? 0
        let shelf=neighborNodes.filter{!$0.isHidden}.flatMap{fixtureCorners($0)}.map{Double($0.z)}.max() ?? 0
        return held-shelf
    }
}

@MainActor final class CaseSceneSmokeHarness {
    private let renderer = CaseScene()
    let bridge = CaseHitBridge()
    var view: SCNView { renderer.view }
    var texturesReady: Bool { renderer.fixtureTexturesReady }
    var previewOnLid: Bool { renderer.fixturePreviewOnLid }
    var cameraDistance:Double {renderer.fixtureCameraDistance}
    var neighborBounds:[CGRect] {renderer.fixtureNeighborBounds}
    var heldBounds:CGRect {renderer.fixtureHeldBounds}
    var depthClearance:Double {renderer.fixtureDepthClearance}

    init(size: CGSize) {
        renderer.bridge = bridge
        renderer.view.frame = CGRect(origin: .zero, size: size)
    }
    func show(item: IPTVItem, data: CasePrintData, artwork: CGImage, previewStill: CGImage,
              yaw: Double, pitch: Double = -4, focused: CaseFaceLayout.Action? = nil,
              neighbors: [IPTVItem] = [], motion:Bool = false) {
        renderer.update(item: item, details: item.details, data: data, artwork: artwork, episodeArt: [:],
                        focused: focused, yaw: yaw, pitch: pitch, motion: motion, theme: .neo90, quality: .balanced)
        renderer.updatePreview(still: previewStill, player: nil, playing: false, motion: false)
        func neighbor(_ index: Int) -> IPTVItem? { neighbors.indices.contains(index) ? neighbors[index] : nil }
        renderer.updateNeighbors(previous: neighbor(1), next: neighbor(2), previousFar: neighbor(0), nextFar: neighbor(3),
                                 left: artwork, right: artwork, farLeft: artwork, farRight: artwork,
                                 concept: .neoVideoClub, motion: motion)
    }
    func refreshProjection() { renderer.fixtureRefreshProjection() }
    func hit(_ point: CGPoint) -> (ProceduralCase.Surface, CGPoint)? { renderer.hit(point) }
    func release() { renderer.release() }
}
#endif

#if os(macOS)
private struct CaseSceneSurface:NSViewRepresentable {
    let item:IPTVItem;let details:IPTVDetails;let printData:CasePrintData;let artwork:CGImage?;let episodeArt:[String:FluxBitmap];let focused:CaseFaceLayout.Action?;let yaw:Double;let pitch:Double;let motion:Bool;let theme:VideoClubTheme;let quality:CaseRenderQuality;let bridge:CaseHitBridge;let padInput:(CasePadInput)->Void;let padEnabled:Bool
    let previousItem:IPTVItem?;let nextItem:IPTVItem?;let previousFarItem:IPTVItem?;let nextFarItem:IPTVItem?;let leftArtwork:CGImage?;let rightArtwork:CGImage?;let farLeftArtwork:CGImage?;let farRightArtwork:CGImage?;let previewStill:CGImage?;let previewPlayer:AVPlayer?;let previewPlaying:Bool;let concept:ClubInterfaceProfile
    func makeCoordinator()->CaseScene {CaseScene()}
    func makeNSView(context:Context)->SCNView {let scene=context.coordinator;scene.bridge=bridge;bridge.pick={[weak scene] in scene?.hit($0)};bridge.pickNeighbor={[weak scene] in scene?.hitNeighbor($0)};scene.view.padInput=padInput;scene.view.padEnabled=padEnabled;return scene.view}
    func updateNSView(_ view:SCNView,context:Context) {context.coordinator.view.padInput=padInput;context.coordinator.view.padEnabled=padEnabled;context.coordinator.update(item:item,details:details,data:printData,artwork:artwork,episodeArt:episodeArt,focused:focused,yaw:yaw,pitch:pitch,motion:motion,theme:theme,quality:quality);context.coordinator.updatePreview(still:previewStill,player:previewPlayer,playing:previewPlaying,motion:motion);context.coordinator.updateNeighbors(previous:previousItem,next:nextItem,previousFar:previousFarItem,nextFar:nextFarItem,left:leftArtwork,right:rightArtwork,farLeft:farLeftArtwork,farRight:farRightArtwork,concept:concept,motion:motion)}
    static func dismantleNSView(_ nsView:SCNView,coordinator:CaseScene) {coordinator.release()}
}
#else
private struct CaseSceneSurface:UIViewRepresentable {
    let item:IPTVItem;let details:IPTVDetails;let printData:CasePrintData;let artwork:CGImage?;let episodeArt:[String:FluxBitmap];let focused:CaseFaceLayout.Action?;let yaw:Double;let pitch:Double;let motion:Bool;let theme:VideoClubTheme;let quality:CaseRenderQuality;let bridge:CaseHitBridge;let padInput:(CasePadInput)->Void;let padEnabled:Bool
    let previousItem:IPTVItem?;let nextItem:IPTVItem?;let previousFarItem:IPTVItem?;let nextFarItem:IPTVItem?;let leftArtwork:CGImage?;let rightArtwork:CGImage?;let farLeftArtwork:CGImage?;let farRightArtwork:CGImage?;let previewStill:CGImage?;let previewPlayer:AVPlayer?;let previewPlaying:Bool;let concept:ClubInterfaceProfile
    func makeCoordinator()->CaseScene {CaseScene()}
    func makeUIView(context:Context)->SCNView {let scene=context.coordinator;scene.bridge=bridge;bridge.pick={[weak scene] in scene?.hit($0)};bridge.pickNeighbor={[weak scene] in scene?.hitNeighbor($0)};scene.view.padInput=padInput;scene.view.padEnabled=padEnabled;return scene.view}
    func updateUIView(_ view:SCNView,context:Context) {context.coordinator.view.padInput=padInput;context.coordinator.view.padEnabled=padEnabled;context.coordinator.update(item:item,details:details,data:printData,artwork:artwork,episodeArt:episodeArt,focused:focused,yaw:yaw,pitch:pitch,motion:motion,theme:theme,quality:quality);context.coordinator.updatePreview(still:previewStill,player:previewPlayer,playing:previewPlaying,motion:motion);context.coordinator.updateNeighbors(previous:previousItem,next:nextItem,previousFar:previousFarItem,nextFar:nextFarItem,left:leftArtwork,right:rightArtwork,farLeft:farLeftArtwork,farRight:farRightArtwork,concept:concept,motion:motion)}
    static func dismantleUIView(_ uiView:SCNView,coordinator:CaseScene) {coordinator.release()}
}
#endif
struct CaseFrameKey: PreferenceKey {
    static var defaultValue:[String:CGRect]=[:]
    static func reduce(value:inout [String:CGRect],nextValue:()->[String:CGRect]) {value.merge(nextValue(),uniquingKeysWith:{_,new in new})}
}
final class CaseFrameCache {
    private var frames:[String:CGRect]=[:]
    func update(_ value:[String:CGRect]) {frames=value}
    func frame(for id:String)->CGRect? {frames[id]}
}
