struct SwitcherPanelSnapshot {
    var entries: [WindowEntry]
    var searchBuffer: String
    var selectedRow: Int?

    static let empty = SwitcherPanelSnapshot(entries: [], searchBuffer: "", selectedRow: nil)
}

enum SwitcherPanelAction {
    case cancel
    case commit
    case moveSelection(delta: Int)
    case appendSearchCharacter(Character)
    case deleteLastSearchCharacter
    case selectFilteredRow(Int)
    case commitFilteredRow(Int)
}
