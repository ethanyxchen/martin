import SwiftUI

struct Page<Header: View, Content: View>: View {
    var title: String?
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content
    @State private var viewport: CGFloat = 0
    @State private var collapsed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY <= 0 } action: { collapsed = $0 }
                    .padding(.top, 18)
                    .padding(.bottom, 22)
                    .movesWindow()
                content
            }
            .frame(minHeight: viewport, alignment: .top)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height - $0.contentInsets.top - $0.contentInsets.bottom } action: { viewport = $1 }
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
