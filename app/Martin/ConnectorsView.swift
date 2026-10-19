import MartinKit
import SwiftUI

struct ConnectorsView: View {
    @State private var sources: [Analyzer.Source] = []
    @State private var loading = false
    @State private var failure: String?

    var body: some View {
        SettingsSection(title: "Connectors", summary: "Where your work lives. Martin reads it through GitHub CLI and the connectors you use in Claude, and never writes.") {
            Button(loading ? "Checking…" : "Refresh") { Task { await load() } }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .disabled(loading)
        } content: {
            ForEach(sources) { source in
                SourceRow(source: source, divided: source.id != sources.first?.id)
            }
            if let failure {
                Text(failure)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ember)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { Hairline(divided: !sources.isEmpty) }
            }
            Link(destination: URL(string: "https://claude.ai/settings/connectors")!) {
                Label("Manage connectors in Claude", systemImage: "arrow.up.right")
                    .font(.system(size: 13))
            }
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .overlay(alignment: .top) { Hairline(divided: !sources.isEmpty || failure != nil) }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        failure = nil
        do {
            sources = try await Analyzer.sources()
        } catch {
            failure = error.localizedDescription
        }
        loading = false
    }
}

private struct SourceRow: View {
    let source: Analyzer.Source
    let divided: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(source.name.first.map { String($0).uppercased() } ?? "·")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondary)
                .frame(width: 28, height: 28)
                .background(Theme.paper, in: .rect(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(source.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                if let detail = source.detail ?? hint {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                        .textSelection(.enabled)
                }
            }
            .opacity(source.connected ? 1 : 0.7)
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Circle()
                    .fill(source.connected ? AnyShapeStyle(Theme.moss) : AnyShapeStyle(Theme.tertiary))
                    .frame(width: 6, height: 6)
                Text(source.connected ? "Connected" : label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Hairline(divided: divided) }
    }

    private var label: String {
        switch source.status {
        case "needs-auth": "Sign in"
        case "missing": "Not installed"
        case "disabled": "Off"
        default: "Unavailable"
        }
    }

    private var hint: String? {
        source.status == "needs-auth" ? "Sign in under Claude’s connector settings" : nil
    }
}
