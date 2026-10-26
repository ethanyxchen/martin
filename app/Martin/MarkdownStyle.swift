import AppKit
import MartinKit

@MainActor
final class MarkdownStyle: NSObject {
    nonisolated static let step: CGFloat = 18

    static let typing: [NSAttributedString.Key: Any] = {
        let look = Look(.text)
        return [.font: look.font, .foregroundColor: look.color, .paragraphStyle: paragraph(look, indent: 0, prefix: 0, content: 0), .baselineOffset: look.baselineOffset]
    }()

    private static let body = NSFont.systemFont(ofSize: 15)
    private static let ink = Theme.ink.ns
    private static let secondary = Theme.secondary.ns
    private static let tertiary = Theme.tertiary.ns
    private static let cobalt = Theme.cobalt.ns
    private static let collapsed = NSFont.systemFont(ofSize: 0.01)

    private var codeBlocks: [NSRange] = []
    private var references: [String: String] = [:]
    private var selection: NSRange?

    func select(_ selection: NSRange?, in text: NSString) -> Set<NSRange> {
        guard selection != self.selection else { return [] }
        let before = headings(revealedBy: self.selection, in: text)
        self.selection = selection
        return before.symmetricDifference(headings(revealedBy: selection, in: text))
    }

    func line(at location: Int, in text: NSString) -> (range: NSRange, line: Markdown.Line) {
        var start = 0, contentsEnd = 0
        text.getParagraphStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        let range = NSRange(location: start, length: contentsEnd - start)
        let contents = text.substring(with: range)
        let line = Markdown.Line(contents, references: references)
        guard let block = codeBlocks.first(where: { NSLocationInRange(start, $0) }), start != block.location else { return (range, line) }
        let closing = line.block == .fence && NSMaxRange(text.paragraphRange(for: range)) == NSMaxRange(block)
        return (range, closing ? line : Markdown.Line(contents, code: true))
    }

    private func headings(revealedBy selection: NSRange?, in text: NSString) -> Set<NSRange> {
        guard let selection else { return [] }
        var headings: Set<NSRange> = []
        text.enumerateSubstrings(in: Self.paragraphs(of: selection, in: text), options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
            guard Markdown.mayBeHeading(range, in: text) else { return }
            let line = self.line(at: range.location, in: text).line
            if line.block == .heading { headings.insert(enclosing) }
        }
        return headings
    }

    private static func paragraphs(of selection: NSRange, in text: NSString) -> NSRange {
        let location = min(selection.location, text.length)
        return text.paragraphRange(for: NSRange(location: location, length: min(selection.length, text.length - location)))
    }

    private func edge(of line: Markdown.Line, at location: Int) -> CodeEdge? {
        switch line.block {
        case .code: .middle
        case .fence: codeBlocks.contains { $0.location == location } ? .top : .bottom
        default: nil
        }
    }

