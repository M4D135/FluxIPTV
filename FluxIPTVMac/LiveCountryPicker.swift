import SwiftUI

/// The choices always come from the complete TV catalogue, so an empty search
/// cannot hide the country needed to recover from that search.
struct LiveCountryPicker: View {
    let countries: [LiveCountry]
    let selection: String?
    let select: (String?) -> Void
    let close: () -> Void
    @FocusState private var focusedCountry: String?
    #if os(tvOS)
    @State private var awaitingInitialFocus = true
    #endif

    private var allCount: Int { countries.reduce(0) { $0 + $1.channelCount } }
    private var initialFocusKey: String {
        guard let selection, countries.contains(where: { $0.code == selection }) else { return "all" }
        return selection
    }
    private var rowFont: Font {
        #if os(tvOS)
        .system(size: 27, weight: .semibold)
        #else
        .headline
        #endif
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pays des chaînes").font(.largeTitle.bold())
                    Text("Choisissez un pays pour retrouver ses chaînes et ses catégories.")
                        .font(.body).foregroundStyle(.secondary)
                    countryRow(code: nil, name: "Tous les pays", count: allCount)
                    ForEach(countries) { country in
                        countryRow(code: country.code, name: country.name, count: country.channelCount)
                    }
                    Button("Fermer", action: close)
                        .font(rowFont).padding(.vertical, 16).padding(.horizontal, 20)
                        .buttonStyle(FluxBareButtonStyle())
                        .background(.white.opacity(focusedCountry == "close" ? 0.2 : 0.07),
                                    in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(focusedCountry == "close" ? Color.white : .clear, lineWidth: 2))
                        .focused($focusedCountry, equals: "close").id("close")
                        #if os(tvOS)
                        .focusEffectDisabled()
                        #endif
                }.padding(32)
            }
            .onAppear {
                let target = initialFocusKey
                #if !os(tvOS)
                focusedCountry = target
                #endif
                reader.scrollTo(target, anchor: .center)
            }
            .onChange(of: focusedCountry) { _, code in
                guard let code else { return }
                #if os(tvOS)
                if awaitingInitialFocus {
                    // The first nonnil binding comes from the native sheet's
                    // actual focus entry. onAppear runs before that handoff.
                    // Consume this request before writing the binding so later
                    // remote navigation cannot snap back to the saved country.
                    awaitingInitialFocus = false
                    let target = initialFocusKey
                    #if FLUX_CATALOG_UI_TESTING
                    print("COUNTRY_INITIAL_FOCUS: native=\(code), requested=\(target)")
                    #endif
                    reader.scrollTo(target, anchor: .center)
                    if code != target { focusedCountry = target }
                    return
                }
                #endif
                reader.scrollTo(code, anchor: .center)
            }
        }
        .fluxSheetSize(width: 820, height: 650)
        #if os(tvOS)
        .onExitCommand(perform: close)
        #endif
    }

    private func countryRow(code: String?, name: String, count: Int) -> some View {
        let key = code ?? "all"
        let focused = focusedCountry == key
        let selected = selection == code
        return Button { select(code) } label: {
            HStack(spacing: 18) {
                Image(systemName: code == nil ? "globe" : "globe.europe.africa")
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(rowFont)
                    if let code, code != LiveCountry.unknownCode {
                        Text(code).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                Text("\(count)").font(rowFont.monospacedDigit()).foregroundStyle(.secondary)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.cyan : Color.white.opacity(0.3))
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(.white.opacity(focused ? 0.19 : selected ? 0.11 : 0.055),
                        in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17)
                .strokeBorder(focused ? Color.white : .clear, lineWidth: 3))
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(FluxBareButtonStyle())
        .focused($focusedCountry, equals: key).id(key)
        #if os(tvOS)
        .focusEffectDisabled()
        #if FLUX_CATALOG_UI_TESTING
        .background(TVCatalogControlFrameProbe(identifier: "live-country-option-\(code ?? "all")"))
        #endif
        #endif
        .accessibilityLabel(name)
        .accessibilityIdentifier("live-country-option-\(key)")
        .accessibilityValue("\(count) chaînes\(selected ? ", sélectionné" : "")")
    }
}
