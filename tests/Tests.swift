import AppKit

var failures = 0
func check(_ label: String, _ ok: Bool) {
    print((ok ? "  ok   " : "  FAIL ") + label)
    if !ok { failures += 1 }
}

// Base image: white with a black square in the lower left quadrant.
let base = renderImage(width: 400, height: 300) {
    NSColor.white.setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: 400, height: 300)).fill()
    NSColor.black.setFill()
    NSBezierPath(rect: CGRect(x: 20, y: 20, width: 60, height: 60)).fill()
}!

let doc = Document(image: base)
check("Image size = pixel size", doc.size == CGSize(width: 400, height: 300))

let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)

let rect = RectAnnotation()
rect.color = red; rect.lineWidth = 8
rect.p0 = CGPoint(x: 200, y: 200); rect.p1 = CGPoint(x: 300, y: 260)
doc.annotations.append(rect)

let arrow = ArrowAnnotation()
arrow.color = red; arrow.lineWidth = 6
arrow.start = CGPoint(x: 120, y: 120); arrow.end = CGPoint(x: 180, y: 120)
doc.annotations.append(arrow)

let text = TextAnnotation()
text.color = red; text.fontSize = 40; text.text = "Hallo"
text.origin = CGPoint(x: 150, y: 250)
doc.annotations.append(text)

let pen = PenAnnotation()
pen.color = red; pen.lineWidth = 6
pen.points = [CGPoint(x: 300, y: 60), CGPoint(x: 340, y: 90), CGPoint(x: 380, y: 60)]
doc.annotations.append(pen)

let marker = PenAnnotation()
marker.color = red; marker.lineWidth = 6; marker.isMarker = true
marker.points = [CGPoint(x: 100, y: 40), CGPoint(x: 260, y: 40)]
doc.annotations.append(marker)

let pixelate = PixelateAnnotation()
pixelate.p0 = CGPoint(x: 10, y: 10); pixelate.p1 = CGPoint(x: 90, y: 90)
doc.annotations.append(pixelate)

guard let png = doc.pngData() else { fatalError("no PNG") }
// Own scratch directory, created on demand: a hard coded /tmp path is gone
// after a reboot and takes the whole suite down with it.
let scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kritzel-tests")
try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
try! png.write(to: scratch.appendingPathComponent("out.png"))
check("PNG created (> 1 kB)", png.count > 1000)

let rendered = NSBitmapImageRep(data: png)!
check("Export at full resolution", rendered.pixelsWide == 400 && rendered.pixelsHigh == 300)

func isRed(_ x: Int, _ y: Int) -> Bool {
    // NSBitmapImageRep addresses rows from the top.
    guard let c = rendered.colorAt(x: x, y: 300 - 1 - y)?.usingColorSpace(.sRGB) else { return false }
    return c.redComponent > 0.6 && c.greenComponent < 0.45 && c.blueComponent < 0.45
}
func pixel(_ x: Int, _ y: Int) -> NSColor {
    return rendered.colorAt(x: x, y: 300 - 1 - y)!.usingColorSpace(.sRGB)!
}

check("Rectangle edge drawn", isRed(250, 200))
check("Rectangle interior empty", !isRed(250, 230))
check("Arrow shaft drawn", isRed(140, 120))
check("Arrow head drawn", isRed(176, 120))
check("Text drawn", (150...260).contains(where: { x in (250...290).contains(where: { y in isRed(x, y) }) }))
var penPixels = 0
for x in 300...380 { for y in 50...95 where isRed(x, y) { penPixels += 1 } }
check("Pen drawn (\(penPixels) pixels)", penPixels > 40)
let markerPixel = pixel(180, 40)
check("Highlighter is semi-transparent", markerPixel.redComponent > 0.8 && markerPixel.greenComponent > 0.3 && markerPixel.greenComponent < 0.85)
check("Pixelation stays local", pixel(200, 150).brightnessComponent > 0.98)

