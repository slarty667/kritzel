import AppKit

// MARK: - Tools

enum ToolKind: Int, CaseIterable {
    case select, arrow, rect, ellipse, text, pen, marker, pixelate, crop

    var label: String {
        switch self {
        case .select:   return "Auswahl"
        case .arrow:    return "Pfeil"
        case .rect:     return "Rechteck"
        case .ellipse:  return "Ellipse"
        case .text:     return "Text"
        case .pen:      return "Stift"
        case .marker:   return "Marker"
        case .pixelate: return "Verpixeln"
        case .crop:     return "Zuschneiden"
        }
    }

    var symbolName: String {
        switch self {
        case .select:   return "cursorarrow"
        case .arrow:    return "arrow.up.right"
        case .rect:     return "rectangle"
        case .ellipse:  return "circle"
        case .text:     return "textformat"
        case .pen:      return "pencil"
        case .marker:   return "highlighter"
        case .pixelate: return "square.grid.3x3.fill"
        case .crop:     return "crop"
        }
    }
}

// MARK: - Geometry helpers

func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let len2 = dx * dx + dy * dy
    if len2 < 0.0001 { return hypot(p.x - a.x, p.y - a.y) }
    var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
    t = max(0, min(1, t))
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}

func rectBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                  width: abs(b.x - a.x), height: abs(b.y - a.y))
}

// MARK: - Annotation base class

/// One editable object drawn on top of the image.
/// All coordinates live in image space: origin bottom left, 1 unit == 1 pixel.
class Annotation {
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 5

    required init() {}

    func draw(doc: Document) {}
    func contains(_ p: CGPoint, tolerance: CGFloat) -> Bool { return false }
    func translate(by d: CGPoint) {}
    func scale(by f: CGFloat) { lineWidth *= f }
    var handles: [CGPoint] { return [] }
    func moveHandle(_ index: Int, to p: CGPoint) {}
    var boundingBox: CGRect { return .zero }
    /// True once the object is large enough to be worth keeping.
    var isSubstantial: Bool { return true }

    func clone() -> Annotation {
        let c = type(of: self).init()
        c.copyState(from: self)
        return c
    }

    /// Subclasses override and call super to copy their own state.
    func copyState(from other: Annotation) {
        color = other.color
        lineWidth = other.lineWidth
    }
}

// MARK: - Arrow

final class ArrowAnnotation: Annotation {
    var start: CGPoint = .zero
    var end: CGPoint = .zero

    override func draw(doc: Document) {
        let w = max(1.5, lineWidth)
        let len = hypot(end.x - start.x, end.y - start.y)
        guard len > 1 else { return }
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLen = max(w * 4.0, 12)
        let headHalf = max(w * 2.2, 7)

        color.setStroke()
        color.setFill()

        let shaftEnd = CGPoint(x: end.x - cos(angle) * headLen * 0.8,
                               y: end.y - sin(angle) * headLen * 0.8)
        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.line(to: shaftEnd)
        shaft.lineWidth = w
        shaft.lineCapStyle = .round
        shaft.stroke()

        let base = CGPoint(x: end.x - cos(angle) * headLen, y: end.y - sin(angle) * headLen)
        let nx = -sin(angle), ny = cos(angle)
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: CGPoint(x: base.x + nx * headHalf, y: base.y + ny * headHalf))
        head.line(to: CGPoint(x: base.x - nx * headHalf, y: base.y - ny * headHalf))
        head.close()
        head.fill()
    }

    override func contains(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        return distance(p, toSegment: start, end) <= max(tolerance, lineWidth)
    }

    override func translate(by d: CGPoint) {
        start = CGPoint(x: start.x + d.x, y: start.y + d.y)
        end = CGPoint(x: end.x + d.x, y: end.y + d.y)
    }

    override func scale(by f: CGFloat) {
        super.scale(by: f)
        start = CGPoint(x: start.x * f, y: start.y * f)
        end = CGPoint(x: end.x * f, y: end.y * f)
    }

    override var handles: [CGPoint] { return [start, end] }

    override func moveHandle(_ index: Int, to p: CGPoint) {
        if index == 0 { start = p } else { end = p }
    }

    override var boundingBox: CGRect { return rectBetween(start, end) }

    override var isSubstantial: Bool { return hypot(end.x - start.x, end.y - start.y) > 6 }

    override func copyState(from other: Annotation) {
        super.copyState(from: other)
        if let o = other as? ArrowAnnotation { start = o.start; end = o.end }
    }
}

