import AppKit
import MartinKit
import SwiftUI

struct AssistantSetup: View {
    static let size = NSSize(width: 480, height: 600)
    let app: AppState
    @State private var choice: Assistant
    @State private var statuses: [Assistant: Assistant.Status] = [:]

    init(app: AppState) {
        self.app = app
        _choice = State(initialValue: app.assistant ?? .claude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.cobalt, in: .rect(cornerRadius: 11, style: .continuous))
                .padding(.bottom, 16)
            Text("Choose an assistant")
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 6)
            Text("Martin uses it to read your notes and keep your projects up to date. Your notes go only to the assistant you choose.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)
            VStack(spacing: 8) {
                ForEach(Assistant.allCases) { assistant in
                    Button { choice = assistant } label: {
                        AssistantOption(assistant: assistant, status: statuses[assistant], selected: assistant == choice)
                    }
                    .buttonStyle(Pressable(scale: 0.98))
                }
            }
            .padding(.bottom, 22)
            if let status = statuses[choice] {
                AssistantStep(app: app, assistant: choice, status: status) { Task { await check() } }
                    .id(choice)
                    .transition(.opacity)
            }
            Spacer(minLength: 20)
            HStack {
                Spacer()
                Button("Not Now") { app.closeAssistantSetup() }
                    .keyboardShortcut(.cancelAction)
                Button("Use \(choice.title)") { app.use(choice) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(statuses[choice] != .ready)
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Theme.paper)
        .animation(.easeOut(duration: 0.15), value: choice)
        .animation(.easeOut(duration: 0.15), value: statuses)
        .task { await check() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await check() } }
    }

    private func check() async {
        async let claude = Assistant.claude.status()
        async let codex = Assistant.codex.status()
        statuses = [.claude: await claude, .codex: await codex]
    }
}

private struct AssistantOption: View {
    let assistant: Assistant
    let status: Assistant.Status?
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: assistant.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(assistant.hue, in: .rect(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(assistant.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Uses your \(assistant.account) account")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            StatusLabel(status: status)
        }
        .padding(12)
        .background(selected ? AnyShapeStyle(Theme.cobalt.opacity(0.08)) : AnyShapeStyle(Theme.well), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.cobalt, lineWidth: 1.5)
                .opacity(selected ? 1 : 0)
        }
        .contentShape(.rect)
        .pointerStyle(.link)
    }
}

private struct StatusLabel: View {
    let status: Assistant.Status?

    var body: some View {
        Group {
            switch status {
            case nil: ProgressView().controlSize(.small)
            case .ready: Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.cobalt)
            case .signedOut: Label("Not signed in", systemImage: "person.crop.circle.badge.exclamationmark").foregroundStyle(Theme.secondary)
            case .missing: Label("Not installed", systemImage: "arrow.down.circle").foregroundStyle(Theme.tertiary)
            }
        }
        .font(.system(size: 11.5, weight: .medium))
    }
}

private struct AssistantStep: View {
    let app: AppState
    let assistant: Assistant
    let status: Assistant.Status
    let check: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch status {
            case .ready:
                Text("\(assistant.title) is ready.")
                    .font(Theme.heading)
                    .foregroundStyle(Theme.ink)
            case .missing:
                instructions(title: "Install \(assistant.title)", command: assistant.install)
            case .signedOut:
                instructions(title: "Sign in to \(assistant.title)", command: assistant.signIn)
            }
        }
    }

    @ViewBuilder private func instructions(title: String, command: String) -> some View {
        Text(title)
            .font(Theme.heading)
            .foregroundStyle(Theme.ink)
        Text("Run this in Terminal, then come back.")
            .font(Theme.meta)
            .foregroundStyle(Theme.secondary)
        HStack(spacing: 8) {
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button("Copy", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(RowAction())
            .help("Copy")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Theme.well, in: .rect(cornerRadius: 8, style: .continuous))
        HStack(spacing: 8) {
            Button("Open in Terminal") { app.runInTerminal(command, titled: title) }
            Button("Check Again", action: check)
        }
    }
}

private extension Assistant {
    var symbol: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "hexagon"
        }
    }

    var hue: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.11, green: 0.12, blue: 0.13)
        }
    }
}