// Fine stripes are the honest test for pixelation: inside the region neighbouring
// pixels must collapse to one averaged block colour, outside they must not.
let striped = renderImage(width: 200, height: 100) {
    NSColor.white.setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: 200, height: 100)).fill()
    NSColor.black.setFill()
    for x in stride(from: 0, to: 200, by: 2) {
        NSBezierPath(rect: CGRect(x: CGFloat(x), y: 0, width: 1, height: 100)).fill()
    }
}!
let stripeDoc = Document(image: striped)
let blur = PixelateAnnotation()
blur.p0 = CGPoint(x: 20, y: 20); blur.p1 = CGPoint(x: 180, y: 80)
stripeDoc.annotations.append(blur)
let stripeRep = NSBitmapImageRep(data: stripeDoc.pngData()!)!
func stripePixel(_ x: Int, _ y: Int) -> NSColor {
    return stripeRep.colorAt(x: x, y: 100 - 1 - y)!.usingColorSpace(.sRGB)!
}
let inA = stripePixel(100, 50), inB = stripePixel(101, 50)
check("Pixelation smooths neighbouring pixels",
      abs(inA.brightnessComponent - inB.brightnessComponent) < 0.05)
check("Pixelation yields a blended grey",
      inA.brightnessComponent > 0.1 && inA.brightnessComponent < 0.9)
let outA = stripePixel(5, 50), outB = stripePixel(6, 50)
check("Stripes stay sharp outside",
      abs(outA.brightnessComponent - outB.brightnessComponent) > 0.5)

// Crop moves annotations along with the image.
let snapshot = doc.snapshot()
doc.crop(to: CGRect(x: 100, y: 100, width: 200, height: 150))
check("Crop sets the new size", doc.size == CGSize(width: 200, height: 150))
check("Crop shifts objects", abs(arrow.start.x - 20) < 0.01 && abs(arrow.start.y - 20) < 0.01)

doc.restore(snapshot)
check("Undo restores the size", doc.size == CGSize(width: 400, height: 300))
check("Undo restores the object count", doc.annotations.count == 6)

doc.resize(factor: 2)
check("Resize scales the image", doc.size == CGSize(width: 800, height: 600))
if let scaledArrow = doc.annotations.first(where: { $0 is ArrowAnnotation }) as? ArrowAnnotation {
    check("Resize scales objects", abs(scaledArrow.start.x - 240) < 0.01)
}

// Hit testing and handles.
let hitDoc = Document(image: base)
let box = RectAnnotation()
box.p0 = CGPoint(x: 100, y: 100); box.p1 = CGPoint(x: 200, y: 200)
hitDoc.annotations.append(box)
check("Hit on the edge", box.contains(CGPoint(x: 100, y: 150), tolerance: 6))
check("No hit in the middle", !box.contains(CGPoint(x: 150, y: 150), tolerance: 6))
box.moveHandle(0, to: CGPoint(x: 50, y: 50))
check("Handle drags the corner", box.rect == CGRect(x: 50, y: 50, width: 150, height: 150))
let cloned = box.clone() as! RectAnnotation
cloned.translate(by: CGPoint(x: 10, y: 0))
check("Clone is independent", box.rect.minX == 50 && cloned.rect.minX == 60)


// MARK: - Interaction tests
//
// These drive the real CanvasView with synthesized mouse events inside an
// off-screen window, so tool handling, selection, undo and crop are exercised
// exactly as they are when clicking, without needing a visible screen.

print("\n-- Interaction --")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let uiImage = renderImage(width: 600, height: 400) {
    NSColor.white.setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: 600, height: 400)).fill()
}!
let controller = EditorController(doc: Document(image: uiImage))
let canvas = controller.canvas
controller.window?.setFrame(NSRect(x: 0, y: 0, width: 900, height: 640), display: false)
canvas.frame = NSRect(x: 0, y: 0, width: 900, height: 596)
canvas.layoutSubtreeIfNeeded()

/// Converts an image point to window coordinates the way a real click arrives.
func windowPoint(_ imagePoint: CGPoint) -> CGPoint {
    let viewPoint = canvas.debugViewPoint(for: imagePoint)
    return canvas.convert(viewPoint, to: nil)
}

func event(_ type: NSEvent.EventType, _ imagePoint: CGPoint, clicks: Int = 1) -> NSEvent {
    return NSEvent.mouseEvent(with: type, location: windowPoint(imagePoint), modifierFlags: [],
                              timestamp: ProcessInfo.processInfo.systemUptime,
                              windowNumber: controller.window?.windowNumber ?? 0,
                              context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
}

func drag(from a: CGPoint, to b: CGPoint, steps: Int = 4) {
    canvas.mouseDown(with: event(.leftMouseDown, a))
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        canvas.mouseDragged(with: event(.leftMouseDragged,
                                        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)))
    }
    canvas.mouseUp(with: event(.leftMouseUp, b))
}

