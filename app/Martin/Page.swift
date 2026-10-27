import SwiftUI

struct Page<Header: View, Content: View>: View {
    let title: String
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content
    @State private var titlebar: CGFloat = 0
    @State private var viewport: CGFloat = 0
    @State private var collapsed = false

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .opacity(collapsed ? 1 : 0)
                .offset(y: collapsed ? 0 : 6)
                .animation(.easeOut(duration: 0.12), value: collapsed)
                .padding(.leading, Theme.controls)
                .padding(.trailing, Theme.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .frame(height: titlebar)
                .movesWindow()
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
            .clipped()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
        }
        .background(Theme.paper)
        .ignoresSafeArea(edges: .top)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { titlebar = $0 }
    }
}
