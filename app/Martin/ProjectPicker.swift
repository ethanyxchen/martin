import AppKit
import MartinKit
import SwiftUI

enum ProjectOption: Hashable {
    case project(Project)
    case new(String)
    case unassigned

    static func options(for query: String, in projects: [Project], current: Project.ID?) -> (matches: [ProjectOption], others: [ProjectOption]) {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = projects.suggestions(for: name).filter { $0.id != current }
        let taken = projects.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let others = (name.isEmpty || taken ? [] : [ProjectOption.new(name)]) + (current == nil ? [] : [.unassigned])
        return (matches.map(ProjectOption.project), others)
    }

    var choice: Dropdown.Choice {
        switch self {
        case .project(let project): Dropdown.Choice(badge: project.name.initials, title: project.name)
        case .new(let name): Dropdown.Choice(badge: "+", title: "New project “\(name)”")
        case .unassigned: Dropdown.Choice(badge: "–", title: "Unassigned")
        }
    }
}

struct ProjectChip: View {
    let app: AppState
    let meeting: Meeting
    @State private var editing = false

    var body: some View {
        if editing {
            ProjectField(projects: app.projects, current: meeting.project) { option in
                editing = false
                switch option {
                case .project(let project): app.file(meeting, in: project.id)
                case .new(let name): app.file(meeting, inNewProjectNamed: name)
                case .unassigned: app.file(meeting, in: nil)
                case nil: break
                }
            }
            .frame(width: 180)
        } else {
            let project = app.project(of: meeting)
            Button { editing = true } label: {
                Label(project?.name ?? "Unassigned", systemImage: "folder")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(project == nil ? AnyShapeStyle(Theme.secondary) : AnyShapeStyle(Theme.cobalt))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(project == nil ? AnyShapeStyle(Theme.well) : AnyShapeStyle(Theme.cobalt.opacity(0.1)), in: .capsule)
            }
            .buttonStyle(Pressable())
            .pointerStyle(.link)
            .help("Move to Project")
        }
    }
}

struct ProjectField: NSViewRepresentable {
    let projects: [Project]
    let current: Project.ID?
    let done: (ProjectOption?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(field: self)
    }

    func makeNSView(context: Context) -> FocusedField {
        let field = FocusedField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 11.5, weight: .medium)
        field.placeholderString = "Find or create a project"
        field.delegate = context.coordinator
        field.focused = { [weak coordinator = context.coordinator] in coordinator?.refresh() }
        context.coordinator.text = field
        return field
    }

    func updateNSView(_ field: FocusedField, context: Context) {
        context.coordinator.field = self
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var field: ProjectField
        private var options: [ProjectOption] = []
        weak var text: NSTextField?
        private lazy var dropdown = Dropdown { [weak self] in self?.choose($0) }

        init(field: ProjectField) {
            self.field = field
        }

        func refresh() {
            guard let text, let window = text.window else { return }
            let (matches, others) = ProjectOption.options(for: text.stringValue, in: field.projects, current: field.current)
            options = matches + others
            guard !options.isEmpty else { return dropdown.hide() }
            let sections = [Dropdown.Section(title: "Projects", choices: matches.map(\.choice)), Dropdown.Section(choices: others.map(\.choice))]
            dropdown.show(sections.filter { !$0.choices.isEmpty }, matching: text.stringValue, under: window.convertToScreen(text.convert(text.bounds, to: nil)), in: window)
        }

        func controlTextDidChange(_ notification: Notification) {
            refresh()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            dropdown.hide()
            field.done(nil)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): dropdown.move(by: -1)
            case #selector(NSResponder.moveDown(_:)): dropdown.move(by: 1)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)): dropdown.selection.map(choose)
            case #selector(NSResponder.cancelOperation(_:)): control.window?.makeFirstResponder(nil)
            default: return false
            }
            return true
        }

        private func choose(_ index: Int) {
            dropdown.hide()
            field.done(options[index])
        }
    }
}

final class FocusedField: NSTextField {
    var focused: () -> Void = {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.makeFirstResponder(self)
        DispatchQueue.main.async { [weak self] in self?.focused() }
    }
}