func click(_ p: CGPoint, clicks: Int = 1) {
    canvas.mouseDown(with: event(.leftMouseDown, p, clicks: clicks))
    canvas.mouseUp(with: event(.leftMouseUp, p, clicks: clicks))
}

// Draw an arrow.
canvas.tool = .arrow
drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 250))
check("Dragging creates an arrow", canvas.doc.annotations.count == 1 && canvas.doc.annotations[0] is ArrowAnnotation)
if let a = canvas.doc.annotations.first as? ArrowAnnotation {
    check("Arrow ends under the pointer",
          abs(a.end.x - 300) < 1.5 && abs(a.end.y - 250) < 1.5)
}

// A click without dragging must not leave a stray object behind.
canvas.tool = .rect
click(CGPoint(x: 400, y: 300))
check("Click without drag creates nothing", canvas.doc.annotations.count == 1)

// Draw a rectangle, then select and move it.
drag(from: CGPoint(x: 350, y: 80), to: CGPoint(x: 500, y: 200))
check("Rectangle drawn", canvas.doc.annotations.count == 2)
canvas.tool = .select
click(CGPoint(x: 350, y: 140))
check("Click on the edge selects", canvas.selectedAnnotation is RectAnnotation)
let beforeMove = (canvas.selectedAnnotation as! RectAnnotation).rect
drag(from: CGPoint(x: 350, y: 140), to: CGPoint(x: 370, y: 160))
let afterMove = (canvas.selectedAnnotation as! RectAnnotation).rect
check("Selection can be moved",
      abs(afterMove.minX - beforeMove.minX - 20) < 1.5 && abs(afterMove.minY - beforeMove.minY - 20) < 1.5)

// Handle dragging resizes.
let handle = canvas.selectedAnnotation!.handles[2]
drag(from: handle, to: CGPoint(x: handle.x + 40, y: handle.y + 30))
check("Handle enlarges the object",
      (canvas.selectedAnnotation as! RectAnnotation).rect.width > afterMove.width + 30)

// Undo and redo walk the whole stack.
let countBeforeUndo = canvas.doc.annotations.count
canvas.undoAction(nil)
canvas.undoAction(nil)
canvas.undoAction(nil)
check("Undo steps back", canvas.doc.annotations.count < countBeforeUndo)
canvas.redoAction(nil)
canvas.redoAction(nil)
canvas.redoAction(nil)
check("Redo restores", canvas.doc.annotations.count == countBeforeUndo)

// Delete removes the selection.
canvas.tool = .select
click(CGPoint(x: 370, y: 160))
let countBeforeDelete = canvas.doc.annotations.count
canvas.deleteSelection(nil)
check("Delete removes the selection", canvas.doc.annotations.count == countBeforeDelete - 1)

// Text: placing starts an inline editor, committing keeps the text.
canvas.tool = .text
click(CGPoint(x: 120, y: 300))
check("Text tool opens the inline editor", canvas.isEditingText)
canvas.debugSetEditingText("Testnotiz")
canvas.commitTextEditing()
let placed = canvas.doc.annotations.compactMap { $0 as? TextAnnotation }.first
check("Text is committed", placed?.text == "Testnotiz")
check("Editor is closed again", !canvas.isEditingText)

// Empty text must not leave an invisible object behind.
let countBeforeEmpty = canvas.doc.annotations.count
click(CGPoint(x: 200, y: 320))
canvas.commitTextEditing()
check("Empty text is discarded", canvas.doc.annotations.count == countBeforeEmpty)

// -- Werkzeugleiste folgt der Auswahl ----------------------------------
canvas.tool = .select
canvas.doc.annotations.removeAll()

let styled = RectAnnotation()
styled.color = kritzelPalette[4]          // blau
styled.lineWidth = 13
styled.p0 = CGPoint(x: 80, y: 80); styled.p1 = CGPoint(x: 260, y: 220)
canvas.doc.annotations.append(styled)

