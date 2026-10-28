import AppKit
import MartinKit
import SwiftUI

enum ProjectOption: Hashable {
    case project(Project)
    case new(String)
    case unassigned

    static func options(for query: String, in projects: [Project]) -> (matches: [ProjectOption], others: [ProjectOption]) {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = projects.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let others: [ProjectOption] = name.isEmpty ? [.unassigned] : taken ? [] : [.new(name)]
        return (projects.suggestions(for: name).map(ProjectOption.project), others)
    }

    var title: String {
        switch self {
        case .project(let project): project.name
        case .new(let name): "Create “\(name)”"
        case .unassigned: "Unassigned"
        }
    }
}

struct ProjectChip: View {
    let app: AppState
    let meeting: Meeting
    @State private var picking = false

    var body: some View {
        let project = app.project(of: meeting)
        Button { picking = true } label: {
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
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            ProjectPicker(projects: app.projects, current: meeting.project) { option in
                picking = false
                switch option {
                case .project(let project): app.file(meeting, in: project.id)
                case .new(let name): app.file(meeting, inNewProjectNamed: name)
                case .unassigned: app.file(meeting, in: nil)
                }
            }
        }
    }
}

private struct ProjectPicker: View {
    private static let row: CGFloat = 24
    private static let tallest: CGFloat = 264
    let projects: [Project]
    let current: Project.ID?
    let pick: (ProjectOption) -> Void
    @State private var query = ""
    @State private var selected = 0

    var body: some View {
        let (matches, others) = ProjectOption.options(for: query, in: projects)
        let options = matches + others
        VStack(alignment: .leading, spacing: 4) {
            SearchField(text: $query, prompt: "Find or create a project") { step in
                if let step {
                    selected = (selected + step + options.count) % options.count
                } else if options.indices.contains(selected) {
                    pick(options[selected])
                }
            }
            .padding(.bottom, 2)
            if matches.isEmpty, !query.isEmpty {
                Text("No matching projects")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: Self.row)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.element) { index, option in
                            row(option, at: index)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: min(CGFloat(matches.count) * Self.row, Self.tallest))
                .onChange(of: selected) { proxy.scrollTo(options[selected]) }
            }
            if !others.isEmpty {
                if !matches.isEmpty || !query.isEmpty { Divider().padding(.horizontal, 6) }
                ForEach(Array(others.enumerated()), id: \.element) { index, option in
                    row(option, at: matches.count + index)
                }
            }
        }
        .padding(6)
        .frame(width: 240)
        .onChange(of: query) { selected = 0 }
    }

    private func row(_ option: ProjectOption, at index: Int) -> some View {
        let chosen = index == selected
        return HStack(spacing: 7) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .opacity(ticked(option) ? 1 : 0)
            switch option {
            case .project(let project):
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Avatar.hue(of: project.name))
                    .frame(width: 12, height: 12)
            case .new:
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12)
            case .unassigned:
                EmptyView()
            }
            Text(option.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(chosen ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.ink))
        .padding(.horizontal, 7)
        .frame(height: Self.row)
        .background(chosen ? AnyShapeStyle(Theme.cobalt) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 5))
        .contentShape(.rect)
        .id(option)
        .onHover { if $0 { selected = index } }
        .onTapGesture { pick(option) }
    }

    private func ticked(_ option: ProjectOption) -> Bool {
        switch option {
        case .project(let project): project.id == current
        case .unassigned: current == nil
        case .new: false
        }
    }
}

private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let command: (Int?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(field: self)
    }

    func makeNSView(context: Context) -> FocusedSearchField {
        let field = FocusedSearchField()
        field.placeholderString = prompt
        field.focusRingType = .none
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: FocusedSearchField, context: Context) {
        context.coordinator.field = self
        if field.stringValue != text { field.stringValue = text }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var field: SearchField

        init(field: SearchField) {
            self.field = field
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let search = notification.object as? NSSearchField else { return }
            field.text = search.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): field.command(-1)
            case #selector(NSResponder.moveDown(_:)): field.command(1)
            case #selector(NSResponder.insertNewline(_:)): field.command(nil)
            default: return false
            }
            return true
        }
    }
}

final class FocusedSearchField: NSSearchField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}
