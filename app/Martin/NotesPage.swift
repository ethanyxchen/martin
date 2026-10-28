import MartinKit
import SwiftUI

struct NotesView: View {
    let app: AppState

    var body: some View {
        TimelineView(.everyMinute) { context in
            Page(title: "Notes") {
                PageHeading(title: "Notes")
            } content: {
                Rows(items: app.meetings) { meeting in
                    Button { app.open(meeting) } label: {
                        ChatRow(avatar: Avatar(title: meeting.title), title: meeting.displayTitle, stamp: meeting.date.stamp(at: context.date), preview: app.preview(of: meeting))
                    }
                }
                .padding(.horizontal, Theme.margin - ChatRow.inset)
            }
        }
    }
}

struct MeetingsView: View {
    private static let sidebar: CGFloat = 300
    private static let wide: CGFloat = 780
    let app: AppState
    @State private var selected: Series.ID?
    @State private var width: CGFloat = 0
    @State private var grown: CGFloat = 0

    var body: some View {
        let series = app.meetings.series
        let open = series.first { $0.id == selected }
        TimelineView(.everyMinute) { context in
            HStack(spacing: 0) {
                Page(title: "Meetings") {
                    PageHeading(title: "Meetings")
                } content: {
                    Rows(items: series) { series in
                        Button { select(series.id == selected ? nil : series.id) } label: {
                            ChatRow(avatar: Avatar(title: series.avatar), title: series.title, stamp: series.meetings[0].date.stamp(at: context.date), preview: app.preview(of: series.meetings[0]), count: series.meetings.count, selected: series.id == selected)
                        }
                    }
                    .padding(.horizontal, (open == nil ? Theme.margin : 18) - ChatRow.inset)
                }
                .frame(width: open == nil ? nil : Self.sidebar)
                if let open {
                    Rectangle()
                        .fill(Theme.well)
                        .frame(width: 1)
                        .ignoresSafeArea()
                    SeriesView(app: app, series: open)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onExitCommand { select(nil) }
        .onDisappear { select(nil) }
    }

    private func select(_ id: Series.ID?) {
        if selected == nil, id != nil {
            grown = max(0, Self.wide - width)
            app.widenHome(by: grown)
        } else if selected != nil, id == nil {
            app.widenHome(by: -grown)
            grown = 0
        }
        selected = id
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
                    Button { app.open(meeting) } label: {
                        ChatRow(title: meeting.date.formatted(.dateTime.weekday(.wide).day().month(.wide)), preview: app.preview(of: meeting))
                    }
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
                    .buttonStyle(.plain)
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

extension AppState {
    func preview(of meeting: Meeting) -> String? {
        library.note(of: meeting).flatMap(Markdown.preview(of:))
    }
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
