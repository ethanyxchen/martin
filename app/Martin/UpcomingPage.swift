import AppKit
import MartinKit
import SwiftUI

struct UpcomingView: View {
    private static let days = 4
    let app: AppState

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = Calendar.current.startOfDay(for: context.date)
            Page(title: "Upcoming") {
                PageHeading(title: "Upcoming")
            } content: {
                content(from: today, at: context.date)
            }
        }
    }

    private func content(from today: Date, at now: Date) -> some View {
        CalendarFeed(query: Span(start: today, hidden: app.hiddenCalendars), promise: "your next few days of meetings will appear here") { span in
            CalendarLookup.events(from: span.start, to: Calendar.current.date(byAdding: .day, value: Self.days, to: span.start)!, hiding: span.hidden)
        } content: { events in
            LazyVStack(alignment: .leading, spacing: 30) {
                ForEach(CalendarLookup.agenda(of: events, days: Self.days, at: now), id: \.start) { day in
                    DayView(app: app, day: day, now: now)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 28)
        }
    }
}

private struct Span: Equatable {
    let start: Date
    let hidden: Set<EventCalendar.ID>
}

private struct DayView: View {
    let app: AppState
    let day: AgendaDay
    let now: Date

    private var name: String {
        if Calendar.current.isDateInToday(day.start) { return "Today" }
        if Calendar.current.isDateInTomorrow(day.start) { return "Tomorrow" }
        return day.start.formatted(.dateTime.weekday(.wide))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(name)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text(day.start.formatted(.dateTime.month(.wide).day()))
                    .font(Theme.meta)
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.leading, Theme.gutter)
            if day.events.isEmpty {
                Text("No meetings")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.leading, Theme.gutter)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(day.events, id: \.self) { event in
                    Button { app.start(event) } label: {
                        EventRow(event: event, day: day, underway: event.isUnderway(at: now))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(.top, -6)
        }
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let day: AgendaDay
    let underway: Bool
    @State private var hovering = false
    private static let inset: CGFloat = 10

    private var startsEarlier: Bool { event.start < day.start }
    private var endsLater: Bool { event.end > day.end }

    var body: some View {
        HStack(spacing: 16) {
            Text(event.title.isEmpty ? "Untitled" : event.title)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                time
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(underway ? Theme.cobalt : Theme.ink)
                if let span {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text(span)
                    }
                    .font(Theme.meta)
                    .foregroundStyle(Theme.secondary)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 8)
        .background(Theme.well.opacity(hovering ? 1 : 0), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .padding(.horizontal, Theme.gutter - Self.inset)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var time: Text {
        let arrow = Text("→").foregroundStyle(underway ? Theme.cobalt : Theme.tertiary)
        let end = event.end.formatted(.dateTime.hour().minute())
        if underway { return Text("Now \(arrow) \(end)") }
        if startsEarlier { return Text("\(arrow) \(end)") }
        return Text("\(event.start.formatted(.dateTime.hour().minute())) \(arrow) \(end)")
    }

    private var span: String? {
        let format = Date.FormatStyle.dateTime.weekday(.abbreviated).day()
        switch (startsEarlier, endsLater) {
        case (true, true): return "\(event.start.formatted(format)) → \(event.end.formatted(format))"
        case (true, false): return "from \(event.start.formatted(format))"
        case (false, true): return event.end.formatted(format)
        case (false, false): return nil
        }
    }
}
