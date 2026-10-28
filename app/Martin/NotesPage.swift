import MartinKit
import SwiftUI

struct NotesView: View {
    let app: AppState

    var body: some View {
        TimelineView(.everyMinute) { context in
            Page {
                PageHeading(title: "Notes")
            } content: {
                NoteList(app: app, meetings: app.notes, now: context.date)
            }
        }
        .toolbar { ArchiveButton(app: app) }
    }
}

private struct ArchiveButton: ToolbarContent {
    let app: AppState

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Archive", systemImage: "archivebox") { app.openArchive() }
                .help("Open Archive")
        }
    }
}

struct MeetingsView: View {
    private static let wide: CGFloat = 780
    private static let slide: TimeInterval = 0.3
    let app: AppState
    @State private var selected: Series.ID?
    @State private var width: CGFloat = 0
    @State private var grown: CGFloat = 0

    var body: some View {
        let series = app.notes.series
        let open = series.first { $0.id == selected }
        TimelineView(.everyMinute) { context in
            Page {
                PageHeading(title: "Meetings")
            } content: {
                Rows(items: series, indent: ChatRow.avatarIndent) { series in
                    Button { select(series.id == selected ? nil : series.id) } label: {
                        ChatRow(avatar: Avatar(title: series.avatar), title: series.title, stamp: series.meetings[0].date.stamp(at: context.date), preview: app.previews[series.meetings[0].id], count: series.meetings.count, selected: series.id == selected)
                    }
                }
                .padding(.horizontal, Theme.column - ChatRow.inset)
            }
        }
        .toolbar { ArchiveButton(app: app) }
        .inspector(isPresented: Binding { open != nil } set: { if !$0 { select(nil, animated: false) } }) {
            if let open {
                SeriesView(app: app, series: open)
                    .inspectorColumnWidth(min: 260, ideal: 300)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: open?.id) { _, id in
            if id == nil, selected != nil { select(nil, animated: false) }
        }
        .onExitCommand { select(nil, animated: false) }
        .onDisappear { select(nil) }
    }

    private func select(_ id: Series.ID?, animated: Bool = true) {
        let growth = switch (selected, id) {
        case (nil, .some): max(0, Self.wide - width)
        case (.some, nil): -grown
        default: CGFloat(0)
        }
        grown += growth
        app.widenHome(by: growth)
        var transaction = Transaction(animation: animated && growth == 0 ? .drawer(Self.slide) : nil)
        transaction.disablesAnimations = growth != 0
        withTransaction(transaction) { selected = id }
    }
}

struct ArchiveView: View {
    let app: AppState

    var body: some View {
        TimelineView(.everyMinute) { context in
            Page(title: "Archive") {
                PageHeading(title: "Archive", detail: app.archive.isEmpty ? "Notes you archive will appear here." : nil)
            } content: {
                NoteList(app: app, meetings: app.archive, now: context.date)
            }
        }
    }
}

private struct NoteList: View {
    let app: AppState
    let meetings: [Meeting]
    let now: Date

    var body: some View {
        Rows(items: meetings, indent: ChatRow.avatarIndent) { meeting in
            NoteRow(app: app, meeting: meeting, row: ChatRow(avatar: Avatar(title: meeting.title), title: meeting.displayTitle, stamp: meeting.date.stamp(at: now), preview: app.previews[meeting.id]))
        }
        .padding(.horizontal, Theme.column - ChatRow.inset)
    }
}

private struct NoteRow: View {
    let app: AppState
    let meeting: Meeting
    let row: ChatRow

    var body: some View {
        Button { app.open(meeting) } label: { actionable }
            .contextMenu { NoteMenu(app: app, meeting: meeting) }
    }

    private var actionable: ChatRow {
        var row = row
        row.actions = NoteActions(app: app, meeting: meeting, shortcuts: false)
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
    let meeting: Meeting?
    var shortcuts = true

    var body: some View {
        NoteActions(app: app, meeting: meeting, shortcuts: shortcuts)
        Divider()
        Button("Open Archive", systemImage: "archivebox.fill") { app.openArchive() }
            .keyboardShortcut(shortcuts ? KeyboardShortcut("a", modifiers: [.command, .shift]) : nil)
    }
}

struct NoteActions: View {
    let app: AppState
    let meeting: Meeting?
    let shortcuts: Bool

