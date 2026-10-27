import MartinKit
import SwiftUI

struct SettingsView: View {
    @Bindable var app: AppState

    var body: some View {
        Page(title: "Settings") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(Theme.title)
                    .foregroundStyle(Theme.ink)
                Text("Choose the calendars Martin shows and takes notes for.")
                    .font(Theme.meta)
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.leading, Theme.column)
            .padding(.trailing, Theme.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
        } content: {
            CalendarFeed(query: true, promise: "you can choose which of them Martin follows") { _ in
                CalendarLookup.accounts()
            } content: { accounts in
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(accounts) { account in
                        AccountView(account: account, hidden: $app.hiddenCalendars)
                    }
                }
                .padding(.leading, Theme.column)
                .padding(.trailing, Theme.margin)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct AccountView: View {
    let account: CalendarAccount
    @Binding var hidden: Set<EventCalendar.ID>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(account.title)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            ForEach(account.calendars) { calendar in
                Toggle(isOn: shown(calendar)) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(cgColor: calendar.color))
                            .frame(width: 8, height: 8)
                        Text(calendar.title)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func shown(_ calendar: EventCalendar) -> Binding<Bool> {
        Binding {
            !hidden.contains(calendar.id)
        } set: { shown in
            if shown { hidden.remove(calendar.id) } else { hidden.insert(calendar.id) }
        }
    }
}
