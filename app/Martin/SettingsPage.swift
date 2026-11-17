import MartinKit
import SwiftUI

struct SettingsView: View {
    @Bindable var app: AppState

    var body: some View {
        Page {
            PageHeading(title: "Settings")
        } content: {
            VStack(alignment: .leading, spacing: 36) {
                SettingsSection(title: "Navigation bar", detail: "The pages you can switch between at the top of this window.") {
                    NavigationToggles(hidden: $app.hiddenPages)
                        .flush()
                }
                SettingsSection(title: "Assistant", detail: "Reads your notes to keep your projects up to date. Your notes go only to the provider whose API key you save.") {
                    APIKeyForm(app: app)
                        .flush()
                }
                SettingsSection(title: "Calendars", detail: "Martin shows events and takes notes for the calendars you tick.") {
                    CalendarFeed(query: true, promise: "you can choose which of them Martin follows") { _ in
                        CalendarLookup.accounts()
                    } content: { accounts in
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(accounts) { account in
                                AccountView(account: account, hidden: $app.hiddenCalendars)
                            }
                        }
                        .flush()
                    }
                }
            }
            .padding(.bottom, 28)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.heading)
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.meta)
                    .foregroundStyle(Theme.secondary)
            }
            .flush()
            content
        }
    }
}

private struct APIKeyForm: View {
    let app: AppState
    @State private var provider = Provider.anthropic
    @State private var key = ""

    var body: some View {
        if let credential = app.credential {
            HStack(spacing: 10) {
                Label("\(credential.provider.title) API key saved", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                Button("Remove") { app.credential = nil }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Provider", selection: $provider) {
                    ForEach(Provider.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                HStack(spacing: 10) {
                    SecureField("\(provider.title) API key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(trimmedKey.isEmpty)
                }
            }
            .font(.system(size: 13))
        }
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedKey.isEmpty else { return }
        app.use(Credential(provider: provider, key: trimmedKey))
        key = ""
    }
}

private struct NavigationToggles: View {
    @Binding var hidden: Set<HomePage>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            Text(account.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.tertiary)
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
