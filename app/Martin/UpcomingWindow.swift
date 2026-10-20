import AppKit
import MartinKit
import SwiftUI

struct UpcomingView: View {
    private static let days = 4
    @State private var events: [CalendarEvent]?
    @State private var denied = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = Calendar.current.startOfDay(for: context.date)
            VStack(alignment: .leading, spacing: 0) {
                header(from: today)
                content(at: context.date)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: today) { await watch(from: today) }
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
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        if let events {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ForEach(CalendarLookup.agenda(of: events, days: Self.days, at: now), id: \.start) { day in
                        DayView(day: day, now: now)
                    }
                }
                .padding(.leading, Theme.margin)
                .padding(.trailing, Theme.margin)
                .padding(.bottom, 28)
            }
        } else if denied {
            CalendarAccess()
        }
    }

    private func watch(from today: Date) async {
        let end = Calendar.current.date(byAdding: .day, value: Self.days, to: today)!
        while !Task.isCancelled {
            for await events in CalendarLookup.events(from: today, to: end) {
                self.events = events
            }
            guard !Task.isCancelled else { return }
            denied = true
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) { break }
        }
    }
}

private struct DayView: View {
    let day: AgendaDay
    let now: Date

    private var allDay: [CalendarEvent] { day.events.filter(\.isAllDay) }
    private var timed: [CalendarEvent] { day.events.filter { !$0.isAllDay } }

    private var label: String {
        if Calendar.current.isDateInToday(day.start) { return "Today" }
        if Calendar.current.isDateInTomorrow(day.start) { return "Tomorrow" }
        return day.start.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                SectionLabel(label)
                if !allDay.isEmpty {
                    Text("All day  ·  " + allDay.map(\.title).formatted(.list(type: .and)))
                        .font(Theme.meta)
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.leading, Theme.gutter)
            if timed.isEmpty {
                Text("Nothing scheduled")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.leading, Theme.gutter)
            }
            ForEach(timed, id: \.self) { event in
                EventRow(event: event, underway: event.isUnderway(at: now))
            }
        }
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let underway: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Circle()
                .fill(Theme.ember)
                .frame(width: 6, height: 6)
                .opacity(underway ? 1 : 0)
                .frame(width: Theme.gutter, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title.isEmpty ? "Untitled" : event.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(details)
                    .font(Theme.meta)
                    .foregroundStyle(Theme.secondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
    }

    private var details: String {
        let time = underway
            ? "Now until \(event.end.formatted(date: .omitted, time: .shortened))"
            : (event.start..<event.end).formatted(.interval.hour().minute())
        return [time, event.attendees.attendeeSummary].compactMap(\.self).joined(separator: "  ·  ")
    }
}

private struct CalendarAccess: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Martin can’t see your calendar")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("Allow Martin to use your calendars, and your next few days of meetings will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .lineSpacing(3)
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
            .padding(.top, 8)
        }
        .padding(.leading, Theme.column)
        .padding(.trailing, Theme.margin)
    }
}