let styledText = TextAnnotation()
styledText.color = kritzelPalette[3]      // gruen
styledText.fontSize = 44
styledText.text = "Notiz"
styledText.origin = CGPoint(x: 320, y: 300)
canvas.doc.annotations.append(styledText)

// Start from values that differ from both objects.
canvas.color = kritzelPalette[0]
canvas.lineWidth = 5
canvas.fontSize = 32

click(CGPoint(x: 80, y: 150))
check("Selection sets the line width", abs(canvas.lineWidth - 13) < 0.01)
check("Selection sets the colour", sameColor(canvas.color, kritzelPalette[4]))
var state = controller.debugControlState()
check("Slider shows the object's width", abs(state.width - 13) < 0.01)
check("Colour well shows the object's colour", state.colorIndex == 4)

// Changing one control must not touch the other properties.
canvas.color = kritzelPalette[6]
check("Colour change recolours the object", sameColor(styled.color, kritzelPalette[6]))
check("Colour change leaves the width alone", abs(styled.lineWidth - 13) < 0.01)
canvas.lineWidth = 3
check("Width change applies to the object", abs(styled.lineWidth - 3) < 0.01)
check("Width change leaves the colour alone", sameColor(styled.color, kritzelPalette[6]))

// Text objects bring their own size along.
click(CGPoint(x: 340, y: 310))
check("Selection sets the text size", abs(canvas.fontSize - 44) < 0.01)
state = controller.debugControlState()
check("Menu shows the object's text size", state.fontSize == 44)

// A size the menu does not list gets its own entry rather than showing a wrong one.
styledText.fontSize = 37
canvas.deleteSelection(nil)
canvas.undoAction(nil)
if let restored = canvas.doc.annotations.compactMap({ $0 as? TextAnnotation }).first {
    click(CGPoint(x: restored.origin.x + 20, y: restored.origin.y + 10))
    state = controller.debugControlState()
    check("Odd text size is shown (\(state.fontSize) pt)", state.fontSize == 37)
    check("Text selected: text size only", state.fontEnabled && !state.widthEnabled)
}

// Only the control that applies stays live, so the two cannot be confused.
canvas.tool = .text
state = controller.debugControlState()
check("Text tool: text size on, width off", state.fontEnabled && !state.widthEnabled)
canvas.tool = .arrow
state = controller.debugControlState()
check("Arrow tool: width on, text size off", state.widthEnabled && !state.fontEnabled)
canvas.tool = .pixelate
state = controller.debugControlState()
check("Pixelate: both off", !state.widthEnabled && !state.fontEnabled)
canvas.tool = .select
click(CGPoint(x: 80, y: 150))
state = controller.debugControlState()
check("Rectangle selected: width only", state.widthEnabled && !state.fontEnabled)

// Deselecting leaves the controls where they are, ready for the next object.
click(CGPoint(x: 560, y: 380))
check("Click on empty space clears the selection", canvas.selectedAnnotation == nil)

// -- Copy and paste -----------------------------------------------------
canvas.tool = .select
canvas.doc.annotations.removeAll()

let original = ArrowAnnotation()
original.color = kritzelPalette[2]
original.lineWidth = 9
original.start = CGPoint(x: 100, y: 100)
original.end = CGPoint(x: 250, y: 180)
canvas.doc.annotations.append(original)

click(CGPoint(x: 175, y: 140))
check("Arrow selected for copying", canvas.selectedAnnotation === original)

canvas.copy(nil)
canvas.paste(nil)
check("Paste adds a second object", canvas.doc.annotations.count == 2)
if let pasted = canvas.doc.annotations.last as? ArrowAnnotation {
    check("Copy is offset",
          abs(pasted.start.x - original.start.x - 18) < 0.01
          && abs(pasted.start.y - original.start.y + 18) < 0.01)
    check("Copy keeps the style",
          sameColor(pasted.color, kritzelPalette[2]) && abs(pasted.lineWidth - 9) < 0.01)
    check("Copy is selected", canvas.selectedAnnotation === pasted)
    pasted.translate(by: CGPoint(x: 5, y: 5))
    check("Copy is detached from the original", abs(original.start.x - 100) < 0.01)
}

// Pasting again steps further along instead of stacking on the same spot.
canvas.paste(nil)
check("Second paste does not stack", canvas.doc.annotations.count == 3)
if let third = canvas.doc.annotations.last as? ArrowAnnotation {
    check("Offset grows", abs(third.start.x - original.start.x - 36) < 0.01)
}