// MARK: - Rectangle / ellipse / pixelate share a corner-dragged rect

class BoxAnnotation: Annotation {
    var p0: CGPoint = .zero
    var p1: CGPoint = .zero

    var rect: CGRect { return rectBetween(p0, p1) }

    override func translate(by d: CGPoint) {
        p0 = CGPoint(x: p0.x + d.x, y: p0.y + d.y)
        p1 = CGPoint(x: p1.x + d.x, y: p1.y + d.y)
    }

    override func scale(by f: CGFloat) {
        super.scale(by: f)
        p0 = CGPoint(x: p0.x * f, y: p0.y * f)
        p1 = CGPoint(x: p1.x * f, y: p1.y * f)
    }

    override var handles: [CGPoint] {
        let r = rect
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    override func moveHandle(_ index: Int, to p: CGPoint) {
        var corners = handles
        guard index >= 0 && index < corners.count else { return }
        corners[index] = p
        p0 = corners[(index + 2) % 4]
        p1 = p
    }

    override var boundingBox: CGRect { return rect }

    override var isSubstantial: Bool { return rect.width > 5 && rect.height > 5 }

    override func copyState(from other: Annotation) {
        super.copyState(from: other)
        if let o = other as? BoxAnnotation { p0 = o.p0; p1 = o.p1 }
    }

    /// Distance based hit test on the outline of a rect.
    func nearOutline(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        let r = rect.insetBy(dx: -tolerance, dy: -tolerance)
        let inner = rect.insetBy(dx: tolerance, dy: tolerance)
        return r.contains(p) && !inner.contains(p)
    }
}

final class RectAnnotation: BoxAnnotation {
    override func draw(doc: Document) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = max(1.5, lineWidth)
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    override func contains(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        return nearOutline(p, tolerance: max(tolerance, lineWidth))
    }
}

final class EllipseAnnotation: BoxAnnotation {
    override func draw(doc: Document) {
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = max(1.5, lineWidth)
        color.setStroke()
        path.stroke()
    }

    override func contains(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        let t = max(tolerance, lineWidth)
        let outer = NSBezierPath(ovalIn: rect.insetBy(dx: -t, dy: -t))
        let inner = NSBezierPath(ovalIn: rect.insetBy(dx: t, dy: t))
        return outer.contains(p) && !inner.contains(p)
    }
}

final class PixelateAnnotation: BoxAnnotation {
    override func draw(doc: Document) {
        let r = rect
        guard r.width > 1, r.height > 1, let pix = doc.pixelatedImage() else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: r).setClip()
        pix.draw(in: CGRect(origin: .zero, size: doc.size),
                 from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
    }

    override func contains(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
    }
}

// MARK: - Text

final class TextAnnotation: Annotation {
    /// Lower left corner of the text block, image coordinates.
    var origin: CGPoint = .zero
    var text: String = ""
    var fontSize: CGFloat = 32
    var fontName: String = "Marker Felt"

    var font: NSFont {
        return NSFont(name: fontName, size: fontSize) ?? NSFont.boldSystemFont(ofSize: fontSize)
    }

    var attributes: [NSAttributedString.Key: Any] {
        return [.font: font, .foregroundColor: color]
    }

    var textSize: CGSize {
        let s = (text as NSString).size(withAttributes: attributes)
        return CGSize(width: max(s.width, fontSize * 0.6), height: max(s.height, fontSize))
    }

