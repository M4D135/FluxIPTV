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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: max(1, columns)), spacing: 18) {
                ForEach(seasons) { season in seasonButton(season) }
            }.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 24)
        }
    }

    private func seasonButton(_ season: IPTVSeason) -> some View {
        let id = Self.focusID(season), selected = focusedID == id
        let title = Self.title(season)
        return Button { focus(season); open(season) } label: {
            VStack(alignment: .leading, spacing: 6) {
                CatalogSleeveArtwork(item: Self.sleeve(series: series, season: season))
                    .aspectRatio(2.0/3.0, contentMode: .fit)
                HStack(spacing: 5) {
                    Text(title).font(.headline).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(CasePackageFormat.resolve(year: series.details.year).title)
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text("\(season.episodes.count) épisodes").font(.caption).foregroundStyle(.secondary)
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
        #if os(tvOS)
         .focused(systemFocus, equals: id).focusEffectDisabled()
        #else
         .focusable().focused(systemFocus, equals: id).focusEffectDisabled()
         .onHover { inside in if inside { focus(season) } }
        #endif
    }
}
