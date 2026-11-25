import SwiftUI

/// A cheap catalogue sleeve: the provider artwork stays complete inside a
/// plastic frame. The parent animates only the focused artwork; the sleeve
/// itself keeps constant bounds and does not scale neighbouring catalogue items.
struct CatalogSleeveArtwork: View {
    let item: IPTVItem

    private var format: CasePackageFormat { .resolve(year: item.details.year) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * (format == .vhs ? 0.89 : 1)
            let spine = max(format == .vhs ? 6 : 3, width * (format == .vhs ? 0.055 : 0.026))
            let radius: CGFloat = format == .vhs ? 6 : 4
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            HStack(spacing: 0) {
                #if os(tvOS)
                // A narrow opaque edge keeps the sleeve depth without a
                // reflected gradient/composited gloss surface on every card.
                Rectangle().fill(Color(red: 0.09, green: 0.10, blue: 0.12))
                    .frame(width: spine)
                    .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.18)).frame(width: 1) }
                #else
                LinearGradient(colors: [.black, .white.opacity(0.20), .black.opacity(0.92)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: spine)
                    .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.22)).frame(width: 0.7) }
                #endif
                ArtworkView(url: item.logoURL, fit: true) {
                    Image(systemName: item.kind == .series ? "square.stack.3d.up" : "film")
                        .font(.largeTitle).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.72))
                #if !os(tvOS)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                #endif
                .padding(.vertical, format == .vhs ? 3 : 2)
                .padding(.trailing, 2)
            }
            .frame(width: width, height: geometry.size.height)
            .background(Color(red: 0.075, green: 0.080, blue: 0.088), in: shape)
            .clipShape(shape)
            #if !os(tvOS)
            .overlay {
                LinearGradient(stops: [.init(color: .white.opacity(0.12), location: 0),
                                       .init(color: .clear, location: 0.26),
                                       .init(color: .clear, location: 0.80),
                                       .init(color: .white.opacity(0.045), location: 1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            #endif
            .overlay { shape.strokeBorder(.white.opacity(0.26), lineWidth: 0.8).allowsHitTesting(false) }
            #if !os(tvOS)
            .shadow(color: .black.opacity(0.46), radius: 2, x: 1.5, y: 2)
            #endif
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .accessibilityHidden(true)
    }
}
