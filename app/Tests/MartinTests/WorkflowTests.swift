import AppKit
import MartinKit
import Testing
@testable import Martin

@MainActor
final class WorkflowTests: Sandbox {
    private lazy var app = AppState(library: library, defaults: defaults)

    private func open(_ meeting: Meeting, in app: AppState? = nil) async throws -> (NSWindow, NoteTextView) {
        let app = app ?? self.app
        let window = app.window
        app.open(meeting)
        for _ in 0..<100 where editor(in: window) == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        let editor = try #require(self.editor(in: window))
        window.makeFirstResponder(editor)
        return (window, editor)
    }

    private func editor(in window: NSWindow) -> NoteTextView? {
        window.contentView?.descendants.lazy.compactMap { $0 as? NoteTextView }.first
    }

    private func type(_ text: String, into editor: NoteTextView) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.offset > 0 { editor.doCommand(by: #selector(NSResponder.insertNewline(_:))) }
            editor.insertText(String(line.element), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    private func saved(_ meeting: Meeting, as note: String) async throws -> Bool {
        for _ in 0..<100 where library.note(of: meeting) != note {
            try await Task.sleep(for: .milliseconds(20))
        }
        return library.note(of: meeting) == note
    }

    @Test func whatIsTypedIsSavedPreviewedAndThereOnReopening() async throws {
        let meeting = try library.create()
        let (_, editor) = try await open(meeting)
        type("# Standup\nTasks:\n- shipped icons\n\n", into: editor)
        #expect(editor.string == "# Standup\nTasks:\n- shipped icons\n")
        #expect(try await saved(meeting, as: "# Standup\nTasks:\n- shipped icons\n"))
        #expect(app.previews[meeting.id] == "Standup")
        app.back()
        let relaunched = AppState(library: library, defaults: defaults)
        let (reopened, again) = try await open(meeting, in: relaunched)
        #expect(again.string == "# Standup\nTasks:\n- shipped icons\n")
        #expect(reopened === relaunched.window)
    }

    @Test func goingBackFromANoteSavesWhatWasJustTyped() async throws {
        let meeting = try library.create()
        let (_, editor) = try await open(meeting)
        type("last words", into: editor)
        app.back()
        #expect(try await saved(meeting, as: "last words"))
    }

    @Test func goingBackWhileEditingTheTitleKeepsTheNewTitle() async throws {
        let meeting = try library.create()
        let (window, _) = try await open(meeting)
        let field = try #require(window.contentView?.descendants.lazy.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        window.makeFirstResponder(field)
        field.currentEditor()?.insertText("Retro")
        app.back()
        for _ in 0..<100 where app.meeting(meeting.id)?.title != "Retro" {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(app.meeting(meeting.id)?.title == "Retro")
    }

    @Test(arguments: [NSApplication.willTerminateNotification, NSWindow.willCloseNotification])
    func quittingOrClosingWhileEditingTheTitleKeepsTheNewTitle(_ leaving: Notification.Name) async throws {
        let meeting = try library.create()
        let (window, _) = try await open(meeting)
        let field = try #require(window.contentView?.descendants.lazy.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        window.makeFirstResponder(field)
        field.currentEditor()?.insertText("Retro")
        NotificationCenter.default.post(name: leaving, object: leaving == NSWindow.willCloseNotification ? window : nil)
        #expect(app.meeting(meeting.id)?.title == "Retro")
    }

    @Test func archivingAnOpenNoteLeavesItAndKeepsWhatWasJustTyped() async throws {
        let meeting = try library.create()
        let (_, editor) = try await open(meeting)
        type("keep this", into: editor)
        app.archive(meeting)
        #expect(app.path.isEmpty)
        #expect(app.archive.map(\.id) == [meeting.id])
        #expect(try await saved(meeting, as: "keep this"))
    }

    @Test func deletingAnOpenNoteLeavesNothingBehind() async throws {
        let meeting = try library.create()
        let (_, editor) = try await open(meeting)
        type("doomed", into: editor)
        app.delete(meeting)
        try await Task.sleep(for: .seconds(1))
        #expect(!FileManager.default.fileExists(atPath: library.folder(of: meeting).path(percentEncoded: false)))
        #expect(app.meetings.isEmpty)
    }

    @Test func formattingASelectionIsSavedAndUndoneInOneStep() async throws {
        let meeting = try library.create()
        try library.saveNote("say word", for: meeting)
        let (_, editor) = try await open(meeting)
        editor.setSelectedRange(NSRange(location: 4, length: 4))
        editor.toggleBold(nil)
        #expect(try await saved(meeting, as: "say **word**"))
        editor.undoManager?.undo()
        #expect(try await saved(meeting, as: "say word"))
    }

    @Test func clickingACheckboxTicksItAndSavesTheNote() async throws {
        let meeting = try library.create()
        try library.saveNote("- [ ] milk", for: meeting)
        let (window, editor) = try await open(meeting)
        let box = window.convertFromScreen(editor.firstRect(forCharacterRange: NSRange(location: 3, length: 1), actualRange: nil))
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: box.midX, y: box.midY), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        editor.mouseDown(with: click)
        #expect(try await saved(meeting, as: "- [x] milk"))
    }

    @Test func backspacingIntoAMentionRemovesTheWholeMention() async throws {
        let meeting = try library.create()
        try library.saveNote("ask @{Kim K <kim.k@example.com>}", for: meeting)
        let (_, editor) = try await open(meeting)
        editor.deleteBackward(nil)
        #expect(try await saved(meeting, as: "ask "))
    }

    @Test func archivingAProjectLeavesItsOpenNoteAndKeepsWhatWasJustTyped() async throws {
        let meeting = try library.create(title: "Kickoff")
        app.file(meeting, inNewProjectNamed: "Atlas")
        let (_, editor) = try await open(try #require(app.meeting(meeting.id)))
        type("- scope the redesign", into: editor)
        app.archive(try #require(app.projects.first))
        #expect(app.path.isEmpty)
        #expect(app.notes.isEmpty)
        #expect(app.archivedProjects.map(\.name) == ["Atlas"])
        #expect(try await saved(meeting, as: "- scope the redesign"))
    }
}
