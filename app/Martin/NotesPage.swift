import MartinKit
import SwiftUI

struct NotesView: View {
    let app: AppState

    var body: some View {
        TimelineView(.everyMinute) { context in
            Page {
                PageHeading(title: "Notes")
            } content: {
                NoteList(app: app, meetings: app.pinned + app.unpinned, now: context.date, detail: app.projectName(of:))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Quick Note", systemImage: "square.and.pencil") { app.quickNote() }
                    .help("New Quick Note (⌘N)")
            }
            ArchiveButton(app: app)
        }
    }
}

private struct ArchiveButton: ToolbarContent {
    let app: AppState

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Archive", systemImage: "archivebox") { app.openArchive() }
                .help("Open Archive (⇧⌘A)")
        }
    }
}

struct SecretsToggle: ToolbarContent {
    static let shortcut = KeyboardShortcut("s", modifiers: [.command, .shift])
    @Bindable var app: AppState

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Toggle("Secret Projects", systemImage: "eye", isOn: $app.showsSecrets)
                .help(app.showsSecrets ? "Keep Secret Projects Secret (⇧⌘S)" : "Show Secret Projects (⇧⌘S)")
        }
    }
}

struct ProjectsView: View {
    private static let wide: CGFloat = 860
    private static let sidebar: CGFloat = 280
    private static let slide: TimeInterval = 0.3
    let app: AppState
    @State private var width: CGFloat = 0
    @State private var grown: CGFloat = 0

