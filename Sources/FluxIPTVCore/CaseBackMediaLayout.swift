import Foundation

/// Normalized UV layout shared by printed artwork, video planes and focus.
public enum CaseBackMediaLayout {
    public static let frame = CGRect(x:0.055,y:0.065,width:0.89,height:0.334)
    public static let trailer = CGRect(x:0.055,y:0.411,width:0.435,height:0.046)
    public static let film = CGRect(x:0.51,y:0.411,width:0.435,height:0.046)
    public static let descriptionFrame = CGRect(x:0.04,y:0.632,width:0.92,height:0.274)
    public static let descriptionPrevious = CGRect(x:0.05,y:0.639,width:0.06,height:0.04)
    public static let descriptionNext = CGRect(x:0.89,y:0.639,width:0.06,height:0.04)
    public static let descriptionLink = CGRect(x:0.13,y:0.874,width:0.74,height:0.026)

    /// The embedded player keeps its 16:9 viewport even on a narrow season
    /// rack. Return its letterboxed rectangle in the printed face's UV space;
    /// width and height describe that face's physical dimensions, not pixels.
    public static func videoFrame(width: CGFloat, height: CGFloat) -> CGRect {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return frame }
        let aspect: CGFloat = 16.0/9.0
        let availableWidth = frame.width*width, availableHeight = frame.height*height
        let fittedWidth = min(availableWidth, availableHeight*aspect)/width
        let fittedHeight = min(availableHeight, availableWidth/aspect)/height
        return CGRect(x: frame.midX-fittedWidth/2, y: frame.midY-fittedHeight/2,
                      width: fittedWidth, height: fittedHeight)
    }

    public static func action(at uv:CGPoint) -> CaseFaceLayout.Action? {
        if trailer.contains(uv) { return .trailer }
        if film.contains(uv) { return .play }
        return nil
    }
}
