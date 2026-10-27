import SwiftUI

enum Page: CaseIterable {
    case upcoming
    case settings

    var title: String {
        switch self {
        case .upcoming: "Upcoming"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .upcoming: "calendar"
        case .settings: "gearshape"
        }
    }
}

struct HomeView: View {
    @Bindable var app: AppState

    var body: some View {
        Group {
            switch app.page {
            case .upcoming: UpcomingView(app: app)
            case .settings: SettingsView(app: app)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            PageTabs(page: $app.page)
                .padding(.top, 5)
                .padding(.trailing, 10)
        }
        .background(Theme.paper)
        .ignoresSafeArea(edges: .top)
    }
}

private struct PageTabs: View {
    @Binding var page: Page

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Page.allCases, id: \.self) { tab in
                Button { page = tab } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13))
                        .foregroundStyle(tab == page ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.tertiary))
                        .frame(width: 30, height: 22)
                        .background(Theme.paper.opacity(tab == page ? 1 : 0), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .padding(2)
        .background(Theme.well, in: .capsule)
        .animation(.easeOut(duration: 0.12), value: page)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
            Text(subtitle)
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
}
