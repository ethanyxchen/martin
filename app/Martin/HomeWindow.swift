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
        GlassEffectContainer {
            HStack(spacing: 2) {
                ForEach(pages, id: \.self) { tab in
                    let selected = tab == page
                    Button { page = tab } label: {
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
                        .glassEffect(selected ? .regular.interactive() : .identity, in: .capsule)
                        .glassEffectID(selected ? "selection" : nil, in: selection)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(Pressable())
                    .help(tab.title)
                }
            }
            .padding(4)
        }
        .animation(animation, value: page)
        .animation(animation, value: pages)
    }
}
