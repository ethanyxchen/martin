import SwiftUI

struct Page<Header: View, Content: View>: View {
    var title: String?
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content
    @State private var viewport: CGFloat = 0
    @State private var toolbar: CGFloat = 0
    @State private var headerEdge: CGFloat = .infinity
    @State private var titleEdge: CGFloat?
    private var collapsed: Bool { (titleEdge ?? headerEdge) <= toolbar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).maxY } action: { headerEdge = $0 }
                    .onPreferenceChange(TitleEdge.self) { titleEdge = $0 }
                    .padding(.top, 18)
                    .padding(.bottom, 22)
                    .movesWindow()
                content
            }
            .frame(minHeight: viewport, alignment: .top)
        }
        .coordinateSpace(name: "pageScroll")
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height - $0.contentInsets.top - $0.contentInsets.bottom } action: { viewport = $1 }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { toolbar = $1 }
        .background(Theme.paper)
        .toolbar {
            if let title {
                ToolbarItem(placement: .navigation) {
                    Text(title)
                        .font(Theme.heading)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .opacity(collapsed ? 1 : 0)
                        .offset(y: collapsed ? 0 : 6)
                        .animation(.easeOut(duration: 0.12), value: collapsed)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
    }
}

private struct TitleEdge: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

extension View {
    /// Marks the view whose bottom edge decides when a page's title moves into the window bar.
    func pageTitle() -> some View {
        overlay(GeometryReader { proxy in
            Color.clear.preference(key: TitleEdge.self, value: proxy.frame(in: .named("pageScroll")).maxY)
        })
    }
}

struct PageHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
            if let detail {
                Text(detail)
                    .font(Theme.meta)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .flush()
    }
}
