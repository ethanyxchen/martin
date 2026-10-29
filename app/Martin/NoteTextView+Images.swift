import AppKit
import MartinKit

struct ImageDrag {
    let paragraph: NSRange
    let contents: NSRange
    let image: NoteImage
    let origin: NSPoint
    let startWidth: CGFloat
    let natural: CGFloat
    let growsLeftward: Bool
    var width: CGFloat
}

struct ImageHit {
    let line: NoteTextView.ImageLine
    let frame: CGRect
}

struct ImageItem {
    let data: Data
    let fileExtension: String
}

extension NoteTextView {
    typealias ImageLine = (paragraph: NSRange, contents: NSRange, image: NoteImage)

    private var text: NSString { string as NSString }
    private var containerWidth: CGFloat { textContainer?.size.width ?? 0 }

    var selectedImage: ImageLine? {
        let selection = selectedRange()
        guard selection.length > 0, let found = style.imageLine(at: selection.location, in: text), found.contents == selection else { return nil }
        return found
    }

    func refreshImages() {
        guard text.range(of: "![").location != NSNotFound else { return }
        var paragraphs: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
            if self.style.imageLine(at: range.location, in: self.text) != nil { paragraphs.append(enclosing) }
        }
        refresh(paragraphs)
    }

    func skippingImages(_ range: NSRange) -> NSRange {
        guard let found = style.imageLine(at: range.location, in: text),
              range.location >= found.paragraph.location, NSMaxRange(range) <= NSMaxRange(found.contents) else { return range }
        return found.contents
    }

    func moveOffImage(for selector: Selector) -> Bool {
        guard let found = selectedImage else { return false }
        switch selector {
        case #selector(moveLeft(_:)), #selector(moveUp(_:)):
            if found.paragraph.location > 0 {
                setSelectedRange(NSRange(location: found.paragraph.location - 1, length: 0))
            } else if isEditable {
                apply(Markdown.Edit(range: NSRange(location: 0, length: 0), replacement: "\n", selection: NSRange(location: 0, length: 0)))
            }
        case #selector(moveRight(_:)), #selector(moveDown(_:)):
            let next = NSMaxRange(found.paragraph)
            if next > NSMaxRange(found.contents) { setSelectedRange(NSRange(location: next, length: 0)) }
        case #selector(insertNewline(_:)):
            guard isEditable else { return false }
            moveBelow(found)
        default:
            return false
        }
        return true
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if isEditable, replacementRange.location == NSNotFound, let found = selectedImage { moveBelow(found) }
        super.insertText(string, replacementRange: replacementRange)
    }

    private func moveBelow(_ found: ImageLine) {
        let next = NSMaxRange(found.paragraph)
        if next == NSMaxRange(found.contents) || style.imageLine(at: next, in: text) != nil {
            apply(Markdown.Edit(range: NSRange(location: next, length: 0), replacement: "\n", selection: NSRange(location: next, length: 0)))
            if next == NSMaxRange(found.contents) { setSelectedRange(NSRange(location: next + 1, length: 0)) }
        } else {
            setSelectedRange(NSRange(location: next, length: 0))
        }
    }

    @discardableResult
    func removeSelectedImage() -> Bool {
        guard isEditable, let found = selectedImage else { return false }
        apply(Markdown.Edit(range: found.paragraph, replacement: "", selection: NSRange(location: found.paragraph.location, length: 0)))
        return true
    }

    func resizeSelectedImage(to width: Int?) {
        guard isEditable, let found = selectedImage else { return }
        let replacement = found.image.resized(to: width).markdown
        apply(Markdown.Edit(range: found.contents, replacement: replacement, selection: NSRange(location: found.contents.location, length: (replacement as NSString).length)))
    }

    func fitSelectedImage() {
        resizeSelectedImage(to: Int(style.available(width: containerWidth)))
    }

    // MARK: Geometry

    private func location(of fragment: NSTextLayoutFragment) -> Int? {
        guard let content = textContentStorage else { return nil }
        return content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
    }

    private func pictureFragment(at location: Int) -> PictureFragment? {
        guard let textLayoutManager, let content = textContentStorage,
              let start = content.location(content.documentRange.location, offsetBy: location) else { return nil }
        textLayoutManager.ensureLayout(for: NSTextRange(location: start, end: content.location(start, offsetBy: 1)) ?? content.documentRange)
        return textLayoutManager.textLayoutFragment(for: start) as? PictureFragment
    }

    private func pictureFrame(at location: Int) -> CGRect? {
        pictureFragment(at: location).map { frame(of: $0) }
    }

    private func frame(of fragment: PictureFragment) -> CGRect {
        let origin = textContainerOrigin
        return fragment.picture.bounds.offsetBy(dx: fragment.layoutFragmentFrame.minX + origin.x, dy: fragment.layoutFragmentFrame.minY + origin.y)
    }

    private func imageUnder(_ point: NSPoint) -> ImageHit? {
        guard let textLayoutManager else { return nil }
        let origin = textContainerOrigin
        guard let fragment = textLayoutManager.textLayoutFragment(for: CGPoint(x: point.x - origin.x, y: point.y - origin.y)) as? PictureFragment,
              let start = location(of: fragment), let line = style.imageLine(at: start, in: text) else { return nil }
        let picture = frame(of: fragment)
        return picture.insetBy(dx: -6, dy: -6).contains(point) ? ImageHit(line: line, frame: picture) : nil
    }

    private func handle(at point: NSPoint, of frame: CGRect) -> Int? {
        Picture.handles(of: frame).firstIndex { $0.insetBy(dx: -4, dy: -4).contains(point) }
    }

    // MARK: Mouse

    func selectImage(under point: NSPoint) -> Bool {
        guard let hit = imageUnder(point), hit.frame.contains(point) else { return false }
        window?.makeFirstResponder(self)
        setSelectedRange(hit.line.contents)
        return true
    }

    func beginResizing(at point: NSPoint) -> Bool {
        guard let found = selectedImage, let frame = pictureFrame(at: found.paragraph.location), let corner = handle(at: point, of: frame),
              let picture = style.picture(found.image) else { return false }
        imageDrag = ImageDrag(paragraph: found.paragraph, contents: found.contents, image: found.image, origin: point, startWidth: frame.width, natural: picture.size.width, growsLeftward: corner % 2 == 0, width: frame.width)
        imageBar.isHidden = true
        return true
    }

    func continueResizing(to point: NSPoint, precisely: Bool) {
        guard var drag = imageDrag else { return }
        let available = style.available(width: containerWidth)
        var width = drag.startWidth + (drag.growsLeftward ? drag.origin.x - point.x : point.x - drag.origin.x)
        width = min(max(width, MarkdownStyle.smallest), available)
        if !precisely {
            for target in [available, drag.natural] where abs(width - target) < 8 { width = min(target, available) }
        }
        drag.width = width
        imageDrag = drag
        style.resizing = (drag.paragraph.location, width)
        refresh([drag.paragraph])
        if let frame = pictureFrame(at: drag.paragraph.location) {
            if sizeBadge.superview == nil { addSubview(sizeBadge) }
            sizeBadge.show(width: width)
            sizeBadge.frame.origin = NSPoint(x: frame.maxX - sizeBadge.frame.width, y: frame.minY - sizeBadge.frame.height - 6)
        }
    }

    func finishResizing() {
        guard let drag = imageDrag else { return }
        imageDrag = nil
        style.resizing = nil
        sizeBadge.removeFromSuperview()
        let width = abs(drag.width - drag.natural) < 1 ? nil : Int(drag.width.rounded())
        if width == drag.image.width || (width == nil && drag.image.width == Int(drag.natural.rounded())) {
            refresh([drag.paragraph])
            layoutImageBar()
        } else {
            resizeSelectedImage(to: width)
        }
    }

    func imageCursor(at point: NSPoint) -> NSCursor? {
        if imageDrag != nil { return .frameResize(position: .bottomRight, directions: .all) }
        guard isEditable else { return nil }
        if let found = selectedImage, let frame = pictureFrame(at: found.paragraph.location), let corner = handle(at: point, of: frame) {
            let positions: [NSCursor.FrameResizePosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
            return .frameResize(position: positions[corner], directions: .all)
        }
        return imageUnder(point)?.frame.contains(point) == true ? .arrow : nil
    }

    func layoutImageBar() {
        guard isEditable, imageDrag == nil, window?.firstResponder === self, let found = selectedImage, let frame = pictureFrame(at: found.paragraph.location) else {
            imageBar.isHidden = true
            return
        }
        if imageBar.superview == nil { addSubview(imageBar) }
        imageBar.isHidden = false
        let x = min(max(frame.midX - imageBar.frame.width / 2, 4), max(4, bounds.width - imageBar.frame.width - 4))
        let roomy = frame.height >= imageBar.frame.height * 3 && frame.width >= imageBar.frame.width + 24
        imageBar.frame.origin = NSPoint(x: x, y: roomy ? frame.maxY - imageBar.frame.height - 10 : frame.maxY + 8)
    }

    // MARK: Adding images

    func hasImages(_ pasteboard: NSPasteboard) -> Bool {
        if let files = fileImages(pasteboard) { return !files.isEmpty }
        return pasteboard.data(forType: .png) != nil || pasteboard.data(forType: .tiff) != nil && pasteboard.string(forType: .string) == nil
    }

    private func fileImages(_ pasteboard: NSPasteboard) -> [URL]? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return nil }
        let images = urls.filter { NoteImages.extensions.contains($0.pathExtension.lowercased()) }
        return images.count == urls.count ? images : []
    }

    private func imageItems(_ pasteboard: NSPasteboard) -> [ImageItem] {
        if let files = fileImages(pasteboard) {
            return files.compactMap { url in (try? Data(contentsOf: url)).map { ImageItem(data: $0, fileExtension: url.pathExtension) } }
        }
        if let png = pasteboard.data(forType: .png) { return [ImageItem(data: png, fileExtension: "png")] }
        if let tiff = pasteboard.data(forType: .tiff), let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return [ImageItem(data: png, fileExtension: "png")]
        }
        return []
    }

    @discardableResult
    func insertImages(_ items: [ImageItem], at location: Int) -> Bool {
        guard isEditable, let images, !items.isEmpty, let paths = try? items.map({ try images.add($0.data, fileExtension: $0.fileExtension) }) else {
            NSSound.beep()
            return false
        }
        var insertion = location > 0 && text.character(at: location - 1) != 0x0A ? "\n" : ""
        insertion += paths.map { NoteImage(path: $0).markdown + "\n" }.joined()
        window?.makeFirstResponder(self)
        apply(Markdown.Edit(range: NSRange(location: location, length: 0), replacement: insertion, selection: NSRange(location: location + (insertion as NSString).length, length: 0)))
        return true
    }

    override func paste(_ sender: Any?) {
        guard isEditable, hasImages(.general) else { return super.paste(sender) }
        let caret = selectedRange()
        let paragraph = text.paragraphRange(for: NSRange(location: min(caret.location, text.length), length: 0))
        insertImages(imageItems(.general), at: caret.location == paragraph.location ? paragraph.location : NSMaxRange(paragraph))
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), isEditable, hasImages(.general) { return true }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: Dropping

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isEditable, hasImages(sender.draggingPasteboard) else { return super.draggingEntered(sender) }
        showDropTarget(at: convert(sender.draggingLocation, from: nil))
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isEditable, hasImages(sender.draggingPasteboard) else { return super.draggingUpdated(sender) }
        showDropTarget(at: convert(sender.draggingLocation, from: nil))
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        hideDropTarget()
        super.draggingExited(sender)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        hideDropTarget()
        super.draggingEnded(sender)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isEditable && hasImages(sender.draggingPasteboard) ? true : super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isEditable, hasImages(sender.draggingPasteboard) else { return super.performDragOperation(sender) }
        let target = dropTarget(at: convert(sender.draggingLocation, from: nil))
        hideDropTarget()
        return insertImages(imageItems(sender.draggingPasteboard), at: target.location)
    }

    func dropTarget(at point: NSPoint) -> (location: Int, y: CGFloat) {
        let origin = textContainerOrigin
        guard let textLayoutManager, let content = textContentStorage else { return (text.length, bounds.height) }
        let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard let fragment = textLayoutManager.textLayoutFragment(for: local), let start = location(of: fragment) else {
            return local.y < 0 ? (0, origin.y) : (text.length, textLayoutManager.usageBoundsForTextContainer.maxY + origin.y)
        }
        let frame = fragment.layoutFragmentFrame
        let length = content.offset(from: fragment.rangeInElement.location, to: fragment.rangeInElement.endLocation)
        return local.y < frame.midY ? (start, frame.minY + origin.y) : (start + length, frame.maxY + origin.y)
    }

    private func showDropTarget(at point: NSPoint) {
        let target = dropTarget(at: point)
        if dropGuide.superview == nil { addSubview(dropGuide) }
        let x = Theme.gutter + textContainerOrigin.x - 3
        dropGuide.frame = NSRect(x: x, y: target.y - 4, width: max(0, containerWidth - Theme.gutter + 3), height: 8)
    }

    func hideDropTarget() {
        dropGuide.removeFromSuperview()
    }
}
