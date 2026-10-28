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

    var body: some View {
        ZStack {
            view(of: app.page)
                .id(app.page)
                .transition(transition(drifting: CGFloat(app.page.order) * 26 - 36))
                .zIndex(Double(app.page.order))
        }
        .animation(.default, value: app.page)
        .overlay(alignment: .topTrailing) {
            PageTabs(pages: app.pages, page: $app.page, animation: reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2))
                .padding([.top, .trailing], 4)
                .ignoresSafeArea(edges: .top)
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

    private func transition(drifting x: CGFloat) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        let drift = AnyTransition.offset(x: x).combined(with: .opacity)
        return .asymmetric(
            insertion: drift.animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.4).delay(0.07)),
            removal: drift.animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.3))
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
                let selected = tab == page
                Button { page = tab } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                        if selected {
                            Text(tab.title)
                                .fixedSize()
                                .transition(.opacity)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.tertiary))
                    .padding(.horizontal, selected ? 9 : 0)
                    .frame(minWidth: 28, minHeight: 20)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.paper)
                                .shadow(color: .black.opacity(0.14), radius: 1, y: 0.5)
                                .matchedGeometryEffect(id: "selection", in: selection)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(Pressable())
                .help(tab.title)
            }
        }
        .padding(2)
        .background(Theme.well, in: .capsule)
        .animation(animation, value: page)
        .animation(animation, value: pages)
    }
}

private struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
