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
    }
}

struct MeetingsView: View {
    private static let sidebar: CGFloat = 300
    private static let wide: CGFloat = 780
    private static let slide: TimeInterval = 0.3
    let app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Series.ID?
    @State private var width: CGFloat = 0
    @State private var grown: CGFloat = 0

    var body: some View {
        let series = app.notes.series
        let open = series.first { $0.id == selected }
        TimelineView(.everyMinute) { context in
            HStack(spacing: 0) {
                Page {
                    PageHeading(title: "Meetings")
                } content: {
                    Rows(items: series) { series in
                        Button { select(series.id == selected ? nil : series.id) } label: {
                            ChatRow(avatar: Avatar(title: series.avatar), title: series.title, stamp: series.meetings[0].date.stamp(at: context.date), preview: app.previews[series.meetings[0].id], count: series.meetings.count, selected: series.id == selected)
                        }
                    }
                    .padding(.horizontal, (open == nil ? Theme.margin : 18) - ChatRow.inset)
                }
                .frame(width: open == nil ? nil : Self.sidebar)
                if let open {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Theme.well)
                            .frame(width: 1)
                            .ignoresSafeArea()
                        SeriesView(app: app, series: open)
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
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
        let duration = animated ? Self.slide : 0
        if selected == nil, id != nil {
            grown = max(0, Self.wide - width)
            app.widenHome(by: grown, over: duration)
        } else if selected != nil, id == nil {
            app.widenHome(by: -grown, over: duration)
            grown = 0
        }
        withAnimation(animated ? .drawer(duration) : nil) { selected = id }
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
        Rows(items: meetings) { meeting in
            NoteRow(app: app, meeting: meeting, row: ChatRow(avatar: Avatar(title: meeting.title), title: meeting.displayTitle, stamp: meeting.date.stamp(at: now), preview: app.previews[meeting.id]))
        }
        .padding(.horizontal, Theme.margin - ChatRow.inset)
    }
}

private struct NoteRow: View {
    let app: AppState
    let meeting: Meeting
    let row: ChatRow
    @State private var hovering = false

    var body: some View {
        Button { app.open(meeting) } label: { row }
            .overlay(alignment: .trailing) {
                if hovering {
                    HStack(spacing: 0) {
                        NoteActions(app: app, meeting: meeting, shortcuts: false)
                    }
                    .buttonStyle(RowAction())
                    .padding(.horizontal, 6)
                    .frame(maxHeight: .infinity)
                    .background(Theme.well, in: .rect(cornerRadius: 9))
                    .transition(.opacity)
                }
            }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .contextMenu { NoteMenu(app: app, meeting: meeting) }
    }
}

private struct RowAction: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Theme.ink : Theme.secondary)
            .frame(width: 28, height: 28)
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

private struct NoteActions: View {
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
        VStack(alignment: .leading, spacing: 0) {
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
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Rectangle()
                .fill(Theme.well)
                .frame(height: 1)
            ScrollView {
                Rows(items: series.meetings) { meeting in
                    NoteRow(app: app, meeting: meeting, row: ChatRow(title: meeting.date.formatted(.dateTime.weekday(.wide).day().month(.wide)), preview: app.previews[meeting.id]))
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct Rows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                row(item)
                    .buttonStyle(Pressable(scale: 0.98))
                    .overlay(alignment: .top) {
                        if item.id != items.first?.id {
                            Rectangle()
                                .fill(Theme.well)
                                .frame(height: 1)
                                .padding(.horizontal, ChatRow.inset)
                        }
                    }
            }
        }
        .padding(.bottom, 20)
    }
}

private struct ChatRow: View {
    static let inset: CGFloat = 10
    var avatar: Avatar?
    let title: String
    var stamp: String?
    let preview: String?
    var count: Int?
    var selected = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let stamp {
                        Text(stamp)
                            .font(Theme.meta.monospacedDigit())
                            .foregroundStyle(faint)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(preview ?? "No notes")
                        .font(.system(size: 12.5))
                        .foregroundStyle(preview == nil ? faint : quiet)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let count {
                        Text(count, format: .number)
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(faint)
                    }
                }
            }
            .lineLimit(1)
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 9)
        .background(selected ? AnyShapeStyle(Theme.cobalt) : AnyShapeStyle(Theme.well.opacity(hovering ? 1 : 0)), in: .rect(cornerRadius: 9))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointerStyle(.link)
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
    let title: String?
    var size: CGFloat = 40

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
                .background(Theme.well, in: .circle)
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
