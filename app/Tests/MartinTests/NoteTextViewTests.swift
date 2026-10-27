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
}
