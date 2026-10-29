import AppKit
import MartinKit
import SwiftUI

struct RepositoryCard: View {
    let app: AppState
    let project: Project

    var body: some View {
        content.task(id: project.id) { await app.suggestRepository(for: project) }
    }

    @ViewBuilder private var content: some View {
        if let folder = project.repository {
            if let repository = Repository(at: folder) {
                card(icon: "chevron.left.forwardslash.chevron.right", tint: Theme.ink, title: repository.slug, detail: [folder.abbreviated, repository.branch].compactMap(\.self).joined(separator: " · ")) {
                    linkedMenu(repository)
                }
            } else {
                card(icon: "exclamationmark.triangle", tint: Theme.secondary, title: folder.lastPathComponent, detail: "No GitHub repository at \(folder.abbreviated)") {
                    linkedMenu(nil)
                }
            }
        } else {
            switch app.suggestions[project.id] {
            case .found(let pick?):
                card(icon: "sparkles", tint: Theme.cobalt, title: pick.repository.slug, detail: pick.reason, tentative: true) {
                    Button("Link") { app.link(project, to: pick.repository.folder) }
                        .buttonStyle(Chip())
                        .help("Link \(pick.repository.folder.abbreviated) to \(project.name)")
                    Menu("Other Repositories", systemImage: "ellipsis") { LinkChoices(app: app, project: project) }
                        .menuButton(RowAction())
                }
            case .thinking:
                card(icon: "sparkles", tint: Theme.cobalt, title: "Finding this project’s repository…", detail: "Claude is reading your notes and local clones", tentative: true, pulsing: true) { linkMenu }
            case .found(nil), nil:
                card(icon: "link", tint: Theme.secondary, title: "Link a repository", detail: "Pick the clone of this project’s GitHub repo", tentative: true) { linkMenu }
            }
        }
    }

    private var linkMenu: some View {
        Menu("Link…") { LinkChoices(app: app, project: project) }
            .menuButton(Chip())
    }

    private func linkedMenu(_ repository: Repository?) -> some View {
        Menu("Repository", systemImage: "ellipsis") {
            if let repository {
                Button("Open on GitHub", systemImage: "safari") { NSWorkspace.shared.open(repository.web) }
                Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([repository.folder]) }
                Divider()
            }
            Menu("Change Repository", systemImage: "arrow.triangle.swap") { LinkChoices(app: app, project: project) }
            Button("Unlink Repository", systemImage: "link.badge.minus") { app.link(project, to: nil) }
        }
        .menuButton(RowAction())
    }

    private func card(icon: String, tint: some ShapeStyle, title: String, detail: String, tentative: Bool = false, pulsing: Bool = false, @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: pulsing)
                .frame(width: 32, height: 32)
                .background(tentative ? AnyShapeStyle(Theme.well) : AnyShapeStyle(Theme.paper), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) { actions() }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            if tentative {
                shape.strokeBorder(Theme.tertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else {
                shape.fill(Theme.well)
            }
        }
        .flush()
        .padding(.bottom, 14)
    }
}

private struct LinkChoices: View {
    private static let shown = 8
    let app: AppState
    let project: Project

    var body: some View {
        let choices = app.clones.filter { $0.folder != project.repository }.prefix(Self.shown)
        if !choices.isEmpty {
            Section("On This Mac") {
                ForEach(choices, id: \.folder) { repository in
                    Button(repository.slug) { app.link(project, to: repository.folder) }
                }
            }
            Divider()
        }
        Button("Choose Folder…") { app.chooseRepository(for: project) }
    }
}

private struct Chip: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.cobalt, in: .capsule)
            .contentShape(.capsule)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .pointerStyle(.link)
    }
}

private extension View {
    func menuButton(_ style: some ButtonStyle) -> some View {
        menuStyle(.button).menuIndicator(.hidden).buttonStyle(style)
    }
}

extension URL {
    var abbreviated: String {
        (path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}
