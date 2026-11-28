import XCTest
@testable import FluxIPTVCore

final class SynopsisPagesTests: XCTestCase {
    private let words = ["Dans", "une", "ville", "où", "les", "ombres", "racontent", "des", "histoires", "anciennes,",
                         "une", "enquêtrice", "obstinée", "découvre", "que", "les", "disparitions", "récentes", "sont",
                         "liées", "à", "un", "secret", "de", "famille", "—", "l’usine", "fermée", "depuis", "trente", "ans."]

    private func text(_ count: Int, separator: (Int) -> String = { _ in " " }) -> String {
        (0..<count).map { (($0 > 0) ? separator($0) : "") + words[$0 % words.count] }.joined()
    }

    /// The pages hold every word in its order, cut between words, and none is
    /// longer than its length and a space unless a single word is.
    func testThePagesKeepEveryWordAndTheirLength() {
        let separators: [(Int) -> String] = [{ _ in " " }, { $0 % 7 == 0 ? "\n\n" : $0 % 5 == 0 ? "\t " : " " }]
        for count in [0, 1, 12, 90, 260, 900] {
            for separator in separators {
                let synopsis = text(count, separator: separator)
                for length in [40, 520, 850] {
                    let pages = SynopsisPages.split(synopsis, length: length)
                    XCTAssertFalse(pages.isEmpty)
                    let kept = synopsis.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                    XCTAssertEqual(pages.flatMap { $0.split(separator: " ").map(String.init) }, kept, "\(count) \(length)")
                    for page in pages where page.contains(" ") { XCTAssertLessThanOrEqual(page.count, length + 1) }
                }
            }
        }
        XCTAssertEqual(SynopsisPages.split("", length: 520), [""])
        XCTAssertEqual(SynopsisPages.split(" \n ", length: 520), [" \n "])
        XCTAssertEqual(SynopsisPages.split("un deux", length: 3), ["un", "deux"])
    }

    /// The pages are cut once for each text kept (0.9.10): read again, after
    /// another text, another length or the same ones, they are those of their
    /// text.
    /// Its cache lives on the main actor, where the tests run: a class
    /// whose tests are not all isolated alike does not build under Linux.
    func testThePagesReadAgainAreThoseOfTheirText() { MainActor.assumeIsolated {
        let long = text(400), short = text(30), accented = "Été " + text(200) + " ﬁn"
        let readings: [(String, Int)] = [(long, 520), (long, 520), (long, 850), (short, 520), ("", 520),
                                         (accented, 520), (long, 520), (accented, 520), (accented, 40), ("", 850), (long, 520)]
        for (synopsis, length) in readings {
            XCTAssertEqual(SynopsisPages.reading(synopsis, length: length), SynopsisPages.split(synopsis, length: length), "\(synopsis.count) \(length)")
        }
        // The same characters written another way are not the same text.
        let composed = "Café " + text(80), decomposed = "Cafe\u{301} " + text(80)
        XCTAssertEqual(SynopsisPages.reading(composed, length: 40), SynopsisPages.split(composed, length: 40))
        XCTAssertEqual(SynopsisPages.reading(decomposed, length: 40), SynopsisPages.split(decomposed, length: 40))
        XCTAssertEqual(SynopsisPages.reading(decomposed, length: 40).first?.unicodeScalars.contains("\u{301}"), true)
    } }
}
