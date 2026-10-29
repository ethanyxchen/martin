import AppKit
import MartinKit
import SwiftUI

struct RepositoryCard: View {
    let app: AppState
    let project: Project
    let repository: RepositoryLink

    var body: some View {
        content.task(id: project.id) { await app.suggestRepository(for: project) }
    }

    @ViewBuilder private var content: some View {
        switch repository {
        case .folder(let folder):
            if let repository = Repository(at: folder) {
                card(icon: "chevron.left.forwardslash.chevron.right", tint: Theme.ink, title: repository.slug, detail: [folder.abbreviated, repository.branch].compactMap(\.self).joined(separator: " · ")) {
                    linkedMenu(repository)
                }
            } else {
                card(icon: "exclamationmark.triangle", tint: Theme.secondary, title: folder.lastPathComponent, detail: "Not found at \(folder.abbreviated)") {
                    linkedMenu(nil)
                }
            }
        case .unset:
            card(icon: "link", tint: Theme.secondary, title: "Link a repository", detail: "Choose its folder on your Mac", tentative: true, busy: app.suggestions[project.id] == .thinking) {
                Menu("Link…") { LinkChoices(app: app, project: project) }
                    .menuButton(Chip())
            }
        }
    }

    private func linkedMenu(_ repository: Repository?) -> some View {
        Menu("Repository", systemImage: "ellipsis") {
            if let repository {
                Button("Open on GitHub", systemImage: "safari") { NSWorkspace.shared.open(repository.web) }
                Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([repository.folder]) }
                Divider()
            }
            Menu("Change Repository", systemImage: "arrow.triangle.swap") { LinkChoices(app: app, project: project) }
            Button("Remove Repository", systemImage: "link.badge.minus") { app.link(project, to: nil) }
        }
        .menuButton(RowAction())
    }

    private func card(icon: String, tint: some ShapeStyle, title: String, detail: String, tentative: Bool = false, busy: Bool = false, @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 12) {
            Group {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tint)
                }
            }
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
                    .lineLimit(1)
                    .truncationMode(.middle)
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
        let choices = app.clones.filter { $0.folder != project.repository?.folder }.prefix(Self.shown)
        if !choices.isEmpty {
            Section("On This Mac") {
                ForEach(choices, id: \.folder) { repository in
                    Button(repository.slug) { app.link(project, to: .folder(repository.folder)) }
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
