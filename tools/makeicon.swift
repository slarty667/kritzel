import AppKit

// Renders the app icon at 1024 px and writes it as PNG.
let side: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: side, height: side)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset: CGFloat = 40
let body = NSBezierPath(roundedRect: CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset),
                        xRadius: 200, yRadius: 200)
let gradient = NSGradient(starting: NSColor(srgbRed: 0.99, green: 0.99, blue: 1.0, alpha: 1),
                          ending: NSColor(srgbRed: 0.87, green: 0.89, blue: 0.93, alpha: 1))!
gradient.draw(in: body, angle: -90)

NSGraphicsContext.current?.compositingOperation = .multiply
NSColor(srgbRed: 0.99, green: 0.85, blue: 0.15, alpha: 0.75).setStroke()
let marker = NSBezierPath()
marker.move(to: CGPoint(x: 215, y: 400))
marker.line(to: CGPoint(x: 800, y: 430))
marker.lineWidth = 170
marker.lineCapStyle = .round
marker.stroke()
NSGraphicsContext.current?.compositingOperation = .sourceOver

let red = NSColor(srgbRed: 0.88, green: 0.13, blue: 0.13, alpha: 1)
red.setStroke()
red.setFill()
let start = CGPoint(x: 240, y: 250)
let tip = CGPoint(x: 790, y: 760)
let angle = atan2(tip.y - start.y, tip.x - start.x)
let headLen: CGFloat = 250
let headHalf: CGFloat = 128
let shaft = NSBezierPath()
shaft.move(to: start)
shaft.line(to: CGPoint(x: tip.x - cos(angle) * headLen * 0.8, y: tip.y - sin(angle) * headLen * 0.8))
shaft.lineWidth = 76
shaft.lineCapStyle = .round
shaft.stroke()
let base = CGPoint(x: tip.x - cos(angle) * headLen, y: tip.y - sin(angle) * headLen)
let nx = -sin(angle), ny = cos(angle)
let head = NSBezierPath()
head.move(to: tip)
head.line(to: CGPoint(x: base.x + nx * headHalf, y: base.y + ny * headHalf))
head.line(to: CGPoint(x: base.x - nx * headHalf, y: base.y - ny * headHalf))
head.close()
head.fill()

NSColor.black.withAlphaComponent(0.12).setStroke()
let rim = NSBezierPath(roundedRect: CGRect(x: inset + 2, y: inset + 2, width: side - 2 * inset - 4,
                                           height: side - 2 * inset - 4), xRadius: 198, yRadius: 198)
rim.lineWidth = 4
rim.stroke()

NSGraphicsContext.restoreGraphicsState()
let data = rep.representation(using: .png, properties: [:])!
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! data.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
