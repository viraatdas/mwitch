import Cocoa
import SwiftUI

struct SwitcherPanelView: View {
    let entries: [WindowEntry]
    let searchBuffer: String
    let selectedRow: Int?
    let scrollTarget: Int?
    let presentationID: Int
    let rowHeight: CGFloat
    let selectionInsetX: CGFloat
    let selectionInsetY: CGFloat
    let selectionCornerRadius: CGFloat
    let onSelect: (Int) -> Void
    let onCommit: (Int) -> Void

    @State private var initialPointerLocation: CGPoint?
    @State private var isHoverSelectionEnabled = false

    private let hoverActivationDistance: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            if !searchBuffer.isEmpty {
                Text("Search: \(searchBuffer)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 26)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { row, entry in
                            SwitcherRowView(
                                entry: entry,
                                isSelected: row == selectedRow,
                                rowHeight: rowHeight,
                                selectionInsetX: selectionInsetX,
                                selectionInsetY: selectionInsetY,
                                selectionCornerRadius: selectionCornerRadius
                            )
                            .id(row)
                            .contentShape(Rectangle())
                            .onContinuousHover(coordinateSpace: .global) { phase in
                                handleRowHover(phase, row: row)
                            }
                            .onTapGesture {
                                onSelect(row)
                                onCommit(row)
                            }
                        }
                    }
                    .padding(6)
                    .contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .global) { phase in
                        updateHoverGate(phase)
                    }
                }
                .onAppear {
                    resetHoverGate()
                    scrollToTarget(proxy)
                }
                .onChange(of: scrollTarget) { _ in
                    scrollToTarget(proxy)
                }
                .onChange(of: presentationID) { _ in
                    resetHoverGate()
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
    }

    private func handleRowHover(_ phase: HoverPhase, row: Int) {
        guard isHoverSelectionEnabled else { return }

        switch phase {
        case .active:
            guard entries.indices.contains(row) else { return }
            guard selectedRow != row else { return }

            onSelect(row)

        case .ended:
            break
        }
    }

    private func updateHoverGate(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            if initialPointerLocation == nil {
                initialPointerLocation = location
                return
            }

            guard !isHoverSelectionEnabled else { return }
            guard let initialPointerLocation else { return }

            let distanceFromInitial = hypot(
                location.x - initialPointerLocation.x,
                location.y - initialPointerLocation.y
            )

            if distanceFromInitial >= hoverActivationDistance {
                isHoverSelectionEnabled = true
            }

        case .ended:
            resetHoverGate()
        }
    }

    private func resetHoverGate() {
        initialPointerLocation = nil
        isHoverSelectionEnabled = false
    }

    private func scrollToTarget(_ proxy: ScrollViewProxy) {
        guard let scrollTarget, entries.indices.contains(scrollTarget) else { return }
        proxy.scrollTo(scrollTarget)
    }
}

private struct SwitcherRowView: View {
    let entry: WindowEntry
    let isSelected: Bool
    let rowHeight: CGFloat
    let selectionInsetX: CGFloat
    let selectionInsetY: CGFloat
    let selectionCornerRadius: CGFloat

    private let appWidth: CGFloat = 220
    private let iconSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.appName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color(nsColor: .secondaryLabelColor))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(width: appWidth, alignment: .trailing)

            Group {
                if let appIcon = entry.appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: iconSize, height: iconSize)

            Text(entry.title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? Color.white : Color(nsColor: .labelColor))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: rowHeight)
        .background(alignment: .center) {
            if isSelected {
                RoundedRectangle(cornerRadius: selectionCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlAccentColor))
                    .padding(.horizontal, selectionInsetX)
                    .padding(.vertical, selectionInsetY)
            }
        }
    }
}
