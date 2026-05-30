import Cocoa

/// Pure list/search state for the switcher panel.
///
/// The UI table only knows about rows in `filtered`, but `SwitcherController`
/// owns selection as an index into the full `entries` array because that is what
/// gets committed. This type keeps those two coordinate systems in sync and
/// returns the index the caller needs after each state transition.
struct SwitcherListState {
    private(set) var entries: [WindowEntry] = []
    private(set) var filtered: [WindowEntry] = []
    private(set) var searchBuffer: String = ""

    /// Selected row in `filtered`, not an index into `entries`.
    private(set) var selectedRow: Int?

    /// Replaces the full list and returns the visible row for `selection`, if it
    /// is still present after filtering.
    mutating func update(entries: [WindowEntry], selection: Int) -> Int? {
        self.entries = entries
        filtered = entries
        searchBuffer = ""
        return selectAbsolute(selection)
    }

    /// Accepts the controller's absolute selection index and returns the row the
    /// table should highlight in the current filtered list.
    mutating func setSelection(absoluteIndex: Int) -> Int? {
        selectAbsolute(absoluteIndex)
    }

    mutating func clearSelection() {
        selectedRow = nil
    }

    /// Updates the search text and returns the absolute index that should become
    /// the controller selection. A nil return means the filter has no matches.
    mutating func appendSearchCharacter(_ character: Character) -> Int? {
        searchBuffer.append(character)
        return applyFilter()
    }

    /// Removes one search character and returns the absolute index now selected.
    mutating func deleteLastSearchCharacter() -> Int? {
        guard !searchBuffer.isEmpty else { return selectedAbsoluteIndex }
        searchBuffer.removeLast()
        return applyFilter()
    }

    /// Moves within the visible filtered rows and returns the matching absolute
    /// index for the controller.
    mutating func moveSelection(by delta: Int) -> Int? {
        guard !filtered.isEmpty else {
            selectedRow = nil
            return nil
        }

        let current = selectedRow ?? 0
        let next = (current + delta + filtered.count) % filtered.count
        selectedRow = next
        return absoluteIndex(forFilteredRow: next)
    }

    /// Converts a table row in `filtered` to the matching index in `entries`.
    func absoluteIndex(forFilteredRow row: Int) -> Int? {
        guard filtered.indices.contains(row) else { return nil }
        return entries.firstIndex(of: filtered[row])
    }

    /// Current selection expressed in the controller's full-list coordinate
    /// system.
    var selectedAbsoluteIndex: Int? {
        guard let selectedRow else { return nil }
        return absoluteIndex(forFilteredRow: selectedRow)
    }

    private mutating func selectAbsolute(_ index: Int) -> Int? {
        guard entries.indices.contains(index) else {
            selectedRow = nil
            return nil
        }
        guard let row = filtered.firstIndex(of: entries[index]) else {
            selectedRow = nil
            return nil
        }
        selectedRow = row
        return row
    }

    private mutating func applyFilter() -> Int? {
        let needle = searchBuffer.lowercased()
        if needle.isEmpty {
            filtered = entries
        } else {
            filtered = SwitcherSearch.rankedResults(for: entries, query: needle)
        }

        guard !filtered.isEmpty else {
            selectedRow = nil
            return nil
        }

        selectedRow = 0
        return absoluteIndex(forFilteredRow: 0)
    }

}
