import SwiftUI

enum HomePage: CaseIterable {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch app.page {
            case .upcoming:
                UpcomingView(app: app)
                    .transition(transition(drifting: -36))
            case .settings:
                SettingsView(app: app)
                    .transition(transition(drifting: 44))
                    .zIndex(1)
            }
        }
        .animation(.default, value: app.page)
        .overlay(alignment: .topTrailing) {
            PageTabs(page: $app.page, animation: reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1))
                .padding([.top, .trailing], 4)
                .ignoresSafeArea(edges: .top)
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
    @Binding var page: HomePage
    let animation: Animation?
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HomePage.allCases, id: \.self) { tab in
                Button { page = tab } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13))
                        .foregroundStyle(tab == page ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.tertiary))
                        .frame(width: 28, height: 20)
                        .background {
                            if tab == page {
                                Capsule()
                                    .fill(Theme.paper)
                                    .matchedGeometryEffect(id: "selection", in: selection)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .padding(2)
        .background(Theme.well, in: .capsule)
        .animation(animation, value: page)
    }
}
