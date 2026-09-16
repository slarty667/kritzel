import AppKit

// Renders a README screenshot off-screen: a neutral mock-up as the base image,
// annotated with every tool, shown inside the real editor window.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let grey = NSColor(srgbRed: 0.42, green: 0.45, blue: 0.5, alpha: 1)

func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor, radius: CGFloat = 3) {
    color.setFill()
    NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}

func label(_ text: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
           color: NSColor = NSColor(srgbRed: 0.15, green: 0.17, blue: 0.2, alpha: 1)) {
    (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color
    ])
}

// A plain, invented report page. No real brand, no real data.
let mockup = renderImage(width: 1180, height: 760) {
    NSColor.white.setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: 1180, height: 760)).fill()

    // Header strip
    bar(0, 690, 1180, 70, NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1), radius: 0)
    label("Quartalsübersicht", 40, 712, size: 22, weight: .semibold)
    label("Zeitraum 01.07. – 30.09.", 40, 696, size: 11, color: grey)
    bar(980, 706, 160, 32, NSColor(srgbRed: 0.88, green: 0.90, blue: 0.93, alpha: 1), radius: 6)
    label("Exportieren", 1010, 715, size: 12, color: grey)

    // Metric cards
    let cardTitles = ["Sitzungen", "Conversions", "Umsatz"]
    let cardValues = ["48.310", "1.204", "92.480 €"]
    for i in 0..<3 {
        let x = 40 + CGFloat(i) * 368
        bar(x, 520, 344, 130, NSColor(srgbRed: 0.97, green: 0.975, blue: 0.98, alpha: 1), radius: 8)
        label(cardTitles[i], x + 20, 610, size: 12, color: grey)
        label(cardValues[i], x + 20, 560, size: 34, weight: .semibold)
        label(i == 1 ? "+ 318 %" : "+ 4 %", x + 20, 538, size: 12,
              color: NSColor(srgbRed: 0.2, green: 0.6, blue: 0.35, alpha: 1))
    }

    // Table
    label("Top-Seiten", 40, 470, size: 14, weight: .semibold)
    let rows = [("/leistungen/analytics", "8.420", "312"),
                ("/blog/tracking-ohne-cookies", "6.115", "188"),
                ("/kontakt", "4.902", "504"),
                ("/blog/server-side-tagging", "3.744", "96")]
    bar(40, 430, 1100, 28, NSColor(srgbRed: 0.95, green: 0.96, blue: 0.97, alpha: 1), radius: 4)
    label("Seite", 56, 437, size: 11, weight: .medium, color: grey)
    label("Sitzungen", 800, 437, size: 11, weight: .medium, color: grey)
    label("Conversions", 960, 437, size: 11, weight: .medium, color: grey)
    for (i, row) in rows.enumerated() {
        let y = 392 - CGFloat(i) * 38
        label(row.0, 56, y, size: 13)
        label(row.1, 800, y, size: 13)
        label(row.2, 960, y, size: 13)
        bar(40, y - 10, 1100, 1, NSColor(srgbRed: 0.91, green: 0.92, blue: 0.93, alpha: 1), radius: 0)
    }

    // Footer with a contact address, the classic thing you pixelate away
    label("Rückfragen an", 40, 200, size: 12, color: grey)
    label("anna.beispiel@musterfirma.example", 40, 170, size: 16, weight: .medium)
    label("Telefon 089 1234567", 40, 146, size: 13, color: grey)
}!

let doc = Document(image: mockup)
// Trim the empty bottom margin so the screenshot is all content.
doc.crop(to: CGRect(x: 0, y: 110, width: 1180, height: 650))

// Rectangle around the suspicious number
let box = RectAnnotation()
box.color = kritzelPalette[0]; box.lineWidth = 5
box.p0 = CGPoint(x: 400, y: 418); box.p1 = CGPoint(x: 600, y: 490)
doc.annotations.append(box)

// Arrow pointing at it
let arrow = ArrowAnnotation()
arrow.color = kritzelPalette[0]; arrow.lineWidth = 6
arrow.start = CGPoint(x: 760, y: 220); arrow.end = CGPoint(x: 612, y: 430)
doc.annotations.append(arrow)

// Note next to the arrow
let note = TextAnnotation()
note.color = kritzelPalette[0]; note.fontSize = 34
note.text = "Das kann nicht stimmen"
note.origin = CGPoint(x: 700, y: 180)
doc.annotations.append(note)

// Marker over one table row
let marker = PenAnnotation()
marker.color = kritzelPalette[2]; marker.lineWidth = 6; marker.isMarker = true
marker.points = [CGPoint(x: 60, y: 249), CGPoint(x: 300, y: 249), CGPoint(x: 520, y: 250)]
doc.annotations.append(marker)

// Pixelate the contact address
let blur = PixelateAnnotation()
blur.p0 = CGPoint(x: 36, y: 28); blur.p1 = CGPoint(x: 460, y: 86)
doc.annotations.append(blur)

let controller = EditorController(doc: doc)
let window = controller.window!
window.setFrame(NSRect(x: 0, y: 0, width: 1240, height: 840), display: true)
let canvas = controller.canvas

// Select the rectangle so the handles are visible in the shot.
func windowPoint(_ p: CGPoint) -> CGPoint { canvas.convert(canvas.debugViewPoint(for: p), to: nil) }
func mouse(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
    return NSEvent.mouseEvent(with: type, location: windowPoint(p), modifierFlags: [],
                              timestamp: 0, windowNumber: window.windowNumber, context: nil,
                              eventNumber: 0, clickCount: 1, pressure: 1)!
}
canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 400, y: 454)))
canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 400, y: 454)))

let content = window.contentView!
content.layoutSubtreeIfNeeded()
content.display()
let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
content.cacheDisplay(in: content.bounds, to: rep)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("gerendert:", CommandLine.arguments[1])
