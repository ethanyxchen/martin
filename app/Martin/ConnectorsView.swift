import MartinKit
import SwiftUI

struct ConnectorsView: View {
    @Binding var connectors: [Connector]
    @State private var statuses: [String: Analyzer.ConnectorStatus] = [:]
    @State private var checking = false
    @State private var failure: String?
    @State private var expanded: Connector.ID?

    var body: some View {
        SettingsSection(title: "Connectors", summary: "Where your work lives. Martin looks here to tell your work from everyone else’s.") {
            if !connectors.isEmpty {
                Button(checking ? "Checking…" : "Check connections") { Task { await check() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .disabled(checking)
            }
        } content: {
            ForEach($connectors) { $connector in
                ConnectorRow(
                    connector: $connector,
                    status: statuses[connector.name],
                    checking: checking,
                    divided: connector.id != connectors.first?.id,
                    expanded: Binding { expanded == connector.id } set: { expanded = $0 ? connector.id : nil },
                    remove: { remove(connector) }
                )
            }
            if let failure {
                Text(failure)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ember)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { Hairline(divided: !connectors.isEmpty) }
            }
            addMenu
                .overlay(alignment: .top) { Hairline(divided: !connectors.isEmpty || failure != nil) }
        }
        .animation(.easeOut(duration: 0.2), value: expanded)
        .animation(.easeOut(duration: 0.2), value: connectors.count)
    }

    private var addMenu: some View {
        Menu {
            ForEach(Connector.presets.filter { preset in !connectors.contains { $0.url == preset.url } }) { preset in
                Button(preset.name) { add(Connector(name: preset.name, url: preset.url)) }
            }
            Divider()
            Button("Custom Server…") { add(Connector(name: "", url: URL(string: "https://")!)) }
        } label: {
            Label(connectors.isEmpty ? "Connect GitHub, Linear or Slack" : "Add connector", systemImage: "plus")
                .font(.system(size: 13))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func add(_ connector: Connector) {
        connectors.append(connector)
        expanded = connector.id
    }

    private func remove(_ connector: Connector) {
        Secrets.set(nil, for: connector.secretKey)
        connectors.removeAll { $0.id == connector.id }
    }

    private func check() async {
        checking = true
        failure = nil
        do {
            statuses = Dictionary(try await Analyzer.check(connectors).map { ($0.name, $0) }) { first, _ in first }
        } catch {
            failure = error.localizedDescription
        }
        checking = false
    }
}

private struct ConnectorRow: View {
    @Binding var connector: Connector
    let status: Analyzer.ConnectorStatus?
    let checking: Bool
    let divided: Bool
    @Binding var expanded: Bool
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Monogram(name: connector.name)
                VStack(alignment: .leading, spacing: 1) {
                    Text(connector.name.isEmpty ? "New connector" : connector.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(connector.url.host() ?? "Add a server URL")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                }
                .opacity(connector.enabled ? 1 : 0.55)
                Spacer(minLength: 12)
                StatusBadge(status: status, checking: checking && connector.enabled)
                Toggle("Enabled", isOn: $connector.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(.rect)
            .onTapGesture { expanded.toggle() }
            if expanded {
                ConnectorEditor(connector: $connector, error: status?.error, remove: remove)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) { Hairline(divided: divided) }
    }
}

private struct ConnectorEditor: View {
    @Binding var connector: Connector
    let error: String?
    let remove: () -> Void
    @State private var url: String

    init(connector: Binding<Connector>, error: String?, remove: @escaping () -> Void) {
        _connector = connector
        self.error = error
        self.remove = remove
        _url = State(initialValue: connector.wrappedValue.url.absoluteString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRow(label: "Name", hint: "How notes refer to it") {
                TextField("Name", text: $connector.name)
            }
            FieldRow(label: "Server URL", hint: "A remote MCP endpoint") {
                TextField("https://", text: $url)
            }
            FieldRow(label: "Token", hint: "Sent as a bearer token") {
                SecretField(key: connector.secretKey, prompt: "Optional")
            }
            HStack(alignment: .firstTextBaseline) {
                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ember)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Remove", action: remove)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .padding(.leading, 40)
        .onChange(of: url) {
            guard let parsed = URL(string: url.trimmingCharacters(in: .whitespaces)), parsed.scheme?.hasPrefix("http") == true, parsed.host() != nil else { return }
            connector.url = parsed
        }
    }
}

private struct Monogram: View {
    let name: String

    var body: some View {
        Text(name.first.map { String($0).uppercased() } ?? "·")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.secondary)
            .frame(width: 28, height: 28)
            .background(Theme.paper, in: .rect(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}

private struct StatusBadge: View {
    let status: Analyzer.ConnectorStatus?
    let checking: Bool

    var body: some View {
        if checking {
            ProgressView().controlSize(.mini)
        } else if let status {
            HStack(spacing: 6) {
                Circle()
                    .fill(status.ok ? AnyShapeStyle(Theme.moss) : AnyShapeStyle(Theme.ember))
                    .frame(width: 6, height: 6)
                Text(status.ok ? "\(status.tools) tools" : "Can’t connect")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
            }
            .help(status.error ?? "")
        }
    }
}