canvas.undoAction(nil)
check("Paste can be undone", canvas.doc.annotations.count == 2)

// Without a selection the shortcut means the whole picture. A private pasteboard
// keeps the test out of whatever the user currently has copied.
click(CGPoint(x: 580, y: 30))
check("Nothing selected", canvas.selectedAnnotation == nil)
let scratchBoard = NSPasteboard(name: NSPasteboard.Name("de.markusuhl.kritzel.tests"))
check("Image lands on the clipboard", canvas.copyImage(to: scratchBoard))
if let data = scratchBoard.data(forType: .png), let rep = NSBitmapImageRep(data: data) {
    check("Clipboard holds the whole image at full resolution",
          rep.pixelsWide == Int(canvas.doc.size.width) && rep.pixelsHigh == Int(canvas.doc.size.height))
} else {
    check("Clipboard holds the whole image at full resolution", false)
}
scratchBoard.releaseGlobally()

// A fresh clipboard beats the stale object buffer.
click(CGPoint(x: 175, y: 140))
canvas.copy(nil)
NSPasteboard.general.clearContents()
NSPasteboard.general.setString("irgendwas anderes", forType: .string)
check("After a foreign copy no object is pasted any more", !canvas.pasteCopiedAnnotation())

canvas.doc.annotations.removeAll()
canvas.tool = .select

// -- Zuschneiden --------------------------------------------------------
func cropIs(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, tolerance: CGFloat = 1.5) -> Bool {
    guard let r = canvas.cropRect else { return false }
    return abs(r.minX - x) < tolerance && abs(r.minY - y) < tolerance
        && abs(r.width - w) < tolerance && abs(r.height - h) < tolerance
}

canvas.tool = .crop
check("Crop frame starts on the whole image", cropIs(0, 0, 600, 400))

// Corner grip: the opposite corner stays put.
drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
check("Corner grip drags the corner", cropIs(50, 50, 550, 350))
drag(from: CGPoint(x: 600, y: 400), to: CGPoint(x: 450, y: 350))
check("Opposite corner grip", cropIs(50, 50, 400, 300))

// Edge grip moves one side only.
drag(from: CGPoint(x: 250, y: 50), to: CGPoint(x: 250, y: 100))
check("Edge grip moves one side only", cropIs(50, 100, 400, 250))

// Dragging inside the frame moves it as a whole.
drag(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 230, y: 220))
check("Dragging inside the frame moves it", cropIs(80, 120, 400, 250))

// The frame cannot leave the image.
drag(from: CGPoint(x: 230, y: 220), to: CGPoint(x: 900, y: 900))
check("Frame stays inside the image", cropIs(200, 150, 400, 250))

// Typed values resize from the top left.
canvas.setCropSize(width: 120, height: 90)
check("Typed size is applied", cropIs(200, 310, 120, 90))
canvas.setCropSize(width: 5000, height: 5000)
check("Typed size is clamped", (canvas.cropRect?.width ?? 0) <= 600 && (canvas.cropRect?.height ?? 0) <= 400)

// Dragging outside the frame starts a fresh one.
canvas.resetCropFrame(nil)
drag(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 400, y: 300))
check("Frame can be drawn anew", canvas.cropRect != nil)

// Escape leaves crop mode without touching the image.
canvas.cancelCrop(nil)
check("Cancel leaves crop mode", canvas.cropRect == nil && canvas.tool == .select)
check("Cancel leaves the image untouched", canvas.doc.size == CGSize(width: 600, height: 400))

// Applying an untouched full frame is a no-op rather than a pointless undo step.
canvas.tool = .crop
canvas.applyCrop(nil)
check("Full-image frame crops nothing", canvas.doc.size == CGSize(width: 600, height: 400))

// A crop frame is legitimately empty for a moment: the first pixel of a new drag,
// or a grip pulled across the opposite edge. Rendering has to survive that --
// NSBezierPath(rect:) returns an empty path for an empty rect, and reversing an
// empty path throws.
func renderCanvas() {
    guard let cache = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return }
    canvas.cacheDisplay(in: canvas.bounds, to: cache)
}

