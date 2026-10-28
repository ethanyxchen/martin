import MartinKit
import SwiftUI

struct SettingsView: View {
    @Bindable var app: AppState

    var body: some View {
        Page(title: "Settings") {
            PageHeading(title: "Settings", detail: "Choose the pages in the navigation bar and the calendars Martin follows.")
        } content: {
            VStack(alignment: .leading, spacing: 26) {
                NavigationSection(hidden: $app.hiddenPages)
                    .padding(.leading, Theme.column)
                    .padding(.trailing, Theme.margin)
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
                }
            }
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NavigationSection: View {
    @Binding var hidden: Set<HomePage>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Navigation bar")
                .font(Theme.heading)
                .foregroundStyle(Theme.ink)
            ForEach(HomePage.allCases, id: \.self) { page in
                Toggle(isOn: $hidden.excludes(page)) {
                    HStack(spacing: 8) {
                        Image(systemName: page.symbol)
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 16)
                        Text(page.title)
                            .foregroundStyle(Theme.ink)
                        if !page.hideable {
                            Text("Always shown")
                                .foregroundStyle(Theme.tertiary)
                        }
                    }
                    .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .disabled(!page.hideable)
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
                .font(Theme.heading)
                .foregroundStyle(Theme.ink)
            ForEach(account.calendars) { calendar in
                Toggle(isOn: $hidden.excludes(calendar.id)) {
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
}

private extension Binding {
    func excludes<Element: Hashable & Sendable>(_ element: Element) -> Binding<Bool> where Value == Set<Element> {
        Binding<Bool> {
            !wrappedValue.contains(element)
        } set: { shown in
            if shown { wrappedValue.remove(element) } else { wrappedValue.insert(element) }
        }
    }
}
