import AppKit
import SwiftUI

struct CalendarFeed<Query: Equatable, Value: Sendable, Content: View>: View {
    let query: Query
    let promise: String
    let stream: (Query) -> AsyncStream<Value>
    @ViewBuilder let content: (Value) -> Content
    @State private var value: Value?
    @State private var denied = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let value {
                content(value)
            } else if denied {
                CalendarAccess(promise: promise)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: query) { await watch() }
    }

    private func watch() async {
        while !Task.isCancelled {
            for await value in stream(query) {
                self.value = value
            }
            guard !Task.isCancelled else { return }
            denied = true
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) { break }
        }
    }
}

private struct CalendarAccess: View {
    let promise: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Martin can’t see your calendar")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("Allow Martin to use your calendars, and \(promise).")
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
