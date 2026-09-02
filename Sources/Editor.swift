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

/// Palette colours are compared by value, not by identity: an annotation carries
/// a copy, and a cloned one may not be the same object any more.
func sameColor(_ a: NSColor, _ b: NSColor) -> Bool {
    guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
    return abs(x.redComponent - y.redComponent) < 0.02
        && abs(x.greenComponent - y.greenComponent) < 0.02
        && abs(x.blueComponent - y.blueComponent) < 0.02
}

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
    private var toolBar: NSVisualEffectView!
    private var cropBar: NSVisualEffectView!
    private var cropWidthField: NSTextField!
    private var cropHeightField: NSTextField!
    private let barHeight: CGFloat = 44
    private let cropBarHeight: CGFloat = 38

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
        canvas.onCropChanged = { [weak self] rect in self?.cropFrameChanged(rect) }
        canvas.onSelectionChanged = { [weak self] a in self?.showStyle(of: a) }
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeBar() -> NSVisualEffectView {
        let bar = NSVisualEffectView(frame: .zero)
        bar.material = .titlebar
        bar.blendingMode = .withinWindow
        bar.state = .active
        return bar
    }

    private func buildInterface() {
        guard let window = window, let content = window.contentView else { return }
        let bar = makeBar()
        toolBar = bar

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

        buildCropBar()

        content.addSubview(canvas)
        content.addSubview(bar)
        content.addSubview(cropBar)
        layoutContent()
        window.makeFirstResponder(canvas)
    }

    /// Second row, visible only while the crop tool is active.
    private func buildCropBar() {
        cropBar = makeBar()
        cropBar.isHidden = true

        let title = NSTextField(labelWithString: "Ausschnitt")
        title.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        title.textColor = .secondaryLabelColor

        cropWidthField = NSTextField(string: "")
        cropHeightField = NSTextField(string: "")
        for field in [cropWidthField!, cropHeightField!] {
            field.alignment = .right
            field.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            field.target = self
            field.action = #selector(cropSizeTyped(_:))
            field.widthAnchor.constraint(equalToConstant: 62).isActive = true
        }
        let times = NSTextField(labelWithString: "×")
        times.textColor = .secondaryLabelColor
        let unit = NSTextField(labelWithString: "px")
        unit.font = NSFont.systemFont(ofSize: 11)
        unit.textColor = .secondaryLabelColor

        let resetButton = NSButton(title: "Ganzes Bild", target: canvas,
                                   action: #selector(CanvasView.resetCropFrame(_:)))
        resetButton.bezelStyle = .rounded

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let cancelButton = NSButton(title: "Abbrechen", target: canvas,
                                    action: #selector(CanvasView.cancelCrop(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let applyButton = NSButton(title: "Anwenden", target: canvas,
                                   action: #selector(CanvasView.applyCrop(_:)))
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [title, cropWidthField, times, cropHeightField, unit,
                                        resetButton, spacer, cancelButton, applyButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        cropBar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cropBar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: cropBar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: cropBar.centerYAnchor)
        ])
    }

    /// Bars sit on top, the canvas takes whatever is left.
    private func layoutContent() {
        guard let content = window?.contentView else { return }
        let w = content.bounds.width, h = content.bounds.height
        toolBar.frame = NSRect(x: 0, y: h - barHeight, width: w, height: barHeight)
        cropBar.frame = NSRect(x: 0, y: h - barHeight - cropBarHeight, width: w, height: cropBarHeight)
        let used = barHeight + (cropBar.isHidden ? 0 : cropBarHeight)
        canvas.frame = NSRect(x: 0, y: 0, width: w, height: max(0, h - used))
    }

    private func cropFrameChanged(_ rect: CGRect?) {
        let shouldShow = rect != nil
        if cropBar.isHidden == shouldShow {
            cropBar.isHidden = !shouldShow
            layoutContent()
        }
        guard let r = rect else { return }
        let editing = window?.firstResponder is NSText
        if !editing {
            cropWidthField.stringValue = String(Int(r.width.rounded()))
            cropHeightField.stringValue = String(Int(r.height.rounded()))
        }
    }

    @objc private func cropSizeTyped(_ sender: Any?) {
        let w = Double(cropWidthField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        let h = Double(cropHeightField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        guard w > 0, h > 0 else { NSSound.beep(); return }
        canvas.setCropSize(width: CGFloat(w), height: CGFloat(h))
    }

    func updateTitle() {
        let dims = "\(Int(canvas.doc.size.width)) × \(Int(canvas.doc.size.height))"
        let name = canvas.doc.sourceName ?? "Ohne Titel"
        window?.title = "Kritzel — \(name)  ·  \(dims)"
    }

    // MARK: - Keeping the controls in step with the selection

    /// Selecting an object puts its own colour, width and text size into the toolbar.
    private func showStyle(of annotation: Annotation?) {
        guard let a = annotation else { return }
        if let i = kritzelPalette.firstIndex(where: { sameColor($0, a.color) }) {
            colorSegments.selectedSegment = i
        }
        widthSlider.doubleValue = Double(min(max(a.lineWidth, CGFloat(widthSlider.minValue)),
                                             CGFloat(widthSlider.maxValue)))
        if let text = a as? TextAnnotation { showFontSize(text.fontSize) }
    }

    /// Text objects scaled by their handle end up at sizes the menu does not list,
    /// so an entry for the actual value is added on the fly.
    private func showFontSize(_ size: CGFloat) {
        let value = max(1, Int(size.rounded()))
        if let existing = fontPopup.itemArray.first(where: {
               $0.tag == value && $0.representedObject as? String != "custom" }) {
            fontPopup.select(existing)
            return
        }
        if let index = fontPopup.itemArray.firstIndex(where: { $0.representedObject as? String == "custom" }) {
            fontPopup.removeItem(at: index)
        }
        fontPopup.insertItem(withTitle: "\(value) pt", at: 0)
        if let item = fontPopup.item(at: 0) {
            item.tag = value
            item.representedObject = "custom"
        }
        fontPopup.selectItem(at: 0)
    }

    /// Reads back what the controls currently show, for tests.
    func debugControlState() -> (colorIndex: Int, width: Double, fontSize: Int) {
        return (colorSegments.selectedSegment, widthSlider.doubleValue,
                fontPopup.selectedItem?.tag ?? 0)
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

    func windowDidResize(_ notification: Notification) {
        layoutContent()
    }
}
