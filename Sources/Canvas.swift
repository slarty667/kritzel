import AppKit
import UniformTypeIdentifiers

/// Which part of the crop frame the mouse grabbed.
enum CropGrip: Equatable {
    case none
    case move
    case corner(Int)   // 0 bottom left, 1 bottom right, 2 top right, 3 top left
    case edge(Int)     // 0 bottom, 1 right, 2 top, 3 left
    case newFrame
}

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

    var tool: ToolKind = .select {
        didSet {
            if tool == .crop {
                selectedIndex = nil
                cropRect = CGRect(origin: .zero, size: doc.size)
            } else if oldValue == .crop {
                cropRect = nil
            }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }
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
    /// The crop frame while the crop tool is active, in image coordinates.
    private(set) var cropRect: CGRect? {
        didSet { onCropChanged?(cropRect) }
    }
    /// Fires whenever the crop frame appears, moves or disappears.
    var onCropChanged: ((CGRect?) -> Void)?
    private var cropGrip: CropGrip = .none
    private var cropAnchor: CGRect = .zero

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
        let frame = toViewRect(c)

        // Dim the image outside the frame with four rectangles. The obvious
        // even-odd mask needs NSBezierPath.reversed, and reversing the empty path
        // that an empty rect produces throws an exception mid-draw.
        NSColor.black.withAlphaComponent(0.55).setFill()
        let inner = frame.intersection(imageViewRect)
        if inner.isNull || inner.isEmpty {
            NSBezierPath(rect: imageViewRect).fill()
        } else {
            let i = imageViewRect
            for band in [CGRect(x: i.minX, y: inner.maxY, width: i.width, height: i.maxY - inner.maxY),
                         CGRect(x: i.minX, y: i.minY, width: i.width, height: inner.minY - i.minY),
                         CGRect(x: i.minX, y: inner.minY, width: inner.minX - i.minX, height: inner.height),
                         CGRect(x: inner.maxX, y: inner.minY, width: i.maxX - inner.maxX, height: inner.height)]
                where band.width > 0 && band.height > 0 {
                NSBezierPath(rect: band).fill()
            }
        }

        guard frame.width >= 1, frame.height >= 1 else { return }

        // Every guide is drawn twice: a dark line underneath, a light one on top.
        // White alone disappears on white screenshots, which is most of them.
        let thirds = NSBezierPath()
        for i in 1...2 {
            let x = (frame.minX + frame.width * CGFloat(i) / 3).rounded() + 0.5
            let y = (frame.minY + frame.height * CGFloat(i) / 3).rounded() + 0.5
            thirds.move(to: CGPoint(x: x, y: frame.minY))
            thirds.line(to: CGPoint(x: x, y: frame.maxY))
            thirds.move(to: CGPoint(x: frame.minX, y: y))
            thirds.line(to: CGPoint(x: frame.maxX, y: y))
        }
        NSColor.black.withAlphaComponent(0.35).setStroke()
        thirds.lineWidth = 3
        thirds.stroke()
        NSColor.white.withAlphaComponent(0.75).setStroke()
        thirds.lineWidth = 1
        thirds.stroke()

        let outline = NSBezierPath(rect: frame)
        NSColor.black.withAlphaComponent(0.5).setStroke()
        outline.lineWidth = 3
        outline.stroke()
        NSColor.white.setStroke()
        outline.lineWidth = 1
        outline.stroke()

        drawCropGrips(frame)
    }

    /// Corner brackets and edge bars on the inside of the frame, with a dark
    /// halo so they stay visible on light image content.
    private func drawCropGrips(_ frame: CGRect) {
        let arm: CGFloat = min(24, frame.width / 3, frame.height / 3)
        let thickness: CGFloat = 3
        guard arm > 4 else { return }

        var bars: [CGRect] = [
            CGRect(x: frame.minX, y: frame.minY, width: arm, height: thickness),
            CGRect(x: frame.minX, y: frame.minY, width: thickness, height: arm),
            CGRect(x: frame.maxX - arm, y: frame.minY, width: arm, height: thickness),
            CGRect(x: frame.maxX - thickness, y: frame.minY, width: thickness, height: arm),
            CGRect(x: frame.maxX - arm, y: frame.maxY - thickness, width: arm, height: thickness),
            CGRect(x: frame.maxX - thickness, y: frame.maxY - arm, width: thickness, height: arm),
            CGRect(x: frame.minX, y: frame.maxY - thickness, width: arm, height: thickness),
            CGRect(x: frame.minX, y: frame.maxY - arm, width: thickness, height: arm)
        ]
        if frame.width > arm * 3 && frame.height > arm * 3 {
            bars.append(CGRect(x: frame.midX - arm / 2, y: frame.minY, width: arm, height: thickness))
            bars.append(CGRect(x: frame.midX - arm / 2, y: frame.maxY - thickness, width: arm, height: thickness))
            bars.append(CGRect(x: frame.minX, y: frame.midY - arm / 2, width: thickness, height: arm))
            bars.append(CGRect(x: frame.maxX - thickness, y: frame.midY - arm / 2, width: thickness, height: arm))
        }

        NSColor.black.withAlphaComponent(0.45).setFill()
        for b in bars { NSBezierPath(rect: b.insetBy(dx: -1, dy: -1)).fill() }
        NSColor.white.setFill()
        for b in bars { NSBezierPath(rect: b).fill() }
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
        case .crop: return   // handled per grip in mouseMoved
        default: cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        guard tool == .crop, dragMode == .none else { return }
        switch gripHit(at: convert(event.locationInWindow, from: nil)) {
        case .edge(let i): (i % 2 == 0 ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).set()
        case .move: NSCursor.openHand.set()
        default: NSCursor.crosshair.set()
        }
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
        clampCropToImage()
        needsDisplay = true
        onDocumentChanged?()
    }

    /// Undo, redo and resize change the image under an existing crop frame.
    /// Without this the frame can end up outside the image entirely.
    private func clampCropToImage() {
        guard tool == .crop else {
            if cropRect != nil { cropRect = nil }
            return
        }
        let full = CGRect(origin: .zero, size: doc.size)
        guard let c = cropRect else { cropRect = full; return }
        let clipped = c.intersection(full)
        if clipped.isNull || clipped.width < 8 || clipped.height < 8 {
            cropRect = full
        } else if clipped != c {
            cropRect = clipped
        }
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
            cropAnchor = cropRect ?? CGRect(origin: .zero, size: doc.size)
            cropGrip = gripHit(at: vp)
            if cropGrip == .newFrame { cropRect = CGRect(origin: p, size: .zero) }
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
            updateCrop(to: p, constrain: event.modifierFlags.contains(.shift))
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
            if tool == .crop { cancelCrop(nil); return }
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

    private func cornerPoint(_ r: CGRect, _ index: Int) -> CGPoint {
        switch index {
        case 0: return CGPoint(x: r.minX, y: r.minY)
        case 1: return CGPoint(x: r.maxX, y: r.minY)
        case 2: return CGPoint(x: r.maxX, y: r.maxY)
        default: return CGPoint(x: r.minX, y: r.maxY)
        }
    }

    /// Which grip sits under the given view point.
    private func gripHit(at vp: CGPoint) -> CropGrip {
        guard let c = cropRect else { return .newFrame }
        let f = toViewRect(c)
        let reach: CGFloat = 13
        let corners = [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY),
                       CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX, y: f.maxY)]
        for (i, p) in corners.enumerated() where hypot(p.x - vp.x, p.y - vp.y) <= reach {
            return .corner(i)
        }
        let edges = [CGPoint(x: f.midX, y: f.minY), CGPoint(x: f.maxX, y: f.midY),
                     CGPoint(x: f.midX, y: f.maxY), CGPoint(x: f.minX, y: f.midY)]
        for (i, p) in edges.enumerated() where hypot(p.x - vp.x, p.y - vp.y) <= reach {
            return .edge(i)
        }
        if f.contains(vp) { return .move }
        return .newFrame
    }

    private func updateCrop(to raw: CGPoint, constrain: Bool) {
        let full = CGRect(origin: .zero, size: doc.size)
        let p = CGPoint(x: min(max(raw.x, 0), full.width), y: min(max(raw.y, 0), full.height))
        var r: CGRect

        switch cropGrip {
        case .newFrame:
            r = rectBetween(dragOrigin, p)

        case .move:
            var moved = cropAnchor.offsetBy(dx: p.x - dragOrigin.x, dy: p.y - dragOrigin.y)
            moved.origin.x = min(max(moved.minX, 0), max(0, full.width - moved.width))
            moved.origin.y = min(max(moved.minY, 0), max(0, full.height - moved.height))
            r = moved

        case .corner(let i):
            let fixed = cornerPoint(cropAnchor, (i + 2) % 4)
            var target = p
            if constrain, cropAnchor.height > 1 {
                // Keep the aspect ratio the frame had when the drag started.
                let ratio = cropAnchor.width / cropAnchor.height
                let width = max(abs(target.x - fixed.x), abs(target.y - fixed.y) * ratio)
                let height = width / max(ratio, 0.0001)
                target = CGPoint(x: fixed.x + (target.x < fixed.x ? -width : width),
                                 y: fixed.y + (target.y < fixed.y ? -height : height))
            }
            r = rectBetween(fixed, target)

        case .edge(let i):
            switch i {
            case 0: r = rectBetween(CGPoint(x: cropAnchor.minX, y: p.y),
                                    CGPoint(x: cropAnchor.maxX, y: cropAnchor.maxY))
            case 1: r = rectBetween(CGPoint(x: cropAnchor.minX, y: cropAnchor.minY),
                                    CGPoint(x: p.x, y: cropAnchor.maxY))
            case 2: r = rectBetween(CGPoint(x: cropAnchor.minX, y: cropAnchor.minY),
                                    CGPoint(x: cropAnchor.maxX, y: p.y))
            default: r = rectBetween(CGPoint(x: p.x, y: cropAnchor.minY),
                                     CGPoint(x: cropAnchor.maxX, y: cropAnchor.maxY))
            }

        case .none:
            return
        }

        let clipped = r.intersection(full)
        cropRect = clipped.isNull ? CGRect(origin: p, size: .zero) : clipped
    }

    /// Sets the crop frame from typed pixel values, anchored at its top left.
    func setCropSize(width: CGFloat, height: CGFloat) {
        guard tool == .crop, let c = cropRect else { return }
        let w = min(max(8, width.rounded()), doc.size.width)
        let h = min(max(8, height.rounded()), doc.size.height)
        var r = CGRect(x: c.minX, y: c.maxY - h, width: w, height: h)
        if r.maxX > doc.size.width { r.origin.x = doc.size.width - w }
        if r.minY < 0 { r.origin.y = 0 }
        cropRect = r
        needsDisplay = true
    }

    @objc func cancelCrop(_ sender: Any?) {
        guard tool == .crop else { return }
        tool = .select
        onToolChanged?(.select)
        needsDisplay = true
    }

    @objc func resetCropFrame(_ sender: Any?) {
        guard tool == .crop else { return }
        cropRect = CGRect(origin: .zero, size: doc.size)
        needsDisplay = true
    }

    @objc func applyCrop(_ sender: Any?) {
        guard let c = cropRect, c.width > 4, c.height > 4 else { NSSound.beep(); return }
        guard c.integral != CGRect(origin: .zero, size: doc.size).integral else {
            cancelCrop(nil)
            return
        }
        pushUndo()
        doc.crop(to: c)
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

    /// Forces a crop frame that normal interaction would clamp, to test drawing.
    func debugSetCropRect(_ r: CGRect?) {
        cropRect = r
        needsDisplay = true
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
        case #selector(applyCrop(_:)), #selector(cancelCrop(_:)),
             #selector(resetCropFrame(_:)): return tool == .crop
        default: return true
        }
    }
}
