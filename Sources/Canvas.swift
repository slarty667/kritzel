import AppKit
import UniformTypeIdentifiers

enum DragMode: Equatable {
    case none
    case create
    case move
    case handle(Int)
    case crop
}

/// The drawing surface: renders the document and handles all direct manipulation.
final class CanvasView: NSView, NSTextFieldDelegate, NSMenuItemValidation {

    var doc: Document {
        didSet {
            undoStack.removeAll(); redoStack.removeAll()
            selectedIndex = nil; cropRect = nil
            needsDisplay = true
        }
    }

    var tool: ToolKind = .select { didSet { discardCrop(); window?.invalidateCursorRects(for: self); needsDisplay = true } }
    var color: NSColor = .systemRed { didSet { applyStyleToSelection() } }
    var lineWidth: CGFloat = 5 { didSet { applyStyleToSelection() } }
    var fontSize: CGFloat = 32 { didSet { applyStyleToSelection() } }

    var onDocumentChanged: (() -> Void)?
    var onToolChanged: ((ToolKind) -> Void)?

    private var selectedIndex: Int?
    private var draft: Annotation?
    private var dragMode: DragMode = .none
    private var dragOrigin: CGPoint = .zero
    private var lastPoint: CGPoint = .zero
    private var didMutate = false
    private var cropRect: CGRect?

    private var undoStack: [Document.Snapshot] = []
    private var redoStack: [Document.Snapshot] = []

    private var textField: NSTextField?
    private weak var editingText: TextAnnotation?

    // Image placement, recomputed on every draw.
    private var scale: CGFloat = 1
    private var imageOrigin: CGPoint = .zero

    init(doc: Document) {
        self.doc = doc
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        registerForDraggedTypes([.fileURL, .png, .tiff])
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { return true }
    override var isOpaque: Bool { return true }

    // MARK: - Coordinate mapping

    private func layoutImage() {
        let avail = bounds.insetBy(dx: 14, dy: 14)
        guard doc.size.width > 0, doc.size.height > 0, avail.width > 0, avail.height > 0 else { return }
        let fit = min(avail.width / doc.size.width, avail.height / doc.size.height)
        scale = max(0.02, min(fit, 2.0))
        imageOrigin = CGPoint(x: (bounds.width - doc.size.width * scale) / 2,
                              y: (bounds.height - doc.size.height * scale) / 2)
    }

    private func toImage(_ p: CGPoint) -> CGPoint {
        return CGPoint(x: (p.x - imageOrigin.x) / scale, y: (p.y - imageOrigin.y) / scale)
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        return CGPoint(x: p.x * scale + imageOrigin.x, y: p.y * scale + imageOrigin.y)
    }

    private func toViewRect(_ r: CGRect) -> CGRect {
        let a = toView(r.origin)
        return CGRect(x: a.x, y: a.y, width: r.width * scale, height: r.height * scale)
    }

    private var hitTolerance: CGFloat { return 7 / max(scale, 0.05) }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        layoutImage()

        let imageViewRect = CGRect(origin: imageOrigin,
                                   size: CGSize(width: doc.size.width * scale,
                                                height: doc.size.height * scale))

        NSColor.black.withAlphaComponent(0.18).setStroke()
        let border = NSBezierPath(rect: imageViewRect.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()

        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: imageOrigin.x, yBy: imageOrigin.y)
        t.scaleX(by: scale, yBy: scale)
        t.concat()
        NSGraphicsContext.current?.imageInterpolation = .high
        doc.image.draw(in: CGRect(origin: .zero, size: doc.size))
        for a in doc.annotations where a !== editingText {
            a.draw(doc: doc)
        }
        draft?.draw(doc: doc)
        NSGraphicsContext.restoreGraphicsState()

        drawSelectionHandles()
        drawCropOverlay(imageViewRect)
        drawHintIfNeeded(imageViewRect)
        if let fb = feedbackText {
            drawBadge(fb, at: CGPoint(x: 14, y: 14))
        }
    }

