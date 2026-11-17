import MartinKit
import SwiftUI

enum OverviewStatus: Equatable {
    case ready
    case refreshing
    case failed(String)

    var action: String {
        if case .failed = self { "Try Again" } else { "Refresh" }
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

    private func group(_ section: Overview.Section, _ tasks: [Overview.Task], first: Bool) -> some View {
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
            if shown.count < tasks.count {
                Button("Show \(tasks.count - shown.count) more") { unfolded = true }
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
            if status == .refreshing {
                ProgressView().controlSize(.mini)
                Text("Refreshing…")
            } else if let overview {
                Text("Updated \(overview.readAt.formatted(.relative(presentation: .named)))")
            }
            Spacer(minLength: 0)
            Button(status.action, systemImage: "arrow.clockwise", action: refresh)
                .buttonStyle(Pill())
                .disabled(status == .refreshing)
        }
        .font(Theme.meta)
        .foregroundStyle(Theme.tertiary)
        .padding(.horizontal, TaskRow.inset)
        .padding(.top, overview == nil ? 0 : 10)
    }

    static func shown(_ tasks: [Overview.Task], in section: Overview.Section, unfolded: Bool) -> [Overview.Task] {
        let folds = section == .shelved && !unfolded && tasks.count > folded + 1
        return folds ? Array(tasks.prefix(folded)) : tasks
    }

    static func stamp(_ day: Date, now: Date, calendar: Calendar = .current) -> String {
        switch calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: now)).day ?? 0 {
        case 0: return "Today"
        case 1: return "Yesterday"
        default:
            let date = Date.FormatStyle.dateTime.month(.abbreviated).day()
            return day.formatted(calendar.isDate(day, equalTo: now, toGranularity: .year) ? date : date.year())
        }
    }
}

private struct TaskRow: View {
    static let inset: CGFloat = 10
    let task: Overview.Task
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

private struct Pill: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Theme.well, in: .capsule)
            .contentShape(.capsule)
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
