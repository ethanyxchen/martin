import AppKit
import MartinKit
import SwiftUI

@MainActor
final class MentionPicker {
    @Observable
    final class Choices {
        var people: [Person] = []
        var selected = 0
    }

    static let width: CGFloat = 288
    static let row: CGFloat = 42
    static let inset: CGFloat = 5
    static let padding: CGFloat = 9
    static let avatar: CGFloat = 26
    static let spacing: CGFloat = 10
    private static let visibleRows = 6

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

    func show(_ people: [Person], under anchor: NSRect, in window: NSWindow) {
        if people != choices.people { choices.selected = 0 }
        choices.people = people
        let panel = panel ?? makePanel()
        let height = CGFloat(min(people.count, Self.visibleRows)) * Self.row + 2 * Self.inset
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
        panel.hasShadow = true
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
                VStack(spacing: 0) {
                    ForEach(Array(choices.people.enumerated()), id: \.element.email) { index, person in
                        MentionRow(person: person, selected: index == choices.selected)
                            .id(index)
                            .onHover { if $0 { choices.selected = index } }
                            .onTapGesture { pick(person) }
                    }
                }
                .padding(MentionPicker.inset)
            }
            .scrollIndicators(.never)
            .onChange(of: choices.selected) { proxy.scrollTo(choices.selected) }
        }
        .background(Theme.paper, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.ink.opacity(0.1), lineWidth: 0.5))
    }
}

private struct MentionRow: View {
    let person: Person
    let selected: Bool

    var body: some View {
        HStack(spacing: MentionPicker.spacing) {
            Text(initials)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.cobalt)
                .frame(width: MentionPicker.avatar, height: MentionPicker.avatar)
                .background(Theme.cobalt.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(person.email)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MentionPicker.padding)
        .frame(height: MentionPicker.row)
        .background(selected ? Theme.cobalt.opacity(0.1) : Theme.cobalt.opacity(0), in: .rect(cornerRadius: 7))
        .contentShape(.rect)
    }

    private var initials: String {
        String(person.displayName.split { !$0.isLetter }.prefix(2).compactMap(\.first)).uppercased()
    }
}
