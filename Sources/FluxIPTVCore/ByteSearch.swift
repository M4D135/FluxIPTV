#if canImport(Darwin)
import Darwin
#endif

/// The search of a run of bytes in another one: `memmem` on the systems of
/// Apple, a plain loop elsewhere (the tests of the core also run on Linux,
/// whose C library declares `memmem` only for GNU sources).
enum ByteSearch {
    /// Whether the `count` bytes from `text` hold the `termCount` bytes from `term`.
    static func contains(_ text: UnsafePointer<UInt8>, _ count: Int,
                         _ term: UnsafePointer<UInt8>, _ termCount: Int) -> Bool {
        guard termCount > 0 else { return true }
        guard termCount <= count else { return false }
        #if canImport(Darwin)
        return memmem(text, count, term, termCount) != nil
        #else
        let first = term[0], last = count - termCount
        var start = 0
        while start <= last {
            if text[start] == first {
                var offset = 1
                while offset < termCount, text[start + offset] == term[offset] { offset += 1 }
                if offset == termCount { return true }
            }
            start += 1
        }
        return false
        #endif
    }

    static func contains(_ text: UnsafeBufferPointer<UInt8>, _ term: UnsafeBufferPointer<UInt8>) -> Bool {
        guard !term.isEmpty else { return true }
        guard let base = text.baseAddress, let wanted = term.baseAddress else { return false }
        return contains(base, text.count, wanted, term.count)
    }
}
