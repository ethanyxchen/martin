import MartinKit
import SwiftUI

enum Screen: Hashable {
    case note(Meeting.ID)
    case archive
    case assistant
}

enum Motion {
    case push
    case pop
    case replace

    func offset(_ phase: TransitionPhase) -> CGFloat {
        switch (self, phase) {
        case (.push, .willAppear), (.pop, .didDisappear): 44
        case (.push, .didDisappear), (.pop, .willAppear): -36
        default: 0
        }
    }
}

struct Navigator: View {
    let app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            screen
                .id(app.path.last)
                .transition(.turn { reduceMotion ? .replace : app.motion })
        }
        .animation(reduceMotion ? nil : .default, value: app.path.last)
        .toolbar {
            if !app.path.isEmpty {
                ToolbarItem(placement: .navigation) {
                    Button("Back", systemImage: "chevron.left", action: app.back)
                        .help("Back (⌘[)")
                }
            }
        }
    }

    @ViewBuilder private var screen: some View {
        switch app.path.last {
        case nil: HomeView(app: app)
        case .note(let id): app.meeting(id).map { NoteView(app: app, meeting: $0) }
        case .archive: ArchiveView(app: app)
        case .assistant: AssistantSetup(app: app)
        }
    }
}

struct BackButton: View {
    let app: AppState

    var body: some View {
        Button("Back", action: app.back)
            .keyboardShortcut("[")
            .disabled(app.path.isEmpty)
    }
}

extension AnyTransition {
    static func turn(_ motion: @escaping @MainActor () -> Motion) -> AnyTransition {
        .asymmetric(
            insertion: AnyTransition(Turn(motion: motion)).animation(.drawer(0.4).delay(0.07)),
            removal: AnyTransition(Turn(motion: motion)).animation(.drawer(0.3))
        )
    }
}

private struct Turn: Transition {
    let motion: @MainActor () -> Motion

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .offset(x: motion().offset(phase))
    }
}
