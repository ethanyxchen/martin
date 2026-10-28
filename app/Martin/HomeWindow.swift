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

    static func shown(hiding hidden: Set<HomePage>, on current: HomePage) -> [HomePage] {
        allCases.filter { !$0.hideable || $0 == current || !hidden.contains($0) }
    }
}

struct HomeView: View {
    @Bindable var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            view(of: app.page)
                .id(app.page)
                .transition(transition)
        }
        .animation(.default, value: app.page)
        .toolbar {
            ToolbarItem(placement: .principal) {
                PageTabs(pages: app.pages, page: $app.page, animation: reduceMotion ? nil : .spring(duration: 0.3, bounce: 0))
            }
        }
    }

    @ViewBuilder private func view(of page: HomePage) -> some View {
        switch page {
        case .upcoming: UpcomingView(app: app)
        case .notes: NotesView(app: app)
        case .meetings: MeetingsView(app: app)
        case .settings: SettingsView(app: app)
        }
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let settle = AnyTransition.scale(scale: 0.985).combined(with: .opacity)
        return .asymmetric(
            insertion: settle.animation(.drawer(0.25)),
            removal: settle.animation(.drawer(0.2))
        )
    }
}

private struct PageTabs: View {
    let pages: [HomePage]
    @Binding var page: HomePage
    let animation: Animation?
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(pages, id: \.self) { tab in
                PageTab(tab: tab, selected: tab == page, selection: selection) { page = tab }
            }
        }
        .padding(4)
        .animation(animation, value: page)
        .animation(animation, value: pages)
    }
}

private struct PageTab: View {
    let tab: HomePage
    let selected: Bool
    let selection: Namespace.ID
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol)
                if selected {
                    Text(tab.title)
                        .fixedSize()
                        .transition(.blurReplace)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.secondary))
            .padding(.horizontal, selected ? 14 : 0)
            .frame(minWidth: 36, minHeight: 28)
            .background {
                if selected {
                    Capsule().fill(.fill.secondary).matchedGeometryEffect(id: "selection", in: selection)
                } else {
                    Capsule().fill(.fill.quaternary).opacity(hovering ? 1 : 0)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(Pressable())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(tab.title)
    }
}
