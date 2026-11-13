import AppKit
import UniformTypeIdentifiers

// MARK: - Application delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var didLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // AppKit turns an uncaught exception during drawing into a bare trap with
        // no reason attached. Write it down before that happens.
        NSSetUncaughtExceptionHandler { exception in
            let text = "\(Date()) \(exception.name.rawValue): \(exception.reason ?? "")\n"
                + exception.callStackSymbols.joined(separator: "\n") + "\n\n"
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/Kritzel-exceptions.log")
            if let data = text.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? data.write(to: url)
                }
            }
        }
        buildMenu()
        if !AppState.shared.newFromClipboard() {
            AppState.shared.newWindow(image: nil, name: nil)
        }
        didLaunch = true
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    /// Reactivating the app with no windows open picks up whatever is on the clipboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && didLaunch {
            if !AppState.shared.newFromClipboard() {
                AppState.shared.newWindow(image: nil, name: nil)
            }
        }
        return true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        guard let img = NSImage(contentsOfFile: filename) else { return false }
        AppState.shared.newWindow(image: img, name: (filename as NSString).lastPathComponent)
        return true
    }

    // MARK: Actions

    @objc func newBlankDocument(_ sender: Any?) {
        AppState.shared.newWindow(image: nil, name: nil)
    }

    @objc func paste(_ sender: Any?) {
        if !AppState.shared.newFromClipboard() {
            let alert = NSAlert()
            alert.messageText = L("No image on the clipboard")
            alert.informativeText = L("Copy an image first, then press ⌘V again.")
            alert.runModal()
        }
    }

    @objc func openImageFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                if let img = NSImage(contentsOf: url) {
                    AppState.shared.newWindow(image: img, name: url.lastPathComponent)
                }
            }
        }
    }

    @objc func captureScreenshot(_ sender: Any?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-c"]
        task.terminationHandler = { _ in
            DispatchQueue.main.async {
                if AppState.shared.newFromClipboard() {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        do { try task.run() } catch { NSSound.beep() }
    }

    @objc func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Kritzel"
        alert.informativeText = L("about.text")
        alert.runModal()
    }

    // MARK: Menu

    private func item(_ title: String, _ action: Selector?, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { mi.keyEquivalentModifierMask = mods }
        mi.target = target
        return mi
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(item(L("About Kritzel"), #selector(showAbout(_:)), "", [], target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("Hide Kritzel"), #selector(NSApplication.hide(_:)), "h"))
        let hideOthers = item(L("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h",
                              [.command, .option])
        appMenu.addItem(hideOthers)
        appMenu.addItem(item(L("Show All"), #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("Quit Kritzel"), #selector(NSApplication.terminate(_:)), "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L("File"))
        fileMenu.addItem(item(L("New Blank Canvas"), #selector(newBlankDocument(_:)), "n", target: self))
        fileMenu.addItem(item(L("Open…"), #selector(openImageFile(_:)), "o", target: self))
        fileMenu.addItem(item(L("Screen Selection…"), #selector(captureScreenshot(_:)), "4",
                              [.command, .shift], target: self))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item(L("Save…"), #selector(CanvasView.saveImageAs(_:)), "s"))
        fileMenu.addItem(item(L("Export…"), #selector(CanvasView.saveImageAs(_:)), "e"))
        fileMenu.addItem(item(L("Copy as Image"), #selector(CanvasView.copyImageToPasteboard(_:)), "c",
                              [.command, .shift]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item(L("Close Window"), #selector(NSWindow.performClose(_:)), "w"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // Edit menu
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("Edit"))
        editMenu.addItem(item(L("Undo"), #selector(CanvasView.undoAction(_:)), "z"))
        editMenu.addItem(item(L("Redo"), #selector(CanvasView.redoAction(_:)), "z", [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(item(L("Copy"), #selector(NSText.copy(_:)), "c"))
        editMenu.addItem(item(L("Paste"), #selector(NSText.paste(_:)), "v"))
        editMenu.addItem(item(L("Delete Selection"), #selector(CanvasView.deleteSelection(_:))))
        editMenu.addItem(item(L("Bring to Front"), #selector(CanvasView.bringToFront(_:)), "f",
                              [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(item(L("Apply Crop"), #selector(CanvasView.applyCrop(_:))))
        editMenu.addItem(item(L("Reset Crop to Whole Image"), #selector(CanvasView.resetCropFrame(_:))))
        editMenu.addItem(item(L("Cancel Crop"), #selector(CanvasView.cancelCrop(_:))))
        editMenu.addItem(item(L("Resize Image…"), #selector(CanvasView.resizeImageDialog(_:)), "i",
                              [.command, .option]))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // View menu
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: L("View"))
        viewMenu.addItem(item(L("Zoom In"), #selector(CanvasView.zoomIn(_:)), "+"))
        // Second, hidden binding: on a German keyboard plain "+" is its own key,
        // on a US one it needs Shift and the key reports "=".
        let zoomInAlt = item(L("Zoom In"), #selector(CanvasView.zoomIn(_:)), "=")
        zoomInAlt.isHidden = true
        zoomInAlt.allowsKeyEquivalentWhenHidden = true
        viewMenu.addItem(zoomInAlt)
        viewMenu.addItem(item(L("Zoom Out"), #selector(CanvasView.zoomOut(_:)), "-"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item(L("Zoom to Fit"), #selector(CanvasView.zoomToFit(_:)), "0"))
        viewMenu.addItem(item(L("Actual Size (100%)"), #selector(CanvasView.zoomActualSize(_:)), "1"))
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        // Window menu
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L("Window"))
        windowMenu.addItem(item(L("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(item(L("Zoom"), #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item(L("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:))))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}

// MARK: - Entry point

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let kritzelDelegate = AppDelegate()
application.delegate = kritzelDelegate
application.run()