    var body: some View {
        let shelves = app.shelves
        let open = shelves.first { $0.id == app.selectedShelf }
        TimelineView(.everyMinute) { context in
            HStack(spacing: 0) {
                Page {
                    PageHeading(title: "Projects")
                } content: {
                    Rows(items: shelves, indent: ChatRow.avatarIndent, selected: app.selectedShelf) { shelf in
                        let latest = shelf.meetings.first
                        Button { select(shelf.id == app.selectedShelf ? nil : shelf.id) } label: {
                            ChatRow(avatar: Avatar(title: shelf.project?.name, square: true), title: shelf.title, stamp: latest?.date.stamp(at: context.date), preview: latest.flatMap { app.previews[$0.id] }, count: shelf.meetings.count, selected: shelf.id == app.selectedShelf)
                        }
                        .contextMenu {
                            if let project = shelf.project { ProjectActions(app: app, project: project, placement: .contextMenu) }
                        }
                    }
                    .padding(.horizontal, Theme.edge - ChatRow.inset)
                }
                .frame(minWidth: open == nil ? 0 : Self.sidebar, maxWidth: open == nil ? max(width, Self.sidebar) : Self.sidebar)
                if let open {
                    Divider()
                    ShelfView(app: app, shelf: open, now: context.date)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            SecretsToggle(app: app)
            ArchiveButton(app: app)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: open?.id) { _, id in
            if id == nil, app.selectedShelf != nil { select(nil, animated: false) }
        }
        .onExitCommand { select(nil, animated: false) }
        .onDisappear { select(nil) }
    }

    private func select(_ id: Shelf.ID?, animated: Bool = true) {
        let duration = animated ? Self.slide : 0
        if app.selectedShelf == nil, id != nil {
            grown = max(0, Self.wide - width)
            app.widenHome(by: grown, over: duration)
        } else if app.selectedShelf != nil, id == nil {
            app.widenHome(by: -grown, over: duration)
            grown = 0
        }
        withAnimation(animated ? .drawer(duration) : nil) { app.selectedShelf = id }
    }
}

struct ArchiveView: View {
    let app: AppState

    var body: some View {
        TimelineView(.everyMinute) { context in
            Page(title: "Archive") {
                PageHeading(title: "Archive", detail: app.archive.isEmpty && app.archivedProjects.isEmpty ? "Notes and projects you archive will appear here." : nil)
            } content: {
                if !app.archivedProjects.isEmpty {
                    Rows(items: app.archivedProjects, indent: ChatRow.avatarIndent) { project in
                        let count = app.notes(in: project).count
                        ChatRow(avatar: Avatar(title: project.name, square: true), title: project.name, stamp: project.archivedAt?.stamp(at: context.date), preview: count == 1 ? "1 note" : "\(count) notes", actions: AnyView(ProjectActions(app: app, project: project, placement: .row)))
                            .contextMenu { ProjectActions(app: app, project: project, placement: .contextMenu) }
                    }
                    .padding(.horizontal, Theme.edge - ChatRow.inset)
                }
                NoteList(app: app, meetings: app.archive, now: context.date, detail: app.projectName(of:))
            }
        }
    }
}

private struct NoteList: View {
    let app: AppState
    let meetings: [Meeting]
    let now: Date
    let detail: (Meeting) -> String?

    var body: some View {
        Rows(items: meetings, indent: ChatRow.avatarIndent) { meeting in
            NoteRow(app: app, meeting: meeting, row: ChatRow(avatar: Avatar(title: meeting.title), title: meeting.displayTitle, stamp: meeting.date.stamp(at: now), preview: detail(meeting), pinned: meeting.isPinned))
        }
        .padding(.horizontal, Theme.edge - ChatRow.inset)
    }
}

private struct NoteRow: View {
    let app: AppState
    let meeting: Meeting
    let row: ChatRow

    var body: some View {
        Button { app.open(meeting) } label: { actionable }
            .contextMenu { NoteActions(app: app, meeting: meeting, placement: .contextMenu) }
    }

    private var actionable: ChatRow {
        var row = row
        row.actions = AnyView(NoteActions(app: app, meeting: meeting, placement: .row))
        return row
    }
}

private struct RowAction: ButtonStyle {
    static let size: CGFloat = 26
    static let glyph: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Theme.ink : Theme.secondary)
            .frame(width: Self.size, height: Self.size)
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct NoteMenu: View {
    let app: AppState
    let meeting: Meeting

    var body: some View {
        NoteActions(app: app, meeting: meeting, placement: .menu)
        Divider()
        Button("Open Archive", systemImage: "archivebox.fill") { app.openArchive() }
    }
}

enum ActionPlacement {
    case menu
    case contextMenu
    case row

    func tooltip(_ text: String) -> String {
        self == .row ? text : ""
    }

    func archive(enabled: Bool) -> KeyboardShortcut? {
        shortcut("a", modifiers: [.command, .control], enabled: enabled)
    }

    func secret(enabled: Bool) -> KeyboardShortcut? {
        shortcut("s", modifiers: [.command, .control], enabled: enabled)
    }

    func delete(enabled: Bool) -> KeyboardShortcut? {
        shortcut(.delete, modifiers: [.command, .option], enabled: enabled)
    }

    private func shortcut(_ key: KeyEquivalent, modifiers: EventModifiers, enabled: Bool) -> KeyboardShortcut? {
        self == .menu && enabled ? KeyboardShortcut(key, modifiers: modifiers) : nil
    }
}

struct NoteActions: View {
    let app: AppState
    let meeting: Meeting?
    let placement: ActionPlacement

    var body: some View {
        if placement != .row {
            Menu("Move to Project", systemImage: "folder") {
                ForEach(app.projects) { project in
                    Toggle(project.name, isOn: Binding { meeting?.project == project.id } set: { _ in meeting.map { app.file($0, in: project.id) } })
                }
                if !app.projects.isEmpty { Divider() }
                Toggle("Unassigned", isOn: Binding { meeting?.project == nil } set: { _ in meeting.map { app.file($0, in: nil) } })
            }
            .disabled(meeting == nil)
        }
        if meeting?.archivedAt == nil {
            let pinned = meeting?.isPinned == true
            Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin") { meeting.map { app.pin($0, !pinned) } }
                .help(placement.tooltip(pinned ? "Unpin" : "Pin"))
                .disabled(meeting == nil)
        }
        Group {
            if meeting?.archivedAt == nil {
                Button("Archive", systemImage: "archivebox") { meeting.map(app.archive) }
                    .help(placement.tooltip("Archive"))
            } else {
                Button("Restore", systemImage: "arrow.uturn.backward") { meeting.map(app.restore) }
                    .help(placement.tooltip("Restore"))
            }
        }
        .keyboardShortcut(placement.archive(enabled: meeting != nil))
        .disabled(meeting == nil)
        Button("Delete…", systemImage: "trash", role: .destructive) { meeting.map(app.confirmDeletion) }
            .help(placement.tooltip("Delete"))
            .keyboardShortcut(placement.delete(enabled: meeting != nil))
            .disabled(meeting == nil)
    }
}

struct ProjectActions: View {
    let app: AppState
    let project: Project?
    let placement: ActionPlacement

    var body: some View {
        if project?.archivedAt == nil {
            let secret = project?.isSecret == true
            Button(secret ? "Make Not Secret" : "Make Secret", systemImage: secret ? "eye" : "eye.slash") { project.map { app.keepSecret($0, !secret) } }
                .help(placement.tooltip(secret ? "Make Not Secret" : "Make Secret"))
                .keyboardShortcut(placement.secret(enabled: project != nil))
                .disabled(project == nil)
        }
        Group {
            if project?.archivedAt == nil {
                Button("Archive Project", systemImage: "archivebox") { project.map(app.archive) }
                    .help(placement.tooltip("Archive"))
            } else {
                Button("Restore Project", systemImage: "arrow.uturn.backward") { project.map(app.restore) }
                    .help(placement.tooltip("Restore"))
            }
        }
        .keyboardShortcut(placement.archive(enabled: project != nil))
        .disabled(project == nil)
        Button("Delete Project…", systemImage: "trash", role: .destructive) { project.map(app.confirmDeletion) }
            .help(placement.tooltip("Delete"))
            .keyboardShortcut(placement.delete(enabled: project != nil))
            .disabled(project == nil)
    }
}

private struct ProjectName: View {
    let app: AppState
    let project: Project
    @State private var name: String
    @FocusState private var editing: Bool

    init(app: AppState, project: Project) {
        self.app = app
        self.project = project
        _name = State(initialValue: project.name)
    }

    var body: some View {
        TextField("Project", text: $name)
            .textFieldStyle(.plain)
            .focused($editing)
            .onSubmit { editing = false }
            .onChange(of: editing) {
                guard !editing else { return }
                app.rename(project, to: name)
                name = app.allProjects.first { $0.id == project.id }?.name ?? project.name
            }
            .onDisappear { app.rename(project, to: name) }
    }
}

private struct ShelfView: View {
    let app: AppState
    let shelf: Shelf
    let now: Date

    var body: some View {
        Page {
            HStack(spacing: 12) {
                Avatar(title: shelf.project?.name, square: true)
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        if let project = shelf.project {
                            ProjectName(app: app, project: project).id(project.id)
                        } else {
                            Text(shelf.title)
                        }
                    }
                    .font(Theme.title)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    Text(shelf.meetings.count == 1 ? "1 note" : "\(shelf.meetings.count) notes")
                        .font(Theme.meta)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                Button("New Note", systemImage: "square.and.pencil") { app.quickNote(in: shelf.project?.id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(RowAction())
                    .help("New note in \(shelf.title)")
                if let project = shelf.project {
                    Menu("Project", systemImage: "ellipsis") { ProjectActions(app: app, project: project, placement: .menu) }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .buttonStyle(RowAction())
                }
            }
            .flush()
        } content: {
            NoteList(app: app, meetings: shelf.meetings, now: now) { app.previews[$0.id] }
        }
    }
}

struct Rows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var indent: CGFloat = 0
    var selected: Item.ID?
    @ViewBuilder let row: (Item) -> Row
    @State private var hovered: Item.ID?

    var body: some View {
        let above = Dictionary(uniqueKeysWithValues: zip(items.dropFirst().map(\.id), items.map(\.id)))
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                row(item)
                    .buttonStyle(Pressable(scale: 0.98))
                    .environment(\.hovering, hovered == item.id)
                    .onHover { inside in
                        if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
                    }
                    .overlay(alignment: .top) {
                        if let previous = above[item.id] {
                            Rectangle()
                                .fill(Theme.well)
                                .frame(height: 1)
                                .padding(.leading, ChatRow.inset + indent)
                                .padding(.trailing, ChatRow.inset)
                                .opacity(Self.divides(item.id, below: previous, lit: [hovered, selected]) ? 1 : 0)
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .padding(.bottom, 20)
    }

    static func divides(_ item: Item.ID, below previous: Item.ID, lit: Set<Item.ID?>) -> Bool {
        lit.isDisjoint(with: [item, previous])
    }
}

private extension EnvironmentValues {
    @Entry var hovering = false
}

private struct ChatRow: View {
    static let inset: CGFloat = 10
    static let avatarIndent = Avatar.standard + spacing
    private static let spacing: CGFloat = 12
    var avatar: Avatar?
    let title: String
    var stamp: String?
    let preview: String?
    var count: Int?
    var pinned = false
    var selected = false
    var actions: AnyView?
    @Environment(\.hovering) private var hovering

    var body: some View {
        HStack(spacing: Self.spacing) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(ink)
                Text(preview ?? "No notes")
                    .font(.system(size: 12.5))
                    .foregroundStyle(preview == nil ? faint : quiet)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: .trailing) {
                VStack(alignment: .trailing, spacing: 3) {
                    stamp.map { (pinned ? Text("\(Image(systemName: "pin.fill")) \($0)") : Text($0)).font(Theme.meta.monospacedDigit()) }
                    count.map { Text($0, format: .number).font(.system(size: 11.5).monospacedDigit()) }
                }
                .foregroundStyle(faint)
                .opacity(revealed ? 0 : 1)
                if let actions {
                    HStack(spacing: 0) { actions }
                        .buttonStyle(RowAction())
                        .padding(.trailing, -(RowAction.size - RowAction.glyph) / 2)
                        .opacity(revealed ? 1 : 0)
                        .allowsHitTesting(revealed)
                }
            }
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 9)
        .background(selected ? AnyShapeStyle(Theme.cobalt) : AnyShapeStyle(Theme.well.opacity(hovering ? 1 : 0)), in: .rect(cornerRadius: 9))
        .contentShape(.rect)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointerStyle(.link)
    }

    private var revealed: Bool { hovering && actions != nil }

    private var ink: AnyShapeStyle { selected ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.ink) }
    private var quiet: AnyShapeStyle { selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(Theme.secondary) }
    private var faint: AnyShapeStyle { selected ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(Theme.tertiary) }
}

struct Avatar: View {
    private static let hues: [Color] = [
        Color(red: 0.30, green: 0.49, blue: 0.94),
        Color(red: 0.88, green: 0.47, blue: 0.30),
        Color(red: 0.25, green: 0.65, blue: 0.48),
        Color(red: 0.61, green: 0.42, blue: 0.85),
        Color(red: 0.83, green: 0.35, blue: 0.60),
        Color(red: 0.20, green: 0.62, blue: 0.70),
    ]
    static let standard: CGFloat = 40
    let title: String?
    var size = standard
    var square = false
    @Environment(\.hovering) private var hovering