    var body: some View {
        Group {
            if meeting?.archivedAt == nil {
                Button("Archive", systemImage: "archivebox") { if let meeting { app.archive(meeting) } }
            } else {
                Button("Restore", systemImage: "arrow.uturn.backward") { if let meeting { app.restore(meeting) } }
            }
        }
        .keyboardShortcut(shortcuts ? KeyboardShortcut("a", modifiers: [.command, .control]) : nil)
        .help(meeting?.archivedAt == nil ? "Archive" : "Restore")
        Button("Delete…", systemImage: "trash", role: .destructive) { if let meeting { app.confirmDeletion(of: meeting) } }
            .keyboardShortcut(shortcuts ? KeyboardShortcut(.delete, modifiers: [.command, .option]) : nil)
            .help("Delete")
            .disabled(meeting == nil)
    }
}

private struct SeriesView: View {
    let app: AppState
    let series: Series

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Avatar(title: series.avatar, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(series.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(series.meetings.count == 1 ? "1 note" : "\(series.meetings.count) notes")
                            .font(Theme.meta)
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                Rows(items: series.meetings) { meeting in
                    NoteRow(app: app, meeting: meeting, row: ChatRow(title: meeting.date.formatted(.dateTime.weekday(.wide).day().month(.wide)), preview: app.previews[meeting.id]))
                }
            }
            .padding(8)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

private struct Rows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var indent: CGFloat = 0
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
                                .opacity(hovered == item.id || hovered == previous ? 0 : 1)
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .padding(.bottom, 20)
    }
}

private extension EnvironmentValues {
    @Entry var hovering = false
}

private struct ChatRow: View {
    static let inset: CGFloat = 10
    static let avatarIndent = Avatar.standard + spacing
    private static let spacing: CGFloat = 12
    private static let actionsWidth = 2 * RowAction.size - (RowAction.size - RowAction.glyph) / 2
    var avatar: Avatar?
    let title: String
    var stamp: String?
    let preview: String?
    var count: Int?
    var selected = false
    var actions: NoteActions?
    @Environment(\.hovering) private var hovering

    var body: some View {
        HStack(spacing: Self.spacing) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    meta(stamp.map { Text($0).font(Theme.meta.monospacedDigit()) })
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(preview ?? "No notes")
                        .font(.system(size: 12.5))
                        .foregroundStyle(preview == nil ? faint : quiet)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    meta(count.map { Text($0, format: .number).font(.system(size: 11.5).monospacedDigit()) })
                }
            }
            .lineLimit(1)
            .overlay(alignment: .trailing) {
                if revealed {
                    HStack(spacing: 0) { actions }
                        .buttonStyle(RowAction())
                        .padding(.trailing, -(RowAction.size - RowAction.glyph) / 2)
                        .transition(.opacity)
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

    @ViewBuilder private func meta(_ text: Text?) -> some View {
        if text != nil || actions != nil {
            (text ?? Text(verbatim: ""))
                .foregroundStyle(faint)
                .frame(minWidth: actions == nil ? nil : Self.actionsWidth, alignment: .trailing)
                .opacity(revealed ? 0 : 1)
        }
    }

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
    @Environment(\.hovering) private var hovering

    var body: some View {
        if let title, let initial = title.first(where: { $0.isLetter || $0.isNumber }) {
            Text(String(initial).uppercased())
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Self.hue(of: title), in: .circle)
        } else {
            Image(systemName: "note.text")
                .font(.system(size: size * 0.4))
                .foregroundStyle(Theme.secondary)
                .frame(width: size, height: size)
                .background(hovering ? Theme.paper : Theme.well, in: .circle)
        }
    }

    private static func hue(of title: String) -> Color {
        hues[title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % hues.count]
    }
}

extension Series {
    var title: String { id == .other ? "Other notes" : meetings[0].displayTitle }
    var avatar: String? { id == .other ? nil : meetings[0].title }
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
