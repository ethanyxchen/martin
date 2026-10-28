import AppKit
import MartinKit
import SwiftUI

@MainActor
final class Dropdown {
    struct Choice: Hashable {
        let badge: String
        let title: String
        var detail: String?
    }

    struct Section: Hashable {
        var title: String?
        let choices: [Choice]
    }

    @Observable
    final class Choices {
        var sections: [Section] = []
        var query = ""
        var selected = 0

        var count: Int { sections.map(\.choices.count).reduce(0, +) }

        func offset(of section: Int) -> Int {
            sections[..<section].map(\.choices.count).reduce(0, +)
        }
    }

    static let width: CGFloat = 288
    static let row: CGFloat = 42
    static let header: CGFloat = 24
    static let inset: CGFloat = 5
    static let corner: CGFloat = 7
    static let padding: CGFloat = 9
    static let avatar: CGFloat = 26
    static let spacing: CGFloat = 10
    private static let tallest: CGFloat = 300

    private let choices = Choices()
    private let pick: (Int) -> Void
    private var panel: NSPanel?

    init(pick: @escaping (Int) -> Void) {
        self.pick = pick
    }

    var isShown: Bool { panel?.isVisible == true }

    var selection: Int? {
        choices.count > choices.selected ? choices.selected : nil
    }

    func show(_ sections: [Section], matching query: String, under anchor: NSRect, in window: NSWindow) {
        if sections != choices.sections { choices.selected = 0 }
        choices.sections = sections
        choices.query = query
        let panel = panel ?? makePanel()
        let content = CGFloat(choices.count) * Self.row + CGFloat(sections.filter { $0.title != nil }.count) * Self.header + 2 * Self.inset
        let height = min(content, Self.tallest)
        let x = anchor.minX - Self.inset - Self.padding - Self.avatar - Self.spacing
        var frame = NSRect(x: x, y: anchor.minY - 6 - height, width: Self.width, height: height)
        if let screen = window.screen?.visibleFrame, frame.minY < screen.minY { frame.origin.y = anchor.maxY + 6 }
        panel.setFrame(frame, display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func move(by step: Int) {
        guard choices.count > 0 else { return }
        choices.selected = (choices.selected + step + choices.count) % choices.count
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: DropdownList(choices: choices, pick: pick))
        self.panel = panel
        return panel
    }
}

private struct DropdownList: View {
    let choices: Dropdown.Choices
    let pick: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(choices.sections.indices, id: \.self) { section in
                        if let title = choices.sections[section].title {
                            Text(title.uppercased())
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(Theme.tertiary)
                                .padding(.horizontal, Dropdown.padding)
                                .frame(height: Dropdown.header, alignment: .center)
                        }
                        let offset = choices.offset(of: section)
                        ForEach(Array(choices.sections[section].choices.enumerated()), id: \.offset) { row, choice in
                            let index = offset + row
                            DropdownRow(choice: choice, query: choices.query, selected: index == choices.selected)
                                .id(index)
                                .onHover { if $0 { choices.selected = index } }
                                .onTapGesture { pick(index) }
                        }
                    }
                }
                .padding(Dropdown.inset)
            }
            .scrollIndicators(.never)
            .onChange(of: choices.selected) { proxy.scrollTo(choices.selected) }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: Dropdown.corner + Dropdown.inset))
    }
}

private struct DropdownRow: View {
    let choice: Dropdown.Choice
    let query: String
    let selected: Bool

    var body: some View {
        HStack(spacing: Dropdown.spacing) {
            Text(choice.badge)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.cobalt)
                .frame(width: Dropdown.avatar, height: Dropdown.avatar)
                .background(Theme.cobalt.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(highlighted(choice.title))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                if let detail = choice.detail {
                    Text(highlighted(detail))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Dropdown.padding)
        .frame(height: Dropdown.row)
        .background(selected ? Theme.cobalt.opacity(0.1) : Theme.cobalt.opacity(0), in: .rect(cornerRadius: Dropdown.corner))
        .contentShape(.rect)
    }

    private func highlighted(_ text: String) -> AttributedString {
        var highlighted = AttributedString(text)
        for match in text.wordMatches(of: query) {
            guard let range = Range(match, in: highlighted) else { continue }
            highlighted[range].foregroundColor = Color(nsColor: Theme.cobalt.ns)
            highlighted[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return highlighted
    }
}

extension String {
    var initials: String {
        String(split { !$0.isLetter }.prefix(2).compactMap(\.first)).uppercased()
    }
}