    var body: some View {
        if let title, let initial = title.first(where: { $0.isLetter || $0.isNumber }) {
            Text(String(initial).uppercased())
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Self.hue(of: title), in: shape)
        } else {
            Image(systemName: "note.text")
                .font(.system(size: size * 0.4))
                .foregroundStyle(Theme.secondary)
                .frame(width: size, height: size)
                .background(hovering ? Theme.paper : Theme.well, in: shape)
        }
    }

    private var shape: AnyShape {
        square ? AnyShape(.rect(cornerRadius: size * 0.26, style: .continuous)) : AnyShape(.circle)
    }

    static func hue(of title: String) -> Color {
        hues[title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % hues.count]
    }
}

extension Shelf {
    static let unassigned = "Unassigned"
    var title: String { project?.name ?? Self.unassigned }
}

extension Date {
    func stamp(at now: Date) -> String {
        let calendar = Calendar.current
        switch calendar.dateComponents([.day], from: calendar.startOfDay(for: self), to: calendar.startOfDay(for: now)).day ?? 0 {
        case 0: return formatted(date: .omitted, time: .shortened)
        case 1: return "Yesterday"
        case 2..<7: return formatted(.dateTime.weekday(.wide))
        default: return formatted(date: .numeric, time: .omitted)
        }
    }
}
