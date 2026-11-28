import Foundation

/// The pages of a synopsis, as the full description of a fiche shows them:
/// cut between words, none longer than `length` characters and a space,
/// unless a single word is.
public enum SynopsisPages {
    public static func split(_ text: String, length: Int) -> [String] {
        var pages: [String] = [], current = ""
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            if current.count + word.count > length && !current.isEmpty { pages.append(current); current = "" }
            current += (current.isEmpty ? "" : " ") + String(word)
        }
        if !current.isEmpty { pages.append(current) }
        return pages.isEmpty ? [text] : pages
    }

    /// The pages, cut once for each text kept. The full description read
    /// them five times each time it was drawn, and once more for each press:
    /// cutting a synopsis of 1,500 characters took 140 µs on a Mac, six times
    /// for each page turned (bench of the 0.9.10).
    @MainActor public static func reading(_ text: String, length: Int) -> [String] {
        if let last = lastRead, last.length == length,
           last.text.utf8.count == text.utf8.count, last.text.utf8.elementsEqual(text.utf8) {
            return last.pages
        }
        let pages = split(text, length: length)
        lastRead = (text, length, pages)
        return pages
    }
    @MainActor private static var lastRead: (text: String, length: Int, pages: [String])?
}
