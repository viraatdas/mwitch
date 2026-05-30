struct SwitcherSession {
    private(set) var listState = SwitcherListState()
    private(set) var isVisible = false

    var entries: [WindowEntry] { listState.entries }
    var selection: Int { listState.selectedAbsoluteIndex ?? -1 }
    var snapshot: SwitcherPanelSnapshot { listState.snapshot }

    mutating func start(entries: [WindowEntry]) -> SwitcherSessionResult {
        guard !entries.isEmpty else { return .none }
        let initialSelection = entries.count > 1 ? 1 : 0
        _ = listState.update(entries: entries, selection: initialSelection)
        isVisible = true
        return .render(scrollTarget: listState.selectedRow, reposition: false)
    }

    mutating func setSelection(_ index: Int) -> SwitcherSessionResult {
        guard listState.setSelection(absoluteIndex: index) != nil else { return .none }
        return .render(scrollTarget: nil, reposition: false)
    }

    mutating func clearSelection() -> SwitcherSessionResult {
        listState.clearSelection()
        return .render(scrollTarget: nil, reposition: false)
    }

    mutating func perform(_ action: SwitcherPanelAction) -> SwitcherSessionResult {
        switch action {
        case .cancel:
            guard isVisible else { return .none }
            isVisible = false
            return .dismiss(chosen: nil)
        case .commit:
            return commit()
        case .moveSelection(let delta):
            return moveSelection(by: delta)
        case .appendSearchCharacter(let character):
            _ = listState.appendSearchCharacter(character)
            return .render(scrollTarget: listState.selectedRow, reposition: true)
        case .deleteLastSearchCharacter:
            _ = listState.deleteLastSearchCharacter()
            return .render(scrollTarget: listState.selectedRow, reposition: true)
        case .selectFilteredRow(let row):
            guard listState.selectedRow != row,
                  listState.selectFilteredRow(row) != nil else { return .none }
            return .render(scrollTarget: nil, reposition: false)
        case .commitFilteredRow(let row):
            guard listState.selectFilteredRow(row) != nil else { return .none }
            return commit()
        }
    }

    private mutating func moveSelection(by delta: Int) -> SwitcherSessionResult {
        guard listState.moveSelection(by: delta) != nil else {
            listState.clearSelection()
            return .render(scrollTarget: nil, reposition: false)
        }
        return .render(scrollTarget: listState.selectedRow, reposition: false)
    }

    private mutating func commit() -> SwitcherSessionResult {
        guard isVisible else { return .none }
        let chosen = entries.indices.contains(selection) ? entries[selection] : nil
        isVisible = false
        return .dismiss(chosen: chosen)
    }
}

enum SwitcherSessionResult: Equatable {
    case none
    case render(scrollTarget: Int?, reposition: Bool)
    case dismiss(chosen: WindowEntry?)
}
