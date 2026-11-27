import SwiftUI

/// Every provider season gets its own front-facing sleeve in the series' shelf.
/// Lazy rows retain the complete list; opening a season is a separate step.
struct SeriesSeasonShelf: View {
    let series: IPTVItem
    let seasons: [IPTVSeason]
    let columns: Int
    let focusedID: String?
    let systemFocus: FocusState<String?>.Binding
    let focus: (IPTVSeason) -> Void
    let open: (IPTVSeason) -> Void
    /// Set by the desk layout: the sleeve of the open season travels to its fiche.
    var heroNamespace: Namespace.ID? = nil
    var heldSeason: Int? = nil
    var heroExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(iOS)
    private static let topRoom: CGFloat = 32, topFade: CGFloat = 0
    #else
    // A remote scrolls one row at a time and leaves the foot of the row above
    // at the top of the shelf: it fades there, clear of the lifted sleeve.
    // A Mac shows the same shelf at the size of its window.
    private static var topRoom: CGFloat { Desk.tv(48) }
    private static let topFade: CGFloat = 0.035
    #endif

    static func focusID(_ season: IPTVSeason) -> String { "season-\(season.number)" }
    static func title(_ season: IPTVSeason) -> String { season.number == 0 ? "Spéciaux" : "Saison \(season.number)" }

    static func sleeve(series: IPTVItem, season: IPTVSeason) -> IPTVItem {
        IPTVItem(id: "\(series.id)::season::\(season.number)", sourceID: series.sourceID,
                 name: "\(series.name) · \(title(season))", group: series.group,
                 logoURL: series.logoURL, kind: .series, directURL: nil,
                 xtreamStreamID: nil, fileExtension: nil, backdropURL: series.backdropURL,
                 details: series.details, seasonNumber: season.number)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: Desk.tv(4)), count: max(1, columns)), spacing: Desk.tv(18)) {
                ForEach(seasons) { season in seasonButton(season) }
            }
            // Leave room for the selected sleeve's upward lift and zoom.
            .padding(.horizontal, Desk.tv(20)).padding(.top, Self.topRoom).padding(.bottom, Desk.tv(24))
        }
        #if os(tvOS)
        // A scroll view that touches the edge of the safe area spreads under
        // it, and the focus engine then places its sleeves a margin away from
        // where they are drawn. Two points keep it inside.
        .padding(.horizontal, 2)
        #endif
        // A row that is only partly in view fades out instead of being cut.
        .mask(LinearGradient(stops: [.init(color: Self.topFade > 0 ? .clear : .black, location: 0),
                                     .init(color: .black, location: Self.topFade),
                                     .init(color: .black, location: 0.955), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }

    private func seasonButton(_ season: IPTVSeason) -> some View {
        let id = Self.focusID(season), selected = focusedID == id
        let title = Self.title(season)
        return Button { focus(season); open(season) } label: {
            VStack(alignment: .leading, spacing: 6) {
                CatalogSleeveArtwork(item: Self.sleeve(series: series, season: season))
                    .aspectRatio(2.0/3.0, contentMode: .fit)
                    .modifier(SeasonSleeveHero(namespace: heroNamespace, id: "sleeve-\(series.id)::season::\(season.number)",
                                               held: heldSeason == season.number, expanded: heroExpanded))
                HStack(spacing: 5) {
                    Text(title).font(Desk.font(.headline)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(CasePackageFormat.resolve(year: series.details.year).title)
                        .font(Desk.font(.caption2, .semibold)).foregroundStyle(.secondary)
                }
                Text("\(season.episodes.count) épisodes").font(Desk.font(.caption)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 3).padding(.bottom, 9)
            .background(.white.opacity(selected ? 0.12 : 0.025), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? .white.opacity(0.9) : .white.opacity(0.08), lineWidth: selected ? 2 : 0.7))
            #if os(tvOS)
            // Only the focused sleeve casts a small shadow. All existing lift
            // and spring animations remain attached to this individual item.
            .shadow(color: .black.opacity(selected ? 0.30 : 0), radius: selected ? 6 : 0, y: selected ? 4 : 0)
            #else
            .shadow(color: .black.opacity(selected ? 0.42 : 0.18), radius: selected ? 14 : 3, y: selected ? 9 : 2)
            #endif
            .scaleEffect(!reduceMotion && selected ? 1.035 : 1, anchor: .bottom)
            .offset(y: !reduceMotion && selected ? -7 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: selected)
        }.buttonStyle(FluxBareButtonStyle())
         .id(id)
         .zIndex(selected ? 1 : 0)
         .accessibilityLabel("\(title), \(season.episodes.count) épisodes")
         .accessibilityHint("Ouvrir cette saison pour choisir un épisode.")
         .accessibilityIdentifier("season-sleeve-\(season.number)")
        #if os(tvOS)
         .focused(systemFocus, equals: id).focusEffectDisabled()
         .fluxPointerTarget(id, systemFocus)
        #if FLUX_CATALOG_UI_TESTING
         .background(TVCatalogControlFrameProbe(identifier: "season-sleeve-\(season.number)").allowsHitTesting(false))
        #endif
        #else
         .focusable().focused(systemFocus, equals: id).focusEffectDisabled()
         .onHover { inside in if inside { focus(season) } }
        #endif
    }
}

private struct SeasonSleeveHero: ViewModifier {
    let namespace: Namespace.ID?
    let id: String
    let held: Bool
    let expanded: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if let namespace {
            content
                .matchedGeometryEffect(id: id, in: namespace, properties: .frame, anchor: .center, isSource: !(held && expanded))
                .opacity(held ? 0 : 1)
        } else { content }
    }
}
