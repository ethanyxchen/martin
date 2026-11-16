import AppKit
import MartinKit
import SwiftUI
import Testing
@testable import Martin

@MainActor
final class NavigatorTests: Sandbox {
    @Test func aPushSlidesTheNewScreenInFromTheRightAndAPopFromTheLeft() {
        #expect(Motion.push.offset(.willAppear) == 44)
        #expect(Motion.push.offset(.didDisappear) == -36)
        #expect(Motion.pop.offset(.willAppear) == -36)
        #expect(Motion.pop.offset(.didDisappear) == 44)
        #expect(Motion.replace.offset(.willAppear) == 0)
        #expect(Motion.replace.offset(.didDisappear) == 0)
        #expect([Motion.push, .pop, .replace].map { $0.offset(.identity) } == [0, 0, 0])
    }

    @Test func screensStackAboveHomeAndBackReturnsThroughThem() throws {
        let meeting = try library.create(title: "Standup")
        let app = AppState(library: library, defaults: defaults)
        app.open(meeting)
        #expect(app.path == [.note(meeting.id)])
        #expect(app.motion == .push)
        app.openArchive()
        #expect(app.path == [.note(meeting.id), .archive])
        app.back()
        #expect(app.path == [.note(meeting.id)])
        #expect(app.motion == .pop)
        app.back()
        #expect(app.path.isEmpty)
    }

    @Test func openingAScreenAlreadyInTheStackGoesBackToIt() throws {
        let standup = try library.create(title: "Standup")
        let retro = try library.create(title: "Retro")
        let app = AppState(library: library, defaults: defaults)
        app.openArchive()
        app.open(standup)
        app.open(retro)
        app.openArchive()
        #expect(app.path == [.archive])
        #expect(app.motion == .pop)
        app.open(standup)
        app.open(standup)
        #expect(app.path == [.archive, .note(standup.id)])
    }

    @Test func goingHomeLeavesEveryScreenOnThePageAsked() throws {
        let app = AppState(library: library, defaults: defaults)
        app.open(try library.create())
        app.openArchive()
        app.openHome(on: .upcoming)
        #expect(app.path.isEmpty)
        #expect(app.motion == .pop)
        #expect(app.page == .upcoming)
    }

    @Test func everyScreenOpensInTheOneWindowWithABackArrowAboveHome() async throws {
        let meeting = try library.create(title: "Standup")
        let app = AppState(library: library, defaults: defaults)
        let window = app.window
        func back() async throws -> NSToolbarItem? {
            for _ in 0..<50 {
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            return window.toolbar?.items.first { $0.label == "Back" }
        }
        #expect(try await back() == nil)
        app.open(meeting)
        #expect(try await back() != nil)
        app.openArchive()
        #expect(app.window === window)
        #expect(try await back() != nil)
        app.openHome(on: .notes)
        #expect(try await back() == nil)
    }
}
