import MartinKit
import SwiftUI

enum Screen: Hashable {
    case note(Meeting.ID)
    case archive
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

    var body: some View {
        Turnstile(value: app.path.last, motion: { app.motion }) { screen }
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

struct Turnstile<Value: Hashable, Content: View>: View {
    let value: Value
    let motion: @MainActor () -> Motion
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            content
                .id(value)
                .transition(reduceMotion ? .identity : .asymmetric(
                    insertion: AnyTransition(Turn(motion: motion)).animation(.drawer(0.4).delay(0.07)),
                    removal: AnyTransition(Turn(motion: motion)).animation(.drawer(0.3))
                ))
        }
        .animation(reduceMotion ? nil : .default, value: value)
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
