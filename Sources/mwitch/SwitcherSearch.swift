import Foundation

/// Search policy for switcher entries.
///
/// `WindowEnumerator` already gives us recency/z-order, so search ranking should
/// only reorder when one match is clearly stronger than another. Prefix matches
/// are ranked first because typing the beginning of an app is usually more
/// intentional than a loose fuzzy match. Title prefixes are next, followed by
/// substring and fuzzy matches.
enum SwitcherSearch {
    static func rankedResults(for entries: [WindowEntry], query: String) -> [WindowEntry] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return entries }

        return entries
            .enumerated()
            .compactMap { offset, entry -> SearchResult? in
                guard let rank = rank(needle: needle, entry: entry) else { return nil }
                return SearchResult(entry: entry, rank: rank, offset: offset)
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.offset < rhs.offset
            }
            .map(\.entry)
    }

    private static func rank(needle: String, entry: WindowEntry) -> Int? {
        let appName = entry.appName.lowercased()
        if hasPrefixMatch(needle: needle, haystack: appName) {
            return 0
        }

        let title = entry.title.lowercased()
        if hasPrefixMatch(needle: needle, haystack: title) {
            return 1
        }

        let fields = [appName, title]
        let haystack = fields.joined(separator: " ")
        if haystack.contains(needle) {
            return 2
        }
        if fuzzyMatch(needle: needle, haystack: haystack) {
            return 3
        }
        return nil
    }

    /// Treat the whole field and each whitespace-separated word as prefixable.
    /// That makes "ter" rank Terminal first, and also lets "pre" rank a title
    /// like "Project Preview" ahead of looser fuzzy matches.
    private static func hasPrefixMatch(needle: String, haystack: String) -> Bool {
        haystack.hasPrefix(needle) || haystack.split(separator: " ").contains { $0.hasPrefix(needle) }
    }

    private static func fuzzyMatch(needle: String, haystack: String) -> Bool {
        var idx = haystack.startIndex
        for ch in needle {
            guard let found = haystack[idx...].firstIndex(of: ch) else { return false }
            idx = haystack.index(after: found)
        }
        return true
    }

    private struct SearchResult {
        let entry: WindowEntry
        let rank: Int
        let offset: Int
    }
}
