protocol SwitcherPanelDelegate: AnyObject {
    var switcherPanelIsActive: Bool { get }
    func switcherPanel(_ panel: SwitcherPanel, didPerform action: SwitcherPanelAction)
}