    override func draw(doc: Document) {
        guard !text.isEmpty else { return }
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    override var boundingBox: CGRect { return CGRect(origin: origin, size: textSize) }

    override func contains(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        return boundingBox.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
    }

    override func translate(by d: CGPoint) {
        origin = CGPoint(x: origin.x + d.x, y: origin.y + d.y)
    }

    override func scale(by f: CGFloat) {
        super.scale(by: f)
        origin = CGPoint(x: origin.x * f, y: origin.y * f)
        fontSize *= f
    }

    /// A single handle at the top right scales the font.
    override var handles: [CGPoint] {
        let b = boundingBox
        return [CGPoint(x: b.maxX, y: b.maxY)]
    }

    override func moveHandle(_ index: Int, to p: CGPoint) {
        let newHeight = max(10, p.y - origin.y)
        let ratio = newHeight / max(1, textSize.height)
        fontSize = max(8, min(400, fontSize * ratio))
    }

    override var isSubstantial: Bool { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    override func copyState(from other: Annotation) {
        super.copyState(from: other)
        if let o = other as? TextAnnotation {
            origin = o.origin; text = o.text; fontSize = o.fontSize; fontName = o.fontName
        }
    }
}

// MARK: - Freehand pen and marker

final class PenAnnotation: Annotation {
    var points: [CGPoint] = []
    var isMarker = false

    private var path: NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.line(to: CGPoint(x: first.x + 0.1, y: first.y))
        } else {
            // Smooth the polyline with midpoint quadratic segments.
            for i in 1..<(points.count - 1) {
                let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2,
                                  y: (points[i].y + points[i + 1].y) / 2)
                path.curve(to: mid, controlPoint1: points[i], controlPoint2: points[i])
            }
            path.line(to: points[points.count - 1])
        }
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }

    var strokeWidth: CGFloat { return isMarker ? max(8, lineWidth * 4) : max(1.5, lineWidth) }

    override func draw(doc: Document) {
        guard !points.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        if isMarker {
            NSGraphicsContext.current?.compositingOperation = .multiply
            color.withAlphaComponent(0.42).setStroke()
        } else {
            color.setStroke()
        }
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func contains(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        let t = max(tolerance, strokeWidth / 2)
        if points.count == 1 { return hypot(p.x - points[0].x, p.y - points[0].y) <= t }
        for i in 0..<(points.count - 1) {
            if distance(p, toSegment: points[i], points[i + 1]) <= t { return true }
        }
        return false
    }

    override func translate(by d: CGPoint) {
        points = points.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
    }

    override func scale(by f: CGFloat) {
        super.scale(by: f)
        points = points.map { CGPoint(x: $0.x * f, y: $0.y * f) }
    }

    override var boundingBox: CGRect {
        guard let first = points.first else { return .zero }
        var r = CGRect(origin: first, size: .zero)
        for p in points { r = r.union(CGRect(origin: p, size: .zero)) }
        return r.insetBy(dx: -strokeWidth, dy: -strokeWidth)
    }

    override var isSubstantial: Bool { return points.count > 1 }

    override func copyState(from other: Annotation) {
        super.copyState(from: other)
        if let o = other as? PenAnnotation { points = o.points; isMarker = o.isMarker }
    }
}

// MARK: - Document

/// Creates an off-screen bitmap whose user space is exactly one unit per pixel.
/// NSImage.lockFocus() must not be used for this: on a retina display it silently
/// produces a 2x backing store and doubles the logical size of the result.
func makeBitmapRep(width: Int, height: Int) -> NSBitmapImageRep? {
    guard width > 0, height > 0 else { return nil }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)
    rep?.size = NSSize(width: width, height: height)
    return rep
}

/// Renders into a fresh bitmap of the given pixel size and returns it as an image.
func renderImage(width: Int, height: Int, _ body: () -> Void) -> NSImage? {
    guard let rep = makeBitmapRep(width: width, height: height) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    body()
    NSGraphicsContext.restoreGraphicsState()
    let img = NSImage(size: NSSize(width: width, height: height))
    img.addRepresentation(rep)
    return img
}

final class Document {
    var image: NSImage
    var annotations: [Annotation] = []
    /// True for an empty canvas that was not pasted or opened, so the hint stays visible.
    var isBlank: Bool = false
    var sourceName: String?

    private var pixelCache: NSImage?
    private var pixelCacheBlock: CGFloat = 0

    var size: CGSize { return image.size }

    init(image: NSImage) {
        self.image = Document.normalized(image)
    }

