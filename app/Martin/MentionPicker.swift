import AppKit
import MartinKit
import SwiftUI

@MainActor
final class MentionPicker {
    @Observable
    final class Choices {
        var people: [Person] = []
        var attending: Set<String> = []
        var query = ""
        var selected = 0

        var sections: [(title: String, rows: [Int])] {
            let present = people.indices.filter { attending.contains(people[$0].email) }
            let absent = people.indices.filter { !attending.contains(people[$0].email) }
            return [("In this meeting", present), ("Earlier meetings", absent)].filter { !$0.rows.isEmpty }
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
    private let pick: (Person) -> Void
    private var panel: NSPanel?

    init(pick: @escaping (Person) -> Void) {
        self.pick = pick
    }

    var isShown: Bool { panel?.isVisible == true }

    var selection: Person? {
        choices.people.indices.contains(choices.selected) ? choices.people[choices.selected] : nil
    }

    func show(_ people: [Person], attending: Set<String>, matching query: String, under anchor: NSRect, in window: NSWindow) {
        if people != choices.people { choices.selected = 0 }
        choices.people = people
        choices.attending = attending
        choices.query = query
        let panel = panel ?? makePanel()
        let content = CGFloat(people.count) * Self.row + CGFloat(choices.sections.count) * Self.header + 2 * Self.inset
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
        guard !choices.people.isEmpty else { return }
        choices.selected = (choices.selected + step + choices.people.count) % choices.people.count
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
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: MentionList(choices: choices, pick: pick))
        self.panel = panel
        return panel
    }
}

private struct MentionList: View {
    let choices: MentionPicker.Choices
    let pick: (Person) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(choices.sections, id: \.title) { section in
                        Text(section.title.uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(Theme.tertiary)
                            .padding(.horizontal, MentionPicker.padding)
                            .frame(height: MentionPicker.header, alignment: .center)
                        ForEach(section.rows, id: \.self) { index in
                            let person = choices.people[index]
                            MentionRow(person: person, query: choices.query, selected: index == choices.selected)
                                .id(index)
                                .onHover { if $0 { choices.selected = index } }
                                .onTapGesture { pick(person) }
                        }
                    }
                }
                .padding(MentionPicker.inset)
            }
            .scrollIndicators(.never)
            .onChange(of: choices.selected) { proxy.scrollTo(choices.selected) }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: MentionPicker.corner + MentionPicker.inset))
    }
}

private struct MentionRow: View {
    let person: Person
    let query: String
    let selected: Bool

    var body: some View {
        HStack(spacing: MentionPicker.spacing) {
            Text(initials)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.cobalt)
                .frame(width: MentionPicker.avatar, height: MentionPicker.avatar)
                .background(Theme.cobalt.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(highlighted(person.displayName))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(highlighted(person.email))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MentionPicker.padding)
        .frame(height: MentionPicker.row)
        .background(selected ? Theme.cobalt.opacity(0.1) : Theme.cobalt.opacity(0), in: .rect(cornerRadius: MentionPicker.corner))
        .contentShape(.rect)
    }

    private func highlighted(_ text: String) -> AttributedString {
        var highlighted = AttributedString(text)
        for match in Person.matches(of: query, in: text) {
            guard let range = Range(match, in: highlighted) else { continue }
            highlighted[range].foregroundColor = Color(nsColor: Theme.cobalt.ns)
            highlighted[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return highlighted
    }

    private var initials: String {
        String(person.displayName.split { !$0.isLetter }.prefix(2).compactMap(\.first)).uppercased()
    }
}
