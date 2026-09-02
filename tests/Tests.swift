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
check("Bildgröße = Pixelgröße", doc.size == CGSize(width: 400, height: 300))

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

guard let png = doc.pngData() else { fatalError("kein PNG") }
try! png.write(to: URL(fileURLWithPath: "/tmp/kritzeltest/out.png"))
check("PNG erzeugt (> 1 kB)", png.count > 1000)

let rendered = NSBitmapImageRep(data: png)!
check("Export in voller Auflösung", rendered.pixelsWide == 400 && rendered.pixelsHigh == 300)

func isRed(_ x: Int, _ y: Int) -> Bool {
    // NSBitmapImageRep addresses rows from the top.
    guard let c = rendered.colorAt(x: x, y: 300 - 1 - y)?.usingColorSpace(.sRGB) else { return false }
    return c.redComponent > 0.6 && c.greenComponent < 0.45 && c.blueComponent < 0.45
}
func pixel(_ x: Int, _ y: Int) -> NSColor {
    return rendered.colorAt(x: x, y: 300 - 1 - y)!.usingColorSpace(.sRGB)!
}

check("Rechteck-Kante gezeichnet", isRed(250, 200))
check("Rechteck-Inneres leer", !isRed(250, 230))
check("Pfeilschaft gezeichnet", isRed(140, 120))
check("Pfeilspitze gezeichnet", isRed(176, 120))
check("Text gezeichnet", (150...260).contains(where: { x in (250...290).contains(where: { y in isRed(x, y) }) }))
var penPixels = 0
for x in 300...380 { for y in 50...95 where isRed(x, y) { penPixels += 1 } }
check("Stift gezeichnet (\(penPixels) Pixel)", penPixels > 40)
let markerPixel = pixel(180, 40)
check("Marker halbtransparent", markerPixel.redComponent > 0.8 && markerPixel.greenComponent > 0.3 && markerPixel.greenComponent < 0.85)
check("Verpixelung bleibt lokal", pixel(200, 150).brightnessComponent > 0.98)

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
check("Verpixelung glättet Nachbarpixel",
      abs(inA.brightnessComponent - inB.brightnessComponent) < 0.05)
check("Verpixelung ergibt Mischgrau",
      inA.brightnessComponent > 0.1 && inA.brightnessComponent < 0.9)
let outA = stripePixel(5, 50), outB = stripePixel(6, 50)
check("Ausserhalb bleiben die Streifen scharf",
      abs(outA.brightnessComponent - outB.brightnessComponent) > 0.5)

// Crop moves annotations along with the image.
let snapshot = doc.snapshot()
doc.crop(to: CGRect(x: 100, y: 100, width: 200, height: 150))
check("Crop setzt neue Größe", doc.size == CGSize(width: 200, height: 150))
check("Crop verschiebt Objekte", abs(arrow.start.x - 20) < 0.01 && abs(arrow.start.y - 20) < 0.01)

doc.restore(snapshot)
check("Undo stellt Größe wieder her", doc.size == CGSize(width: 400, height: 300))
check("Undo stellt Objektzahl wieder her", doc.annotations.count == 6)

doc.resize(factor: 2)
check("Resize skaliert Bild", doc.size == CGSize(width: 800, height: 600))
if let scaledArrow = doc.annotations.first(where: { $0 is ArrowAnnotation }) as? ArrowAnnotation {
    check("Resize skaliert Objekte", abs(scaledArrow.start.x - 240) < 0.01)
}

// Hit testing and handles.
let hitDoc = Document(image: base)
let box = RectAnnotation()
box.p0 = CGPoint(x: 100, y: 100); box.p1 = CGPoint(x: 200, y: 200)
hitDoc.annotations.append(box)
check("Treffer auf der Kante", box.contains(CGPoint(x: 100, y: 150), tolerance: 6))
check("Kein Treffer in der Mitte", !box.contains(CGPoint(x: 150, y: 150), tolerance: 6))
box.moveHandle(0, to: CGPoint(x: 50, y: 50))
check("Griff zieht die Ecke", box.rect == CGRect(x: 50, y: 50, width: 150, height: 150))
let cloned = box.clone() as! RectAnnotation
cloned.translate(by: CGPoint(x: 10, y: 0))
check("Clone ist unabhängig", box.rect.minX == 50 && cloned.rect.minX == 60)


// MARK: - Interaction tests
//
// These drive the real CanvasView with synthesized mouse events inside an
// off-screen window, so tool handling, selection, undo and crop are exercised
// exactly as they are when clicking, without needing a visible screen.