    private func drawSelectionHandles() {
        guard tool == .select, let i = selectedIndex, i < doc.annotations.count else { return }
        let a = doc.annotations[i]
        let box = toViewRect(a.boundingBox).insetBy(dx: -4, dy: -4)
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        let outline = NSBezierPath(rect: box)
        outline.lineWidth = 1
        outline.setLineDash([4, 3], count: 2, phase: 0)
        outline.stroke()

        for h in a.handles {
            let c = toView(h)
            let r = CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)
            NSColor.white.setFill()
            NSColor.controlAccentColor.setStroke()
            let p = NSBezierPath(rect: r)
            p.fill()
            p.lineWidth = 1.5
            p.stroke()
        }
    }

    private func drawCropOverlay(_ imageViewRect: CGRect) {
        guard tool == .crop, let c = cropRect else { return }
        let vr = toViewRect(c)
        NSColor.black.withAlphaComponent(0.45).setFill()
        let mask = NSBezierPath(rect: imageViewRect)
        mask.append(NSBezierPath(rect: vr).reversed)
        mask.windingRule = .evenOdd
        mask.fill()
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: vr)
        outline.lineWidth = 1.5
        outline.stroke()

        let label = "\(Int(c.width)) × \(Int(c.height))  ⏎ anwenden"
        drawBadge(label, at: CGPoint(x: vr.minX, y: vr.maxY + 6))
    }

    private func drawBadge(_ text: String, at p: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let box = CGRect(x: p.x, y: p.y, width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attrs)
    }

    private func drawHintIfNeeded(_ imageViewRect: CGRect) {
        guard doc.isBlank, doc.annotations.isEmpty, draft == nil else { return }
        let lines = ["Leere Fläche",
                     "⌘V  Bild aus der Zwischenablage einfügen",
                     "⌘⇧4  Bildschirmausschnitt aufnehmen",
                     "oder eine Bilddatei hierher ziehen"]
        let title: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.black.withAlphaComponent(0.35)]
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.black.withAlphaComponent(0.3)]
        var y = imageViewRect.midY + 40
        for (i, line) in lines.enumerated() {
            let attrs = i == 0 ? title : body
            let s = (line as NSString).size(withAttributes: attrs)
            (line as NSString).draw(at: CGPoint(x: imageViewRect.midX - s.width / 2, y: y), withAttributes: attrs)
            y -= s.height + (i == 0 ? 16 : 6)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        commitTextEditing()
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch tool {
        case .select: cursor = .arrow
        case .text: cursor = .iBeam
        default: cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - Undo

    private func pushUndo() {
        undoStack.append(doc.snapshot())
        redoStack.removeAll()
        if undoStack.count > 60 { undoStack.removeFirst() }
    }

    private func dropLastUndo() {
        if !undoStack.isEmpty { undoStack.removeLast() }
    }

    @objc func undoAction(_ sender: Any?) {
        commitTextEditing()
        guard let s = undoStack.popLast() else { NSSound.beep(); return }
        redoStack.append(doc.snapshot())
        doc.restore(s)
        selectedIndex = nil
        finishEdit()
    }

    @objc func redoAction(_ sender: Any?) {
        commitTextEditing()
        guard let s = redoStack.popLast() else { NSSound.beep(); return }
        undoStack.append(doc.snapshot())
        doc.restore(s)
        selectedIndex = nil
        finishEdit()
    }

    private func finishEdit() {
        needsDisplay = true
        onDocumentChanged?()
    }

    // MARK: - Selection helpers

    private func hitIndex(_ p: CGPoint) -> Int? {
        for i in stride(from: doc.annotations.count - 1, through: 0, by: -1) {
            if doc.annotations[i].contains(p, tolerance: hitTolerance) { return i }
        }
        return nil
    }

    private func applyStyleToSelection() {
        guard let i = selectedIndex, i < doc.annotations.count else { needsDisplay = true; return }
        let a = doc.annotations[i]
        a.color = color
        a.lineWidth = lineWidth
        if let t = a as? TextAnnotation { t.fontSize = fontSize }
        needsDisplay = true
    }

    var selectedAnnotation: Annotation? {
        guard let i = selectedIndex, i < doc.annotations.count else { return nil }
        return doc.annotations[i]
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitTextEditing()
        let vp = convert(event.locationInWindow, from: nil)
        let p = toImage(vp)
        lastPoint = p
        dragOrigin = p
        didMutate = false

        switch tool {
        case .select:
            if let i = selectedIndex, i < doc.annotations.count {
                for (hi, h) in doc.annotations[i].handles.enumerated() {
                    let hv = toView(h)
                    if hypot(hv.x - vp.x, hv.y - vp.y) <= 8 {
                        pushUndo()
                        dragMode = .handle(hi)
                        return
                    }
                }
            }
            if let idx = hitIndex(p) {
                selectedIndex = idx
                if event.clickCount >= 2, let t = doc.annotations[idx] as? TextAnnotation {
                    dragMode = .none
                    pushUndo()
                    beginTextEditing(t)
                    needsDisplay = true
                    return
                }
                pushUndo()
                dragMode = .move
                color = doc.annotations[idx].color
            } else {
                selectedIndex = nil
                dragMode = .none
            }
            needsDisplay = true

        case .crop:
            cropRect = CGRect(origin: p, size: .zero)
            dragMode = .crop
            needsDisplay = true

        case .text:
            pushUndo()
            let t = TextAnnotation()
            t.color = color
            t.fontSize = fontSize
            t.origin = CGPoint(x: p.x, y: p.y - fontSize * 0.75)
            doc.annotations.append(t)
            selectedIndex = doc.annotations.count - 1
            dragMode = .none
            beginTextEditing(t)
            needsDisplay = true

        default:
            pushUndo()
            draft = makeAnnotation(at: p)
            dragMode = .create
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = toImage(convert(event.locationInWindow, from: nil))
        switch dragMode {
        case .create:
            updateDraft(to: p, shift: event.modifierFlags.contains(.shift))
            didMutate = true
        case .move:
            if let a = selectedAnnotation {
                a.translate(by: CGPoint(x: p.x - lastPoint.x, y: p.y - lastPoint.y))
                didMutate = true
            }
        case .handle(let i):
            selectedAnnotation?.moveHandle(i, to: p)
            didMutate = true
        case .crop:
            cropRect = rectBetween(dragOrigin, p).intersection(CGRect(origin: .zero, size: doc.size))
            didMutate = true
        case .none:
            break
        }
        lastPoint = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch dragMode {
        case .create:
            if let d = draft {
                if d.isSubstantial {
                    doc.annotations.append(d)
                    selectedIndex = doc.annotations.count - 1
                } else {
                    dropLastUndo()
                }
            }
            draft = nil
        case .move, .handle:
            if !didMutate { dropLastUndo() }
        default:
            break
        }
        dragMode = .none
        finishEdit()
    }

    private func makeAnnotation(at p: CGPoint) -> Annotation? {
        switch tool {
        case .arrow:
            let a = ArrowAnnotation(); a.color = color; a.lineWidth = lineWidth
            a.start = p; a.end = p; return a
        case .rect:
            let a = RectAnnotation(); a.color = color; a.lineWidth = lineWidth
            a.p0 = p; a.p1 = p; return a
        case .ellipse:
            let a = EllipseAnnotation(); a.color = color; a.lineWidth = lineWidth
            a.p0 = p; a.p1 = p; return a
        case .pixelate:
            let a = PixelateAnnotation(); a.p0 = p; a.p1 = p; return a
        case .pen, .marker:
            let a = PenAnnotation(); a.color = color; a.lineWidth = lineWidth
            a.isMarker = (tool == .marker); a.points = [p]; return a
        default:
            return nil
        }
    }

    private func updateDraft(to p: CGPoint, shift: Bool) {
        guard let d = draft else { return }
        if let pen = d as? PenAnnotation {
            pen.points.append(p)
        } else if let arrow = d as? ArrowAnnotation {
            arrow.end = shift ? constrained(from: arrow.start, to: p) : p
        } else if let box = d as? BoxAnnotation {
            if shift {
                let side = max(abs(p.x - box.p0.x), abs(p.y - box.p0.y))
                box.p1 = CGPoint(x: box.p0.x + (p.x < box.p0.x ? -side : side),
                                 y: box.p0.y + (p.y < box.p0.y ? -side : side))
            } else {
                box.p1 = p
            }
        }
    }

    /// Snap a vector to the nearest 45 degree step.
    private func constrained(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        let step = (CGFloat.pi / 4)
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: a.x + cos(angle) * len, y: a.y + sin(angle) * len)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:
            deleteSelection(nil)
            return
        case 53:
            if cropRect != nil { discardCrop(); needsDisplay = true; return }
            if selectedIndex != nil { selectedIndex = nil; needsDisplay = true; return }
        case 36, 76:
            if cropRect != nil { applyCrop(nil); return }
        case 123, 124, 125, 126:
            if let a = selectedAnnotation {
                let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
                var d = CGPoint.zero
                if event.keyCode == 123 { d.x = -step }
                if event.keyCode == 124 { d.x = step }
                if event.keyCode == 125 { d.y = -step }
                if event.keyCode == 126 { d.y = step }
                pushUndo()
                a.translate(by: d)
                finishEdit()
                return
            }
        default:
            break
        }

        if let chars = event.charactersIgnoringModifiers, chars.count == 1,
           let digit = Int(chars), digit >= 1, digit <= ToolKind.allCases.count,
           !event.modifierFlags.contains(.command) {
            let newTool = ToolKind.allCases[digit - 1]
            tool = newTool
            onToolChanged?(newTool)
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Text editing

    private func beginTextEditing(_ t: TextAnnotation) {
        commitTextEditing()
        editingText = t
        let displaySize = max(11, t.fontSize * scale)
        let field = NSTextField(frame: .zero)
        field.stringValue = t.text
        field.font = NSFont(name: t.fontName, size: displaySize) ?? NSFont.systemFont(ofSize: displaySize)
        field.textColor = t.color
        field.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.92)
        field.drawsBackground = true
        field.isBordered = true
        field.bezelStyle = .squareBezel
        field.focusRingType = .none
        field.delegate = self
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true

        let anchor = toView(t.origin)
        let width = max(160, t.textSize.width * scale + 60)
        field.frame = NSRect(x: anchor.x - 5, y: anchor.y - 5,
                             width: min(width, max(120, bounds.width - anchor.x)),
                             height: displaySize + 12)
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    func commitTextEditing() {
        guard let field = textField, let t = editingText else { return }
        textField = nil
        editingText = nil
        t.text = field.stringValue
        field.removeFromSuperview()
        if !t.isSubstantial {
            if let i = doc.annotations.firstIndex(where: { $0 === t }) {
                doc.annotations.remove(at: i)
                if selectedIndex == i { selectedIndex = nil }
            }
            dropLastUndo()
        }
        finishEdit()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextEditing()
        window?.makeFirstResponder(self)
    }

    func controlTextDidChange(_ obj: Notification) {
        if let field = textField, let t = editingText {
            t.text = field.stringValue
        }
    }

    var isEditingText: Bool { return textField != nil }

    // MARK: - Crop

    private func discardCrop() {
        cropRect = nil
    }

    @objc func applyCrop(_ sender: Any?) {
        guard let c = cropRect, c.width > 4, c.height > 4 else { NSSound.beep(); return }
        pushUndo()
        doc.crop(to: c)
        cropRect = nil
        selectedIndex = nil
        tool = .select
        onToolChanged?(.select)
        finishEdit()
    }

    // MARK: - Editing commands

    @objc func deleteSelection(_ sender: Any?) {
        guard let i = selectedIndex, i < doc.annotations.count else { NSSound.beep(); return }
        pushUndo()
        doc.annotations.remove(at: i)
        selectedIndex = nil
        finishEdit()
    }

    @objc func bringToFront(_ sender: Any?) {
        guard let i = selectedIndex, i < doc.annotations.count else { return }
        pushUndo()
        let a = doc.annotations.remove(at: i)
        doc.annotations.append(a)
        selectedIndex = doc.annotations.count - 1
        finishEdit()
    }

    @objc func resizeImageDialog(_ sender: Any?) {
        commitTextEditing()
        let alert = NSAlert()
        alert.messageText = "Bildgröße ändern"
        alert.informativeText = "Aktuell \(Int(doc.size.width)) × \(Int(doc.size.height)) Pixel. Neue Breite in Pixeln:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = String(Int(doc.size.width))
        alert.accessoryView = input
        alert.addButton(withTitle: "Ändern")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let newWidth = Double(input.stringValue.trimmingCharacters(in: .whitespaces)), newWidth > 10 else {
            NSSound.beep(); return
        }
        let factor = CGFloat(newWidth) / doc.size.width
        pushUndo()
        doc.resize(factor: factor)
        finishEdit()
    }

    // MARK: - Export

    @objc func copyImageToPasteboard(_ sender: Any?) {
        commitTextEditing()
        guard let png = doc.pngData(), let img = doc.flattenedImage() else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
        pb.setData(png, forType: .png)
        flashFeedback("In die Zwischenablage kopiert")
    }

    @objc func saveImageAs(_ sender: Any?) {
        commitTextEditing()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFileName()
        panel.title = "Bild sichern"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            let isJPEG = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg"
            let data = isJPEG ? self.doc.jpegData() : self.doc.pngData()
            guard let payload = data else { NSSound.beep(); return }
            do {
                try payload.write(to: url)
                self.doc.sourceName = url.lastPathComponent
                self.onDocumentChanged?()
                self.flashFeedback("Gesichert: \(url.lastPathComponent)")
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    private func suggestedFileName() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd 'um' HH.mm.ss"
        return "Kritzel \(fmt.string(from: Date())).png"
    }

    private var feedbackText: String?

    private func flashFeedback(_ text: String) {
        feedbackText = text
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self = self else { return }
            if self.feedbackText == text { self.feedbackText = nil; self.needsDisplay = true }
        }
    }

    // MARK: - Drag and drop

    var onOpenImage: ((NSImage, String?) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first, let img = NSImage(contentsOf: url) {
            onOpenImage?(img, url.lastPathComponent)
            return true
        }
        if let imgs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = imgs.first {
            onOpenImage?(img, nil)
            return true
        }
        return false
    }

    // MARK: - Test hooks

    /// Maps an image point to view coordinates. Placement is normally computed
    /// while drawing, so tests have to trigger the layout explicitly.
    func debugViewPoint(for imagePoint: CGPoint) -> CGPoint {
        layoutImage()
        return toView(imagePoint)
    }

    /// Types into the inline text editor without a keyboard.
    func debugSetEditingText(_ value: String) {
        textField?.stringValue = value
        editingText?.text = value
    }

    // MARK: - Menu validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undoAction(_:)): return !undoStack.isEmpty
        case #selector(redoAction(_:)): return !redoStack.isEmpty
        case #selector(deleteSelection(_:)), #selector(bringToFront(_:)): return selectedIndex != nil
        case #selector(applyCrop(_:)): return cropRect != nil
        default: return true
        }
    }
}
