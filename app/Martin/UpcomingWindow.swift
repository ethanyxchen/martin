import AppKit
import MartinKit
import SwiftUI

struct UpcomingView: View {
    private static let days = 4
    let app: AppState

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = Calendar.current.startOfDay(for: context.date)
            VStack(alignment: .leading, spacing: 0) {
                header(from: today)
                content(from: today, at: context.date)
            }
        }
        .background(Theme.paper)
        .ignoresSafeArea(edges: .top)
    }

    private func header(from today: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Upcoming")
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
            Text((today..<Calendar.current.date(byAdding: .day, value: Self.days - 1, to: today)!).formatted(.interval.month(.wide).day()))
                .font(Theme.meta)
                .foregroundStyle(Theme.secondary)
        }
        .padding(.leading, Theme.column)
        .padding(.trailing, Theme.margin)
        .padding(.top, 46)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .movesWindow()
    }

    private func content(from today: Date, at now: Date) -> some View {
        CalendarFeed(query: Span(start: today, hidden: app.hiddenCalendars), promise: "your next few days of meetings will appear here") { span in
            CalendarLookup.events(from: span.start, to: Calendar.current.date(byAdding: .day, value: Self.days, to: span.start)!, hiding: span.hidden)
        } content: { events in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ForEach(CalendarLookup.agenda(of: events, days: Self.days, at: now), id: \.start) { day in
                        DayView(app: app, day: day, now: now)
                    }
                }
                .padding(.leading, Theme.margin)
                .padding(.trailing, Theme.margin)
                .padding(.bottom, 28)
            }
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
                        EventRow(event: event, underway: event.isUnderway(at: now))
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
    let underway: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Circle()
                .fill(Theme.cobalt)
                .frame(width: 6, height: 6)
                .opacity(underway ? 1 : 0)
                .frame(width: Theme.gutter, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title.isEmpty ? "Untitled" : event.title)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                Text(time)
                    .font(Theme.meta.monospacedDigit())
                    .foregroundStyle(Theme.secondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.well.opacity(hovering ? 1 : 0), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var time: String {
        underway
            ? "Now until \(event.end.formatted(date: .omitted, time: .shortened))"
            : (event.start..<event.end).formatted(.interval.hour().minute())
    }
}