print("\n-- Interaktion --")

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
check("Ziehen erzeugt einen Pfeil", canvas.doc.annotations.count == 1 && canvas.doc.annotations[0] is ArrowAnnotation)
if let a = canvas.doc.annotations.first as? ArrowAnnotation {
    check("Pfeil endet unter dem Mauszeiger",
          abs(a.end.x - 300) < 1.5 && abs(a.end.y - 250) < 1.5)
}

// A click without dragging must not leave a stray object behind.
canvas.tool = .rect
click(CGPoint(x: 400, y: 300))
check("Klick ohne Ziehen erzeugt nichts", canvas.doc.annotations.count == 1)

// Draw a rectangle, then select and move it.
drag(from: CGPoint(x: 350, y: 80), to: CGPoint(x: 500, y: 200))
check("Rechteck gezeichnet", canvas.doc.annotations.count == 2)
canvas.tool = .select
click(CGPoint(x: 350, y: 140))
check("Klick auf die Kante wählt aus", canvas.selectedAnnotation is RectAnnotation)
let beforeMove = (canvas.selectedAnnotation as! RectAnnotation).rect
drag(from: CGPoint(x: 350, y: 140), to: CGPoint(x: 370, y: 160))
let afterMove = (canvas.selectedAnnotation as! RectAnnotation).rect
check("Auswahl lässt sich verschieben",
      abs(afterMove.minX - beforeMove.minX - 20) < 1.5 && abs(afterMove.minY - beforeMove.minY - 20) < 1.5)

// Handle dragging resizes.
let handle = canvas.selectedAnnotation!.handles[2]
drag(from: handle, to: CGPoint(x: handle.x + 40, y: handle.y + 30))
check("Griff vergrößert das Objekt",
      (canvas.selectedAnnotation as! RectAnnotation).rect.width > afterMove.width + 30)

// Undo and redo walk the whole stack.
let countBeforeUndo = canvas.doc.annotations.count
canvas.undoAction(nil)
canvas.undoAction(nil)
canvas.undoAction(nil)
check("Undo nimmt Schritte zurück", canvas.doc.annotations.count < countBeforeUndo)
canvas.redoAction(nil)
canvas.redoAction(nil)
canvas.redoAction(nil)
check("Redo stellt wieder her", canvas.doc.annotations.count == countBeforeUndo)

// Delete removes the selection.
canvas.tool = .select
click(CGPoint(x: 370, y: 160))
let countBeforeDelete = canvas.doc.annotations.count
canvas.deleteSelection(nil)
check("Löschen entfernt die Auswahl", canvas.doc.annotations.count == countBeforeDelete - 1)

// Text: placing starts an inline editor, committing keeps the text.
canvas.tool = .text
click(CGPoint(x: 120, y: 300))
check("Textwerkzeug öffnet den Inline-Editor", canvas.isEditingText)
canvas.debugSetEditingText("Testnotiz")
canvas.commitTextEditing()
let placed = canvas.doc.annotations.compactMap { $0 as? TextAnnotation }.first
check("Text wird übernommen", placed?.text == "Testnotiz")
check("Editor ist wieder geschlossen", !canvas.isEditingText)

// Empty text must not leave an invisible object behind.
let countBeforeEmpty = canvas.doc.annotations.count
click(CGPoint(x: 200, y: 320))
canvas.commitTextEditing()
check("Leerer Text wird verworfen", canvas.doc.annotations.count == countBeforeEmpty)

// -- Zuschneiden --------------------------------------------------------
func cropIs(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, tolerance: CGFloat = 1.5) -> Bool {
    guard let r = canvas.cropRect else { return false }
    return abs(r.minX - x) < tolerance && abs(r.minY - y) < tolerance
        && abs(r.width - w) < tolerance && abs(r.height - h) < tolerance
}

canvas.tool = .crop
check("Crop-Rahmen startet auf dem ganzen Bild", cropIs(0, 0, 600, 400))

// Corner grip: the opposite corner stays put.
drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
check("Eckgriff zieht die Ecke", cropIs(50, 50, 550, 350))
drag(from: CGPoint(x: 600, y: 400), to: CGPoint(x: 450, y: 350))
check("Gegenüberliegender Eckgriff", cropIs(50, 50, 400, 300))

// Edge grip moves one side only.
drag(from: CGPoint(x: 250, y: 50), to: CGPoint(x: 250, y: 100))
check("Kantengriff verschiebt nur eine Seite", cropIs(50, 100, 400, 250))

