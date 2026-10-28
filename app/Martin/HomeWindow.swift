import SwiftUI

enum HomePage: String, CaseIterable {
    case upcoming
    case notes
    case meetings
    case settings

    var title: String {
        switch self {
        case .upcoming: "Upcoming"
        case .notes: "Notes"
        case .meetings: "Meetings"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .upcoming: "calendar"
        case .notes: "note.text"
        case .meetings: "repeat"
        case .settings: "gearshape"
        }
    }

    var hideable: Bool { self != .settings }

    static func shown(hiding hidden: Set<HomePage>) -> [HomePage] {
        allCases.filter { !$0.hideable || !hidden.contains($0) }
    }

    fileprivate var order: Int { Self.allCases.firstIndex(of: self)! }
}

struct HomeView: View {
    @Bindable var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var titlebar: CGFloat = 0

    var body: some View {
        ZStack {
            view(of: app.page)
                .id(app.page)
                .transition(transition(drifting: CGFloat(app.page.order) * 26 - 36))
                .zIndex(Double(app.page.order))
        }
        .animation(.default, value: app.page)
        .overlay(alignment: .top) {
            PageTabs(pages: app.pages, page: $app.page, animation: reduceMotion ? nil : .spring(duration: 0.3, bounce: 0))
                .frame(height: titlebar)
                .ignoresSafeArea(edges: .top)
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { titlebar = $0 }
    }

    @ViewBuilder private func view(of page: HomePage) -> some View {
        switch page {
        case .upcoming: UpcomingView(app: app)
        case .notes: NotesView(app: app)
        case .meetings: MeetingsView(app: app)
        case .settings: SettingsView(app: app)
        }
    }

    private func transition(drifting x: CGFloat) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        let drift = AnyTransition.offset(x: x).combined(with: .opacity)
        return .asymmetric(
            insertion: drift.animation(.drawer(0.25)),
            removal: drift.animation(.drawer(0.2))
        )
    }
}

private struct PageTabs: View {
    let pages: [HomePage]
    @Binding var page: HomePage
    let animation: Animation?
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 3) {
            ForEach(pages, id: \.self) { tab in
                let selected = tab == page
                Button { page = tab } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                        if selected {
                            Text(tab.title)
                                .fixedSize()
                                .transition(.opacity)
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.tertiary))
                    .padding(.horizontal, selected ? 12 : 0)
                    .frame(minWidth: 36, minHeight: 22)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.paper)
                                .shadow(color: .black.opacity(0.16), radius: 1.5, y: 1)
                                .matchedGeometryEffect(id: "selection", in: selection)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(Pressable())
                .help(tab.title)
            }
        }
        .padding(3)
        .background(Theme.well, in: .capsule)
        .animation(animation, value: page)
        .animation(animation, value: pages)
    }
}