    private func style(_ text: NSMutableAttributedString, as line: Markdown.Line, length: Int, edge: CodeEdge?, revealed: Bool) {
        let look = Look(line.block)
        let all = NSRange(location: 0, length: text.length)
        text.addAttributes([.font: look.font, .foregroundColor: look.color, .baselineOffset: look.baselineOffset], range: all)
        if case .task(done: true) = line.block {
            text.addAttributes([.foregroundColor: Self.tertiary, .strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: Self.tertiary], range: NSRange(location: line.prefix, length: length - line.prefix))
        }
        if let edge { text.addAttribute(.codeBlock, value: edge, range: all) }
        for span in line.spans {
            switch span.role {
            case .marker:
                text.addAttribute(.foregroundColor, value: Self.tertiary, range: span.range)
                text.removeAttribute(.strikethroughStyle, range: span.range)
                if case .heading = line.block, span.range.location < line.prefix {
                    text.addAttribute(.font, value: Self.body, range: span.range)
                }
            case .bullet:
                let end = line.spans.first { $0.role == .checkbox }?.range.location ?? line.prefix
                text.addAttributes([.font: Self.collapsed, .foregroundColor: NSColor.clear], range: NSRange(location: span.range.location, length: end - span.range.location))
                if line.block == .list { text.addAttribute(.bullet, value: line.depth, range: all) }
            case .checkbox:
                text.addAttribute(.foregroundColor, value: line.block == .task(done: true) ? Self.cobalt : Self.tertiary, range: span.range)
                text.removeAttribute(.strikethroughStyle, range: span.range)
            case .strong:
                Self.add(.bold, to: text, in: span.range)
            case .emphasis:
                Self.add(.italic, to: text, in: span.range)
            case .strikethrough:
                text.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: Self.secondary], range: span.range)
            case .code:
                text.addAttribute(.font, value: Self.mono(look.font.pointSize * 0.9), range: span.range)
            case .link, .reference:
                text.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Self.tertiary], range: span.range)
            case .url:
                text.addAttribute(.foregroundColor, value: Self.tertiary, range: span.range)
            }
        }
        if line.block == .heading, !revealed {
            text.addAttributes([.font: Self.collapsed, .foregroundColor: NSColor.clear], range: NSRange(location: 0, length: line.prefix))
        }
        let nested = switch line.block {
        case .list, .task: true
        default: false
        }
        if nested { text.addAttribute(.font, value: Self.collapsed, range: NSRange(location: 0, length: line.spans[0].range.location)) }
        let indent = nested ? CGFloat(line.depth) * Self.step : 0
        let prefix = text.attributedSubstring(from: NSRange(location: 0, length: line.prefix)).size().width
        let content = text.attribute(.bullet, at: 0, effectiveRange: nil) == nil ? prefix : Self.step
        text.addAttribute(.paragraphStyle, value: Self.paragraph(look, indent: indent, prefix: prefix, content: content), range: all)
    }

    private static func paragraph(_ look: Look, indent: CGFloat, prefix: CGFloat, content: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = Theme.gutter + indent + content - prefix
        style.headIndent = Theme.gutter + indent + content
        if indent > 0 {
            style.tabStops = []
            style.defaultTabInterval = 0.01
        }
        style.minimumLineHeight = look.lineHeight
        style.maximumLineHeight = look.lineHeight
        return style
    }

    private static func add(_ trait: NSFontDescriptor.SymbolicTraits, to text: NSMutableAttributedString, in range: NSRange) {
        text.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let font = value as? NSFont else { return }
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
            text.addAttribute(.font, value: NSFont(descriptor: descriptor, size: font.pointSize) ?? font, range: run)
        }
    }

    private static func mono(_ size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static let serif = NSFont(descriptor: body.fontDescriptor.withDesign(.serif)!, size: 15)!
    private static let code = mono(13)
    private static let small = body.withSize(12.5)
    private static let heading = NSFont(descriptor: NSFont.systemFont(ofSize: 17, weight: .semibold).fontDescriptor.withDesign(.serif)!, size: 17)!

    @MainActor
    private struct Look {
        let font: NSFont
        let color: NSColor
        let lineHeight: CGFloat

        var baselineOffset: CGFloat {
            (lineHeight - font.ascender + font.descender) / 2
        }

        var midline: CGFloat {
            lineHeight + font.descender - baselineOffset - font.xHeight / 2
        }

        init(_ block: Markdown.Line.Block) {
            switch block {
            case .heading: self.init(font: heading, lineHeight: 26)
            case .quote: self.init(font: serif, color: secondary)
            case .fence: self.init(font: code, color: tertiary, lineHeight: 22)
            case .code: self.init(font: code, lineHeight: 21)
            case .blank: self.init(font: body)
            case .rule: self.init(font: body, color: tertiary)
            case .definition: self.init(font: small, color: tertiary, lineHeight: 20)
            case .text, .list, .task: self.init(font: body)
            }
        }

        private init(font: NSFont, color: NSColor = MarkdownStyle.ink, lineHeight: CGFloat = 24) {
            self.font = font
            self.color = color
            self.lineHeight = lineHeight
        }
    }
}

extension MarkdownStyle: @preconcurrency NSTextContentStorageDelegate {
    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let source = textContentStorage.textStorage else { return nil }
        let text = NSMutableAttributedString(attributedString: source.attributedSubstring(from: range))
        let (contents, line) = line(at: range.location, in: source.string as NSString)
        let revealed = selection.map { NSIntersectionRange(Self.paragraphs(of: $0, in: source.string as NSString), range).length > 0 } ?? false
        style(text, as: line, length: contents.length, edge: edge(of: line, at: range.location), revealed: revealed)
        return NSTextParagraph(attributedString: text)
    }
}