// Dragging inside the frame moves it as a whole.
drag(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 230, y: 220))
check("Ziehen im Rahmen verschiebt ihn", cropIs(80, 120, 400, 250))

// The frame cannot leave the image.
drag(from: CGPoint(x: 230, y: 220), to: CGPoint(x: 900, y: 900))
check("Rahmen bleibt im Bild", cropIs(200, 150, 400, 250))

// Typed values resize from the top left.
canvas.setCropSize(width: 120, height: 90)
check("Getippte Größe wird übernommen", cropIs(200, 310, 120, 90))
canvas.setCropSize(width: 5000, height: 5000)
check("Getippte Größe wird begrenzt", (canvas.cropRect?.width ?? 0) <= 600 && (canvas.cropRect?.height ?? 0) <= 400)

// Dragging outside the frame starts a fresh one.
canvas.resetCropFrame(nil)
drag(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 400, y: 300))
check("Rahmen lässt sich neu aufziehen", canvas.cropRect != nil)

// Escape leaves crop mode without touching the image.
canvas.cancelCrop(nil)
check("Abbrechen verlässt den Crop-Modus", canvas.cropRect == nil && canvas.tool == .select)
check("Abbrechen lässt das Bild unangetastet", canvas.doc.size == CGSize(width: 600, height: 400))

// Applying an untouched full frame is a no-op rather than a pointless undo step.
canvas.tool = .crop
canvas.applyCrop(nil)
check("Vollbild-Rahmen schneidet nichts ab", canvas.doc.size == CGSize(width: 600, height: 400))

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
check("Crop-Overlay rendert", true)

// Bottom edge dragged up past the top edge: height collapses to zero.
drag(from: CGPoint(x: 300, y: 0), to: CGPoint(x: 300, y: 400))
renderCanvas()
check("Flachgezogener Rahmen rendert", true)

// First pixel of a fresh frame: width and height are both zero.
canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 100, y: 100)))
renderCanvas()
canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 100, y: 100)))
check("Punktförmiger Rahmen rendert", true)

// Frame dragged completely off the image.
canvas.resetCropFrame(nil)
drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 5, y: 5))
renderCanvas()
check("Winziger Rahmen rendert", true)

// A frame that no longer overlaps the image at all -- what is left over when the
// image shrinks underneath an existing frame.
canvas.tool = .crop
canvas.debugSetCropRect(CGRect(x: 900, y: 900, width: 200, height: 150))
renderCanvas()
check("Rahmen ausserhalb des Bildes rendert", true)

// The real crop.
canvas.tool = .select
canvas.tool = .crop
drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 50))
drag(from: CGPoint(x: 600, y: 400), to: CGPoint(x: 450, y: 350))
canvas.applyCrop(nil)
check("Zuschneiden ändert die Bildgröße", canvas.doc.size == CGSize(width: 400, height: 300))
check("Nach dem Zuschneiden ist Auswahl aktiv", canvas.tool == .select)
check("Crop-Leiste verschwindet wieder", canvas.cropRect == nil)
canvas.undoAction(nil)
check("Zuschneiden ist widerrufbar", canvas.doc.size == CGSize(width: 600, height: 400))

// Undo and redo while the crop tool is still active change the image under the
// frame. That is how the frame ended up outside the image and crashed drawing.
canvas.tool = .crop
canvas.redoAction(nil)
renderCanvas()
check("Redo im Crop-Modus rendert", canvas.doc.size == CGSize(width: 400, height: 300))
check("Rahmen bleibt im geschrumpften Bild",
      (canvas.cropRect ?? .zero).maxX <= 400.5 && (canvas.cropRect ?? .zero).maxY <= 300.5)
canvas.undoAction(nil)
renderCanvas()
check("Undo im Crop-Modus rendert", canvas.doc.size == CGSize(width: 600, height: 400))
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
check("Canvas rendert Bild und Objekte (\(distinctColours.count) Farben)", distinctColours.count >= 3)

// Export from the live canvas keeps full resolution.
if let png = canvas.doc.pngData(), let rep = NSBitmapImageRep(data: png) {
    check("Export aus dem Fenster in Originalauflösung",
          rep.pixelsWide == 600 && rep.pixelsHigh == 400)
} else {
    check("Export aus dem Fenster in Originalauflösung", false)
}

print(failures == 0 ? "\nALLE TESTS BESTANDEN" : "\n\(failures) TESTS FEHLGESCHLAGEN")
exit(failures == 0 ? 0 : 1)