    static func blank(width: Int = 1280, height: Int = 800) -> Document {
        let img = renderImage(width: width, height: height) {
            NSColor.white.setFill()
            NSBezierPath(rect: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))).fill()
        } ?? NSImage(size: NSSize(width: width, height: height))
        let doc = Document(image: img)
        doc.isBlank = true
        return doc
    }

    /// Force the logical size to the pixel size of the best representation so that
    /// image coordinates equal pixels, even for retina screenshots tagged at 144 dpi.
    static func normalized(_ img: NSImage) -> NSImage {
        var bestWidth = 0
        var bestHeight = 0
        for rep in img.representations where rep.pixelsWide > bestWidth {
            bestWidth = rep.pixelsWide
            bestHeight = rep.pixelsHigh
        }
        if bestWidth > 0 && bestHeight > 0 {
            img.size = NSSize(width: bestWidth, height: bestHeight)
        }
        return img
    }

    // MARK: Pixelation source

    var pixelBlockSize: CGFloat {
        return max(6, min(size.width, size.height) / 55)
    }

    func pixelatedImage() -> NSImage? {
        let block = pixelBlockSize
        if let cached = pixelCache, pixelCacheBlock == block { return cached }
        let w = max(1, Int(size.width / block))
        let h = max(1, Int(size.height / block))
        guard let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        small.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
        NSGraphicsContext.current?.imageInterpolation = .medium
        image.draw(in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        NSGraphicsContext.restoreGraphicsState()

        let smallImage = NSImage(size: NSSize(width: w, height: h))
        smallImage.addRepresentation(small)

        guard let out = renderImage(width: Int(round(size.width)), height: Int(round(size.height)), {
            NSGraphicsContext.current?.imageInterpolation = .none
            smallImage.draw(in: CGRect(origin: .zero, size: size),
                            from: .zero, operation: .copy, fraction: 1.0)
        }) else { return nil }

        pixelCache = out
        pixelCacheBlock = block
        return out
    }

    func invalidateCaches() {
        pixelCache = nil
        pixelCacheBlock = 0
    }

    // MARK: Rendering

    /// Image plus all annotations, at full pixel resolution.
    func flattened() -> NSBitmapImageRep? {
        let w = Int(round(size.width)), h = Int(round(size.height))
        guard let rep = makeBitmapRep(width: w, height: h) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        for a in annotations { a.draw(doc: self) }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    func pngData() -> Data? {
        return flattened()?.representation(using: .png, properties: [:])
    }

    func jpegData(quality: CGFloat = 0.9) -> Data? {
        return flattened()?.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    func flattenedImage() -> NSImage? {
        guard let rep = flattened() else { return nil }
        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
    }

    // MARK: Destructive edits

    func crop(to r: CGRect) {
        // Round rather than use CGRect.integral: integral grows the rect outwards,
        // so a typed 1363 x 1329 would silently become 1364 x 1330.
        let rounded = CGRect(x: r.minX.rounded(), y: r.minY.rounded(),
                             width: r.width.rounded(), height: r.height.rounded())
        let clipped = rounded.intersection(CGRect(origin: .zero, size: size))
        guard clipped.width > 4, clipped.height > 4 else { return }
        let w = Int(clipped.width), h = Int(clipped.height)
        guard let rep = makeBitmapRep(width: w, height: h) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(x: -clipped.minX, y: -clipped.minY,
                              width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
        let newImage = NSImage(size: NSSize(width: w, height: h))
        newImage.addRepresentation(rep)
        image = newImage
        let shift = CGPoint(x: -clipped.minX, y: -clipped.minY)
        for a in annotations { a.translate(by: shift) }
        isBlank = false
        invalidateCaches()
    }

    func resize(factor f: CGFloat) {
        guard f > 0.01, f < 20, abs(f - 1) > 0.001 else { return }
        let w = Int(round(size.width * f)), h = Int(round(size.height * f))
        guard let rep = makeBitmapRep(width: w, height: h) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        NSGraphicsContext.restoreGraphicsState()
        let newImage = NSImage(size: NSSize(width: w, height: h))
        newImage.addRepresentation(rep)
        image = newImage
        for a in annotations { a.scale(by: f) }
        invalidateCaches()
    }

    // MARK: Undo snapshots

    struct Snapshot {
        let image: NSImage
        let annotations: [Annotation]
        let isBlank: Bool
    }

    func snapshot() -> Snapshot {
        return Snapshot(image: image, annotations: annotations.map { $0.clone() }, isBlank: isBlank)
    }

    func restore(_ s: Snapshot) {
        image = s.image
        annotations = s.annotations.map { $0.clone() }
        isBlank = s.isBlank
        invalidateCaches()
    }
}