extension MarkdownStyle: @preconcurrency NSTextStorageDelegate {
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let end = textStorage.length - delta
        let before = codeBlocks.map { $0.moved(across: range, by: delta, growing: NSMaxRange($0) == end) }
        let labels = Set(references.keys)
        selection = selection?.moved(across: range, by: delta)
        codeBlocks = Markdown.codeBlocks(in: textStorage.string)
        references = Markdown.references(in: textStorage.string)
        let document = NSRange(location: 0, length: textStorage.length)
        let changed = Set(before).symmetricDifference(codeBlocks)
        if labels != Set(references.keys) {
            textStorage.edited(.editedAttributes, range: document, changeInLength: 0)
        } else if let first = changed.first {
            textStorage.edited(.editedAttributes, range: NSIntersectionRange(changed.reduce(first, NSUnionRange), document), changeInLength: 0)
        }
    }
}

extension MarkdownStyle: @preconcurrency NSTextLayoutManagerDelegate {
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        let range = textElement.elementRange
        guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 else {
            return NSTextLayoutFragment(textElement: textElement, range: range)
        }
        let attributes = paragraph.attributedString.attributes(at: 0, effectiveRange: nil)
        if let edge = attributes[.codeBlock] as? CodeEdge {
            return CodeFragment(textElement: textElement, range: range, edge: edge)
        }
        if let depth = attributes[.bullet] as? Int {
            return BulletFragment(textElement: textElement, range: range, depth: depth, midline: Look(.list).midline)
        }
        return NSTextLayoutFragment(textElement: textElement, range: range)
    }
}

private enum CodeEdge {
    case top, middle, bottom
}

private extension NSAttributedString.Key {
    static let codeBlock = NSAttributedString.Key("martin.codeBlock")
    static let bullet = NSAttributedString.Key("martin.bullet")
}

private final class BulletFragment: NSTextLayoutFragment {
    private static let size: CGFloat = 5.5
    private let depth: Int
    private let midline: CGFloat

    init(textElement: NSTextElement, range: NSTextRange?, depth: Int, midline: CGFloat) {
        self.depth = depth
        self.midline = midline
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(mark)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        let mark = mark.offsetBy(dx: point.x, dy: point.y)
        let color = Theme.tertiary.ns.cgColor
        context.saveGState()
        switch depth % 3 {
        case 0:
            context.setFillColor(color)
            context.fillEllipse(in: mark)
        case 1:
            context.setStrokeColor(color)
            context.setLineWidth(1.3)
            context.strokeEllipse(in: mark.insetBy(dx: 0.65, dy: 0.65))
        default:
            context.setFillColor(color)
            context.fill(mark.insetBy(dx: 0.75, dy: 0.75))
        }
        context.restoreGState()
    }

    private var mark: CGRect {
        let x = Theme.gutter + CGFloat(depth) * MarkdownStyle.step - layoutFragmentFrame.minX
        return CGRect(x: x, y: midline - Self.size / 2, width: Self.size, height: Self.size)
    }
}

private final class CodeFragment: NSTextLayoutFragment {
    private static let radius: CGFloat = 6
    private static let padding: CGFloat = 12
    private let edge: CodeEdge

    init(textElement: NSTextElement, range: NSTextRange?, edge: CodeEdge) {
        self.edge = edge
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(panel)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let panel = panel.offsetBy(dx: point.x, dy: point.y)
        let rounded = CGRect(
            x: panel.minX,
            y: edge == .top ? panel.minY : panel.minY - Self.radius,
            width: panel.width,
            height: panel.height + (edge == .middle ? 2 : 1) * Self.radius
        )
        context.saveGState()
        context.clip(to: panel)
        context.addPath(CGPath(roundedRect: rounded, cornerWidth: Self.radius, cornerHeight: Self.radius, transform: nil))
        context.setFillColor(Theme.ink.ns.cgColor.copy(alpha: 0.037)!)
        context.fillPath()
        context.restoreGState()
        super.draw(at: point, in: context)
    }

    private var panel: CGRect {
        let width = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
        let minX = Theme.gutter - Self.padding, maxX = width + Self.padding
        return CGRect(x: minX - layoutFragmentFrame.minX, y: 0, width: maxX - minX, height: layoutFragmentFrame.height)
    }
}
