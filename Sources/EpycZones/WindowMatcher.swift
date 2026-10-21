/// Pairs saved window descriptions with the windows open now.
///
/// A saved entry matches an open window of the same app with the same title.
/// An untitled entry matches only when its app has exactly one open window,
/// because nothing else identifies it. Each open window is used at most once,
/// so two entries never move the same window.
enum WindowMatcher {
    struct Window: Equatable {
        let bundleID: String
        let title: String
    }

    /// - Returns: For each matched saved index, the index of its open window.
    static func match(saved: [Window], open: [Window]) -> [Int: Int] {
        var matches: [Int: Int] = [:]
        var used = Set<Int>()

        for (savedIndex, entry) in saved.enumerated() where !entry.title.isEmpty {
            guard let openIndex = open.indices.first(where: { !used.contains($0) && open[$0] == entry }) else {
                continue
            }
            matches[savedIndex] = openIndex
            used.insert(openIndex)
        }

        for (savedIndex, entry) in saved.enumerated() where entry.title.isEmpty {
            let sameApp = open.indices.filter { open[$0].bundleID == entry.bundleID }
            guard sameApp.count == 1, let only = sameApp.first, !used.contains(only) else { continue }
            matches[savedIndex] = only
            used.insert(only)
        }

        return matches
    }
}
