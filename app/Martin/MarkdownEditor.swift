import AppKit
import MartinKit
import SwiftUI

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let attendees: [Person]
    let acquaintances: [Person]

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NoteTextView {
        let textView = NoteTextView.make()
        textView.delegate = context.coordinator
        textView.attendees = attendees
        textView.acquaintances = acquaintances
        textView.load(text)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.storageChanged(_:)), name: NSTextStorage.didProcessEditingNotification, object: textView.textStorage)
        return textView
    }

    func updateNSView(_ textView: NoteTextView, context: Context) {
        context.coordinator.text = $text
        textView.attendees = attendees
        textView.acquaintances = acquaintances
        if textView.textStorage?.mutableString.isEqual(to: text) == false { textView.load(text) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: NoteTextView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? textView.frame.width, height: max(textView.intrinsicContentSize.height, proposal.height ?? 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func storageChanged(_ notification: Notification) {
            guard let storage = notification.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) else { return }
            guard !storage.mutableString.isEqual(to: text.wrappedValue) else { return }
            text.wrappedValue = storage.nativeString
        }

        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRanges old: [NSValue], toCharacterRanges new: [NSValue]) -> [NSValue] {
            guard let textView = textView as? NoteTextView else { return new }
            let from = old.first?.rangeValue.location ?? 0
            return new.map { NSValue(range: textView.skippingMentions($0.rangeValue, from: from)) }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let textView = textView as? NoteTextView else { return false }
            if textView.pickMention(for: selector) { return true }
            return switch selector {
            case #selector(NSResponder.insertNewline(_:)): textView.continueList()
            case #selector(NSResponder.insertTab(_:)): textView.indentList(outward: false)
            case #selector(NSResponder.insertBacktab(_:)): textView.indentList(outward: true)
            default: false
            }
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
    var attendees: [Person] = []
    var acquaintances: [Person] = []
    private lazy var picker = MentionPicker { [weak self] in self?.insertMention($0) }
    private var dismissedMention: Int?

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
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = NSSize(width: Theme.margin, height: 2)
        view.isContinuousSpellCheckingEnabled = true
        NotificationCenter.default.addObserver(view, selector: #selector(selectionChanged), name: NSTextView.didChangeSelectionNotification, object: view)
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
        selectionChanged()
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        guard let textLayoutManager else { return super.intrinsicContentSize }
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        return NSSize(width: NSView.noIntrinsicMetric, height: textLayoutManager.usageBoundsForTextContainer.height + textContainerInset.height * 2)
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func setFrameSize(_ size: NSSize) {
        let resized = size.width != frame.width
        super.setFrameSize(size)
        let inset = Theme.margin + max(0, (size.width - Theme.page) / 2)
        if textContainerInset.width != inset { textContainerInset.width = inset }
        if resized { invalidateIntrinsicContentSize() }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { reveal(selectedRange()) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { reveal(nil) }
        picker.hide()
        return resigned
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return picker.hide() }
        NotificationCenter.default.addObserver(self, selector: #selector(hideMentions), name: NSWindow.didResignKeyNotification, object: window)
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

    func pickMention(for selector: Selector) -> Bool {
        guard picker.isShown else { return false }
        switch selector {
        case #selector(moveUp(_:)): picker.move(by: -1)
        case #selector(moveDown(_:)): picker.move(by: 1)
        case #selector(insertNewline(_:)), #selector(insertTab(_:)): picker.selection.map(insertMention)
        case #selector(cancelOperation(_:)):
            dismissedMention = mentionQuery()?.location
            picker.hide()
        default: return false
        }
        return true
    }

    override func deleteBackward(_ sender: Any?) {
        let caret = selectedRange()
        guard caret.length == 0, let mention = mentions(near: caret.location).first(where: { NSMaxRange($0) == caret.location }) else { return super.deleteBackward(sender) }
        delete(mention)
    }

    override func deleteForward(_ sender: Any?) {
        let caret = selectedRange()
        guard caret.length == 0, let mention = mentions(near: caret.location).first(where: { $0.location == caret.location }) else { return super.deleteForward(sender) }
        delete(mention)
    }

    func skippingMentions(_ range: NSRange, from origin: Int) -> NSRange {
        let start = mention(around: range.location), end = mention(around: NSMaxRange(range))
        if range.length == 0, let start {
            return NSRange(location: range.location < origin ? start.location : NSMaxRange(start), length: 0)
        }
        let location = start?.location ?? range.location
        return NSRange(location: location, length: (end.map(NSMaxRange) ?? NSMaxRange(range)) - location)
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

    func indentList(outward: Bool) -> Bool {
        let selection = selectedRange()
        guard !hasMarkedText(), let (range, line) = line(at: selection.location) else { return false }
        switch line.block {
        case .list, .task: break
        default: return false
        }
        guard let edit = Markdown.indent(range, in: string, selection: selection, outward: outward) else { return false }
        apply(edit)
        return true
    }

    private func insertMention(_ person: Person) {
        guard let query = mentionQuery() else { return }
        let mention = person.mention + " "
        apply(Markdown.Edit(range: query, replacement: mention, selection: NSRange(location: query.location + (mention as NSString).length, length: 0)))
    }

    private func showMentions() {
        let query = window?.isKeyWindow == true && window?.firstResponder === self ? mentionQuery() : nil
        if query?.location != dismissedMention { dismissedMention = nil }
        guard let window, let query, dismissedMention == nil else { return picker.hide() }
        let typed = (string as NSString).substring(with: NSRange(location: query.location + 1, length: query.length - 1))
        let people = (attendees + acquaintances).suggestions(for: typed)
        guard !people.isEmpty else { return picker.hide() }
        picker.show(people, attending: Set(attendees.map(\.email)), matching: typed, under: firstRect(forCharacterRange: query, actualRange: nil), in: window)
    }

    @objc private func hideMentions() {
        picker.hide()
    }

    private func mentionQuery() -> NSRange? {
        let caret = selectedRange()
        guard caret.length == 0, !hasMarkedText() else { return nil }
        let (range, line) = style.line(at: caret.location, in: string as NSString)
        return line.mentionQuery(in: (string as NSString).substring(with: range), at: caret.location - range.location)?.offset(by: range.location)
    }

    private func mentions(near index: Int) -> [NSRange] {
        guard let (range, line) = line(at: index) else { return [] }
        return line.spans.compactMap { span in
            guard case .mention = span.role else { return nil }
            return span.range.offset(by: range.location)
        }
    }

    private func mention(around index: Int) -> NSRange? {
        mentions(near: index).first { $0.location < index && index < NSMaxRange($0) }
    }

    private func delete(_ mention: NSRange) {
        apply(Markdown.Edit(range: mention, replacement: "", selection: NSRange(location: mention.location, length: 0)))
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
        return rect(of: box).insetBy(dx: -3, dy: -3).contains(point) ? NSRange(location: box.location + 1, length: 1) : nil
    }

    private func character(under point: NSPoint) -> Int? {
        let index = characterIndexForInsertion(at: point)
        return [index, index - 1].first { NSLocationInRange($0, NSRange(location: 0, length: (string as NSString).length)) && rect(of: NSRange(location: $0, length: 1)).insetBy(dx: -1, dy: -4).contains(point) }
    }

    private func rect(of range: NSRange) -> NSRect {
        guard let window else { return .null }
        return convert(window.convertFromScreen(firstRect(forCharacterRange: range, actualRange: nil)), from: nil)
    }

    private func isProse(_ word: NSRange) -> Bool {
        guard NSMaxRange(word) <= (string as NSString).length else { return false }
        let (range, line) = style.line(at: word.location, in: string as NSString)
        guard line.block != .code, line.block != .fence else { return false }
        return !line.spans.contains { span in
            let literal = switch span.role {
            case .code, .url, .mention: true
            case .link(let destination): destination == span.range
            default: false
            }
            return literal && NSIntersectionRange(span.range.offset(by: range.location), word).length > 0
        }
    }

    @objc private func selectionChanged() {
        reveal(window?.firstResponder === self ? selectedRange() : nil)
        showMentions()
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