canvas.tool = .crop
renderCanvas()
check("Crop overlay renders", true)

// Bottom edge dragged up past the top edge: height collapses to zero.
drag(from: CGPoint(x: 300, y: 0), to: CGPoint(x: 300, y: 400))
renderCanvas()
check("Flattened frame renders", true)

// First pixel of a fresh frame: width and height are both zero.
canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 100, y: 100)))
renderCanvas()
canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 100, y: 100)))
check("Point-sized frame renders", true)

// Frame dragged completely off the image.
canvas.resetCropFrame(nil)
drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 5, y: 5))
renderCanvas()
check("Tiny frame renders", true)

// A frame that no longer overlaps the image at all -- what is left over when the
// image shrinks underneath an existing frame.
canvas.tool = .crop
canvas.debugSetCropRect(CGRect(x: 900, y: 900, width: 200, height: 150))
renderCanvas()
check("Frame outside the image renders", true)

// The real crop.
canvas.tool = .select
canvas.tool = .crop
drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
drag(from: CGPoint(x: 600, y: 400), to: CGPoint(x: 450, y: 350))
canvas.applyCrop(nil)
check("Cropping changes the image size", canvas.doc.size == CGSize(width: 400, height: 300))
check("Select tool is active after cropping", canvas.tool == .select)
check("Crop bar disappears again", canvas.cropRect == nil)
canvas.undoAction(nil)
check("Cropping can be undone", canvas.doc.size == CGSize(width: 600, height: 400))

// Undo and redo while the crop tool is still active change the image under the
// frame. That is how the frame ended up outside the image and crashed drawing.
canvas.tool = .crop
canvas.redoAction(nil)
renderCanvas()
check("Redo in crop mode renders", canvas.doc.size == CGSize(width: 400, height: 300))
check("Frame stays inside the shrunken image",
      (canvas.cropRect ?? .zero).maxX <= 400.5 && (canvas.cropRect ?? .zero).maxY <= 300.5)
canvas.undoAction(nil)
renderCanvas()
check("Undo in crop mode renders", canvas.doc.size == CGSize(width: 600, height: 400))
canvas.cancelCrop(nil)

// The view actually renders something other than the plain background.
let cache = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
canvas.cacheDisplay(in: canvas.bounds, to: cache)
var distinctColours = Set<String>()
for x in stride(from: 4, to: cache.pixelsWide - 4, by: 17) {
    for y in stride(from: 4, to: cache.pixelsHigh - 4, by: 17) {
        if let c = cache.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
            distinctColours.insert(String(format: "%.1f-%.1f-%.1f",
                                          c.redComponent, c.greenComponent, c.blueComponent))
        }
    }
}
check("Canvas renders image and objects (\(distinctColours.count) colours)", distinctColours.count >= 3)

// Export from the live canvas keeps full resolution.
if let png = canvas.doc.pngData(), let rep = NSBitmapImageRep(data: png) {
    check("Export from the window at original resolution",
          rep.pixelsWide == 600 && rep.pixelsHigh == 400)
} else {
    check("Export from the window at original resolution", false)
}

// Zoom: fit by default, manual factors keep the anchor point in place.
canvas.tool = .select
let zs = canvas.doc.size
let zc = CGPoint(x: zs.width / 2, y: zs.height / 2)
func near(_ a: CGPoint, _ b: CGPoint, _ tol: CGFloat = 0.01) -> Bool {
    return abs(a.x - b.x) < tol && abs(a.y - b.y) < tol
}
check("Start: fitted to the window", canvas.zoomFactor == nil)
let fitted = canvas.currentScale
let centreBefore = canvas.debugViewPoint(for: zc)

canvas.zoomActualSize(nil)
check("100%: one image pixel = one point", canvas.currentScale == 1)
check("Zoom keeps the image centre in place", near(canvas.debugViewPoint(for: zc), centreBefore))

canvas.zoomIn(nil)
check("Zoom in jumps to the next stop", canvas.currentScale == 1.5)
canvas.zoomOut(nil); canvas.zoomOut(nil)
check("Zoom out jumps to the stop below", canvas.currentScale == 0.75)

