import AppKit
import Testing
@testable import Martin

@MainActor
struct NoteTextViewTests {
    @Test(arguments: ["", "# Standup\n- shipped icons"])
    func openingANoteFocusesItsEditorWithTheCaretAtTheEnd(note: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: .titled, backing: .buffered, defer: true)
        let textView = NoteTextView.make()
        textView.load(note)
        window.contentView = textView
        #expect(window.firstResponder === textView)
        #expect(textView.selectedRange() == NSRange(location: (note as NSString).length, length: 0))
    }

    @Test func theCursorBecomesAPointingHandOverACheckbox() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: .titled, backing: .buffered, defer: false)
        let textView = NoteTextView.make()
        textView.frame = window.contentRect(forFrameRect: window.frame)
        textView.load("- [ ] milk")
        window.contentView = textView
        func point(over location: Int) -> NSPoint {
            let rect = window.convertFromScreen(textView.firstRect(forCharacterRange: NSRange(location: location, length: 1), actualRange: nil))
            return textView.convert(NSPoint(x: rect.midX, y: rect.midY), from: nil)
        }
        #expect(textView.cursor(at: point(over: 3)) == .pointingHand)
        #expect(textView.cursor(at: point(over: 7)) == nil)
        textView.isEditable = false
        #expect(textView.cursor(at: point(over: 3)) == nil)
    }
}
