import MartinKit
import SwiftUI

enum OverviewStatus: Equatable {
    case ready
    case refreshing
    case failed(String)

    var action: String? {
        switch self {
        case .ready: "Refresh"
        case .refreshing: nil
        case .failed: "Try Again"
        }
    }
}

struct OverviewSection: View {
    static let folded = 2
    let overview: Overview?
    let status: OverviewStatus
    let now: Date
    let refresh: () -> Void
    @State private var unfolded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if case .failed(let message) = status {
                Notice(message: message)
            }
            if let overview {
                let sections = Overview.Section.allCases.filter { !overview[$0].isEmpty }
                ForEach(sections, id: \.self) { section in
                    group(section, overview[section], first: section == sections.first)
                }
                if sections.isEmpty {
                    Text("Nothing in progress yet.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, TaskRow.inset)
                }
            }
            footer
        }
        .flush()
        .padding(.bottom, 14)
    }

    private func group(_ section: Overview.Section, _ tasks: [Overview.Item], first: Bool) -> some View {
        let shown = Self.shown(tasks, in: section, unfolded: unfolded)
        return VStack(alignment: .leading, spacing: 0) {
            Text(section == .shelved ? "\(section.title) · \(tasks.count)" : section.title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.tertiary)
                .padding(.horizontal, TaskRow.inset)
                .padding(.top, first ? 0 : 18)
                .padding(.bottom, 4)
            ForEach(Array(shown.enumerated()), id: \.offset) { index, task in
                TaskRow(task: task, section: section, stamp: task.day(in: .current).map { Self.stamp($0, now: now) })
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle().fill(Theme.well).frame(height: 1).padding(.horizontal, TaskRow.inset)
                        }
                    }
            }
            if Self.folds(tasks, in: section) {
                Button(unfolded ? "Show less" : "Show \(tasks.count - Self.folded) more") { unfolded.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, TaskRow.inset)
                    .padding(.vertical, 6)
                    .pointerStyle(.link)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Self.caption(overview, status: status, now: now).map(Text.init)
            Spacer(minLength: 0)
            if let action = status.action {
                Button(action: refresh) {
                    Label(action, systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Theme.well, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(Pressable())
                .pointerStyle(.link)
            }
        }
        .frame(minHeight: 22)
        .font(Theme.meta)
        .foregroundStyle(Theme.tertiary)
        .padding(.horizontal, TaskRow.inset)
        .padding(.top, overview == nil ? 0 : 10)
    }

    static func caption(_ overview: Overview?, status: OverviewStatus, now: Date) -> String? {
        let updated = overview.map { "Updated \(age(of: $0.readAt, now: now))" }
        guard status == .refreshing else { return updated }
        return updated.map { "\($0) · refreshing" } ?? "Refreshing…"
    }

    static func shown(_ tasks: [Overview.Item], in section: Overview.Section, unfolded: Bool) -> [Overview.Item] {
        folds(tasks, in: section) && !unfolded ? Array(tasks.prefix(folded)) : tasks
    }

    static func folds(_ tasks: [Overview.Item], in section: Overview.Section) -> Bool {
        section == .shelved && tasks.count > folded + 1
    }

    static func stamp(_ day: Date, now: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        switch calendar.days(from: day, to: now) {
        case ...0: return "Today"
        case 1: return "Yesterday"
        case 2..<7: return day.formatted(style.weekday(.wide))
        default:
            style = style.month(.abbreviated).day()
            return day.formatted(calendar.isDate(day, equalTo: now, toGranularity: .year) ? style : style.year())
        }
    }

    static func age(of date: Date, now: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: min(date, now), relativeTo: now)
    }
}

private struct TaskRow: View {
    static let inset: CGFloat = 10
    let task: Overview.Item
    let section: Overview.Section
    let stamp: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            marker.frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13.5, weight: section == .shelved ? .medium : .semibold))
                    .foregroundStyle(section == .shelved ? Theme.secondary : Theme.ink)
                Text(task.caption)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let stamp {
                Text(stamp)
                    .font(Theme.meta.monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 9)
    }

    @ViewBuilder private var marker: some View {
        switch section {
        case .now: Circle().fill(Theme.cobalt)
        case .next: Circle().strokeBorder(Theme.tertiary, lineWidth: 1.5)
        case .shelved: Circle().fill(Theme.tertiary.opacity(0.5))
        }
    }
}

private struct Notice: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(Theme.meta)
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.well, in: .rect(cornerRadius: 9))
            .padding(.bottom, 10)
    }
}

extension Overview.Section {
    var title: String {
        switch self {
        case .now: "Now"
        case .next: "Next"
        case .shelved: "Shelved"
        }
    }
}