// Zoom around a point off centre: that image point must not move.
canvas.setZoom(4)
let pivotImage = CGPoint(x: zs.width * 0.3, y: zs.height * 0.6)
let pivotView = canvas.debugViewPoint(for: pivotImage)
canvas.setZoom(8, anchor: pivotView)
check("Zoom around the pointer keeps the point under it in place",
      near(canvas.debugViewPoint(for: pivotImage), pivotView))

// Panning stops at the image edge instead of scrolling it out of view.
canvas.debugPan(by: CGPoint(x: 100_000, y: 100_000))
let corner = canvas.debugViewPoint(for: .zero)
check("Panning stops at the image edge", near(corner, CGPoint(x: 14, y: 14)))

// Drawing while zoomed and panned lands on the right image pixels.
canvas.setZoom(3)
let visible = CGPoint(x: (canvas.bounds.midX - canvas.debugViewPoint(for: .zero).x) / 3,
                      y: (canvas.bounds.midY - canvas.debugViewPoint(for: .zero).y) / 3)
let before = canvas.doc.annotations.count
canvas.tool = .rect
drag(from: visible, to: CGPoint(x: visible.x + 40, y: visible.y + 30))
if canvas.doc.annotations.count == before + 1, let r = canvas.doc.annotations.last as? RectAnnotation {
    check("Drawing while zoomed hits the image coordinates",
          near(r.p0, visible, 0.5) && near(r.p1, CGPoint(x: visible.x + 40, y: visible.y + 30), 0.5))
} else {
    check("Drawing while zoomed hits the image coordinates", false)
}
renderCanvas()
check("Zoomed view renders", true)

canvas.setZoom(1000)
check("Zoom has an upper limit", canvas.currentScale == 16)
canvas.setZoom(0.0001)
check("Zoom has a lower limit", canvas.currentScale >= 0.02 && canvas.currentScale <= 0.1)

canvas.zoomToFit(nil)
check("Zoom to fit restores the starting state",
      canvas.zoomFactor == nil && canvas.currentScale == fitted
      && near(canvas.debugViewPoint(for: zc), centreBefore))

// Localization: every string the code looks up needs a German translation,
// and the German file must not carry entries the code no longer uses.
print("\n-- Localization --")
if CommandLine.arguments.count > 1 {
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    let sources = root.appendingPathComponent("Sources")
    var used = Set<String>()
    let pattern = try! NSRegularExpression(pattern: #"\bL\("((?:[^"\\]|\\.)*)""#)
    for file in (try? FileManager.default.contentsOfDirectory(atPath: sources.path)) ?? []
        where file.hasSuffix(".swift") {
        guard let code = try? String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8) else { continue }
        for m in pattern.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
            used.insert(String(code[Range(m.range(at: 1), in: code)!]))
        }
    }
    func table(_ lang: String) -> [String: String] {
        let url = root.appendingPathComponent("Localization/\(lang).lproj/Localizable.strings")
        return (NSDictionary(contentsOf: url) as? [String: String]) ?? [:]
    }
    let german = table("de"), english = table("en")
    check("Source strings found (\(used.count))", used.count > 50)
    let untranslated = used.subtracting(german.keys).sorted()
    check("Every string has a German translation" + (untranslated.isEmpty ? "" : ": \(untranslated)"),
          untranslated.isEmpty)
    let stale = Set(german.keys).subtracting(used).sorted()
    check("No stale German entries" + (stale.isEmpty ? "" : ": \(stale)"), stale.isEmpty)
    // Symbolic keys (no English text in the code) must be spelled out in English.
    let symbolic = used.filter { $0.contains(".") && !$0.contains(" ") && !$0.contains("%") }
    check("Symbolic keys have English text", symbolic.allSatisfy { english[$0] != nil })
    // Same placeholders in both languages, or String(format:) reads garbage.
    func placeholders(_ s: String) -> [String] {
        let p = try! NSRegularExpression(pattern: "%[@d]")
        return p.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }
    }
    let mismatched = german.filter { placeholders($0.key) != placeholders($0.value) && english[$0.key] == nil }.keys.sorted()
    check("Placeholders match" + (mismatched.isEmpty ? "" : ": \(mismatched)"), mismatched.isEmpty)
} else {
    check("Repository path passed to the test binary", false)
}

print(failures == 0 ? "\nALL TESTS PASSED" : "\n\(failures) TESTS FAILED")
exit(failures == 0 ? 0 : 1)
