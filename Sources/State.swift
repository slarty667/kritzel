import AppKit

// MARK: - Window registry

final class AppState {
    static let shared = AppState()
    private(set) var controllers: [EditorController] = []

    @discardableResult
    func newWindow(image: NSImage?, name: String?) -> EditorController {
        let doc: Document
        if let img = image {
            doc = Document(image: img)
            doc.sourceName = name
        } else {
            doc = Document.blank()
        }
        let controller = EditorController(doc: doc)
        controllers.append(controller)
        controller.updateTitle()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        cascade(controller)
        return controller
    }

    private func cascade(_ controller: EditorController) {
        guard controllers.count > 1, let previous = controllers[controllers.count - 2].window,
              let window = controller.window else { return }
        let origin = previous.frame.origin
        window.setFrameTopLeftPoint(NSPoint(x: origin.x + 26,
                                            y: origin.y + previous.frame.height - 26))
    }

    func forget(_ controller: EditorController) {
        controllers.removeAll { $0 === controller }
    }

    /// Reads an image from the general pasteboard, if there is one.
    func clipboardImage() -> NSImage? {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first, let img = NSImage(contentsOf: url) {
            return img
        }
        if let imgs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = imgs.first, img.size.width > 0 {
            return img
        }
        return nil
    }

    @discardableResult
    func newFromClipboard() -> Bool {
        guard let img = clipboardImage() else { return false }
        newWindow(image: img, name: "Zwischenablage")
        return true
    }
}
