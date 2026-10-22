import AppKit
import MartinKit
import SwiftUI

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var editable = true

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NoteTextView.make()
        textView.delegate = context.coordinator
        textView.isEditable = editable
        textView.load(text)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.storageChanged(_:)), name: NSTextStorage.didProcessEditingNotification, object: textView.textStorage)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: Theme.margin, right: 0)
        scroll.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: -Theme.margin, right: 0)
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scroll.documentView as? NoteTextView else { return }
        textView.isEditable = editable
        if textView.string != text { textView.load(text) }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func storageChanged(_ notification: Notification) {
            guard let storage = notification.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) else { return }
            let markdown = storage.nativeString
            if text.wrappedValue != markdown { text.wrappedValue = markdown }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            selector == #selector(NSResponder.insertNewline(_:)) && (textView as? NoteTextView)?.continueList() == true
        }
    }
}

final class NoteTextView: NSTextView {
    struct Format {
        let title: String
        let key: Character
        let shift: Bool
        let action: Selector
    }

    static let formats = [
        Format(title: "Bold", key: "b", shift: false, action: #selector(toggleBold(_:))),
        Format(title: "Italic", key: "i", shift: false, action: #selector(toggleItalic(_:))),
        Format(title: "Strikethrough", key: "x", shift: true, action: #selector(toggleStrikethrough(_:))),
        Format(title: "Code", key: "c", shift: true, action: #selector(toggleCode(_:))),
        Format(title: "Link", key: "k", shift: false, action: #selector(insertLink(_:))),
    ]

    private let style = MarkdownStyle()

    static func make() -> NoteTextView {
        let view = NoteTextView(usingTextLayoutManager: true)
        view.textContentStorage?.delegate = view.style
        view.textLayoutManager?.delegate = view.style
        view.textStorage?.delegate = view.style
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = .width
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = NSSize(width: Theme.column - MarkdownStyle.hang, height: 2)
        view.isContinuousSpellCheckingEnabled = true
        view.insertionPointColor = Theme.ink.ns
        view.typingAttributes = MarkdownStyle.typing
        view.defaultParagraphStyle = MarkdownStyle.typing[.paragraphStyle] as? NSParagraphStyle
        return view
    }

    override var isEditable: Bool {
        didSet { if isEditable != oldValue { isContinuousSpellCheckingEnabled = isEditable } }
    }

    func load(_ markdown: String) {
        textStorage?.setAttributedString(NSAttributedString(string: markdown, attributes: MarkdownStyle.typing))
        undoManager?.removeAllActions()
    }

    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        let width = enclosingScrollView?.frame.width ?? size.width
        let inset = Theme.column - MarkdownStyle.hang + max(0, (width - Theme.page) / 2)
        if textContainerInset.width != inset { textContainerInset.width = inset }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        reveal(window?.firstResponder === self ? selectedRange() : nil)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { reveal(selectedRange()) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { reveal(nil) }
        return resigned
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command) || !isEditable, let url = character(under: point).flatMap(link(at:)) {
            NSWorkspace.shared.open(url)
        } else if isEditable, let mark = checkbox(at: characterIndexForInsertion(at: point), under: point) {
            let tick = (string as NSString).substring(with: mark) == " " ? "x" : " "
            apply(Markdown.Edit(range: mark, replacement: tick, selection: selectedRange()))
        } else {
            super.mouseDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        guard let menu, isEditable else { return menu }
        let formats = NSMenu(title: "Format")
        for format in Self.formats {
            let item = formats.addItem(withTitle: format.title, action: format.action, keyEquivalent: String(format.key))
            item.keyEquivalentModifierMask = format.shift ? [.command, .shift] : .command
        }
        let item = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        item.submenu = formats
        let index = menu.items.firstIndex { $0.action == #selector(paste(_:)) }.map { $0 + 1 } ?? 0
        menu.insertItem(item, at: index)
        return menu
    }

    override func handleTextCheckingResults(_ results: [NSTextCheckingResult], forRange range: NSRange, types checkingTypes: NSTextCheckingTypes, options: [NSSpellChecker.OptionKey: Any] = [:], orthography: NSOrthography, wordCount: Int) {
        let prose = results.filter { $0.resultType != .spelling || isProse($0.range) }
        super.handleTextCheckingResults(prose, forRange: range, types: checkingTypes, options: options, orthography: orthography, wordCount: wordCount)
    }

    @objc func toggleBold(_ sender: Any?) {
        apply(Markdown.toggle("**", in: string, selection: selectedRange()))
    }

    @objc func toggleItalic(_ sender: Any?) {
        apply(Markdown.toggle("*", in: string, selection: selectedRange()))
    }

    @objc func toggleStrikethrough(_ sender: Any?) {
        apply(Markdown.toggle("~~", in: string, selection: selectedRange()))
    }

    @objc func toggleCode(_ sender: Any?) {
        apply(Markdown.toggle("`", in: string, selection: selectedRange()))
    }

    @objc func insertLink(_ sender: Any?) {
        apply(Markdown.link(in: string, selection: selectedRange()))
    }

    func continueList() -> Bool {
        let caret = selectedRange()
        guard caret.length == 0, !hasMarkedText() else { return false }
        let text = string as NSString
        let (range, line) = style.line(at: caret.location, in: text)
        guard caret.location >= range.location + line.prefix, let next = line.continuation(in: text.substring(with: range)) else { return false }
        if line.prefix == range.length {
            apply(Markdown.Edit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0)))
        } else {
            apply(Markdown.Edit(range: caret, replacement: "\n" + next, selection: NSRange(location: caret.location + 1 + (next as NSString).length, length: 0)))
        }
        return true
    }

    private func line(at index: Int) -> (range: NSRange, line: Markdown.Line)? {
        let text = string as NSString
        return text.length == 0 ? nil : style.line(at: min(index, text.length - 1), in: text)
    }

    private func link(at index: Int) -> URL? {
        guard let (range, line) = line(at: index) else { return nil }
        let text = string as NSString
        for span in line.spans {
            guard NSLocationInRange(index - range.location, span.range) else { continue }
            switch span.role {
            case .link(let destination): return URL(string: text.substring(with: destination.offset(by: range.location)))
            case .reference(let destination): return URL(string: destination)
            case .url: return URL(string: text.substring(with: span.range.offset(by: range.location)))
            default: continue
            }
        }
        return nil
    }

    private func checkbox(at index: Int, under point: NSPoint) -> NSRange? {
        guard let (range, line) = line(at: index), let box = line.spans.first(where: { $0.role == .checkbox })?.range.offset(by: range.location) else { return nil }
        return rect(of: box)?.insetBy(dx: -3, dy: -3).contains(point) == true ? NSRange(location: box.location + 1, length: 1) : nil
    }

    private func character(under point: NSPoint) -> Int? {
        let index = characterIndexForInsertion(at: point)
        return [index, index - 1].first { NSLocationInRange($0, NSRange(location: 0, length: (string as NSString).length)) && rect(of: NSRange(location: $0, length: 1))?.insetBy(dx: -1, dy: -4).contains(point) == true }
    }

    private func rect(of range: NSRange) -> NSRect? {
        guard let window else { return nil }
        return convert(window.convertFromScreen(firstRect(forCharacterRange: range, actualRange: nil)), from: nil)
    }

    private func isProse(_ word: NSRange) -> Bool {
        guard NSMaxRange(word) <= (string as NSString).length else { return false }
        let (range, line) = style.line(at: word.location, in: string as NSString)
        guard line.block != .code, line.block != .fence else { return false }
        return !line.spans.contains { span in
            let literal = switch span.role {
            case .code, .url: true
            case .link(let destination): destination == span.range
            default: false
            }
            return literal && NSIntersectionRange(span.range.offset(by: range.location), word).length > 0
        }
    }

    private func reveal(_ selection: NSRange?) {
        guard let textStorage, let textLayoutManager, let content = textContentStorage else { return }
        for range in style.select(selection, in: textStorage.string as NSString) {
            textStorage.edited(.editedAttributes, range: range, changeInLength: 0)
            guard let start = content.location(content.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length) else { continue }
            textLayoutManager.invalidateLayout(for: NSTextRange(location: start, end: end)!)
        }
    }

    private func apply(_ edit: Markdown.Edit) {
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: NSAttributedString(string: edit.replacement, attributes: MarkdownStyle.typing))
        setSelectedRange(edit.selection)
        didChangeText()
    }
}

private extension NSTextStorage {
    var nativeString: String {
        let source = string as NSString
        var units = [unichar](repeating: 0, count: source.length)
        source.getCharacters(&units, range: NSRange(location: 0, length: source.length))
        return String(decoding: units, as: UTF16.self)
    }
}

private extension NSRange {
    func offset(by distance: Int) -> NSRange {
        NSRange(location: location + distance, length: length)
    }
}
