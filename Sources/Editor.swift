import AppKit

let kritzelPalette: [NSColor] = [
    NSColor(srgbRed: 0.90, green: 0.13, blue: 0.13, alpha: 1),  // rot
    NSColor(srgbRed: 0.97, green: 0.55, blue: 0.05, alpha: 1),  // orange
    NSColor(srgbRed: 0.98, green: 0.83, blue: 0.10, alpha: 1),  // gelb
    NSColor(srgbRed: 0.16, green: 0.68, blue: 0.30, alpha: 1),  // gruen
    NSColor(srgbRed: 0.11, green: 0.45, blue: 0.90, alpha: 1),  // blau
    NSColor(srgbRed: 0.56, green: 0.24, blue: 0.78, alpha: 1),  // violett
    NSColor.black,
    NSColor.white
]

func colorSwatch(_ color: NSColor, size: CGFloat = 15) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    color.setFill()
    NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), xRadius: 3, yRadius: 3).fill()
    NSColor.black.withAlphaComponent(0.3).setStroke()
    let outline = NSBezierPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: size - 1, height: size - 1),
                               xRadius: 3, yRadius: 3)
    outline.lineWidth = 1
    outline.stroke()
    img.unlockFocus()
    img.isTemplate = false
    return img
}

/// One window: toolbar on top, canvas below.
final class EditorController: NSWindowController {

    let canvas: CanvasView
    private var toolSegments: NSSegmentedControl!
    private var colorSegments: NSSegmentedControl!
    private var widthSlider: NSSlider!
    private var fontPopup: NSPopUpButton!

    init(doc: Document) {
        canvas = CanvasView(doc: doc)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 720, height: 420)
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        buildInterface()
        updateTitle()
        canvas.onDocumentChanged = { [weak self] in self?.updateTitle() }
        canvas.onToolChanged = { [weak self] t in self?.toolSegments.selectedSegment = t.rawValue }
        canvas.onOpenImage = { img, name in AppState.shared.newWindow(image: img, name: name) }
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildInterface() {
        guard let window = window, let content = window.contentView else { return }
        let barHeight: CGFloat = 44

        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: content.bounds.height - barHeight,
                                                   width: content.bounds.width, height: barHeight))
        bar.material = .titlebar
        bar.blendingMode = .withinWindow
        bar.state = .active
        bar.autoresizingMask = [.width, .minYMargin]

        toolSegments = NSSegmentedControl(frame: .zero)
        toolSegments.segmentCount = ToolKind.allCases.count
        toolSegments.segmentStyle = .texturedRounded
        toolSegments.trackingMode = .selectOne
        for (i, t) in ToolKind.allCases.enumerated() {
            let image = NSImage(systemSymbolName: t.symbolName, accessibilityDescription: t.label)
            toolSegments.setImage(image, forSegment: i)
            toolSegments.setWidth(34, forSegment: i)
            toolSegments.setToolTip("\(t.label) (\(i + 1))", forSegment: i)
        }
        toolSegments.selectedSegment = 0
        toolSegments.target = self
        toolSegments.action = #selector(toolChanged(_:))

        colorSegments = NSSegmentedControl(frame: .zero)
        colorSegments.segmentCount = kritzelPalette.count
        colorSegments.segmentStyle = .texturedRounded
        colorSegments.trackingMode = .selectOne
        for (i, c) in kritzelPalette.enumerated() {
            colorSegments.setImage(colorSwatch(c), forSegment: i)
            colorSegments.setWidth(26, forSegment: i)
        }
        colorSegments.selectedSegment = 0
        colorSegments.target = self
        colorSegments.action = #selector(colorChanged(_:))

        widthSlider = NSSlider(value: 5, minValue: 1, maxValue: 24, target: self,
                               action: #selector(widthChanged(_:)))
        widthSlider.isContinuous = true
        widthSlider.toolTip = "Strichstärke"
        widthSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for size in [16, 22, 32, 44, 64, 96] {
            fontPopup.addItem(withTitle: "\(size) pt")
            fontPopup.lastItem?.tag = size
        }
        fontPopup.selectItem(withTitle: "32 pt")
        fontPopup.target = self
        fontPopup.action = #selector(fontSizeChanged(_:))
        fontPopup.toolTip = "Textgröße"

        let widthLabel = NSTextField(labelWithString: "Stärke")
        widthLabel.font = NSFont.systemFont(ofSize: 11)
        widthLabel.textColor = .secondaryLabelColor

        let copyButton = NSButton(title: "Kopieren", target: canvas,
                                  action: #selector(CanvasView.copyImageToPasteboard(_:)))
        copyButton.bezelStyle = .rounded
        let saveButton = NSButton(title: "Sichern…", target: canvas,
                                  action: #selector(CanvasView.saveImageAs(_:)))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = ""

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [toolSegments, colorSegments, widthLabel, widthSlider,
                                        fontPopup, spacer, copyButton, saveButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            widthSlider.widthAnchor.constraint(equalToConstant: 90)
        ])

        canvas.frame = NSRect(x: 0, y: 0, width: content.bounds.width,
                              height: content.bounds.height - barHeight)
        canvas.autoresizingMask = [.width, .height]

        content.addSubview(canvas)
        content.addSubview(bar)
        window.makeFirstResponder(canvas)
    }

    func updateTitle() {
        let dims = "\(Int(canvas.doc.size.width)) × \(Int(canvas.doc.size.height))"
        let name = canvas.doc.sourceName ?? "Ohne Titel"
        window?.title = "Kritzel — \(name)  ·  \(dims)"
    }

    // MARK: - Toolbar actions

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        canvas.commitTextEditing()
        if let t = ToolKind(rawValue: sender.selectedSegment) { canvas.tool = t }
        window?.makeFirstResponder(canvas)
    }

    @objc private func colorChanged(_ sender: NSSegmentedControl) {
        let i = sender.selectedSegment
        if i >= 0 && i < kritzelPalette.count { canvas.color = kritzelPalette[i] }
        window?.makeFirstResponder(canvas)
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        canvas.lineWidth = CGFloat(sender.doubleValue)
    }

    @objc private func fontSizeChanged(_ sender: NSPopUpButton) {
        canvas.fontSize = CGFloat(sender.selectedItem?.tag ?? 32)
        window?.makeFirstResponder(canvas)
    }
}

extension EditorController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        AppState.shared.forget(self)
    }
}
