import AppKit
import SwiftUI

/// AppKit-owned main window hosting SwiftUI. Owning the NSWindow gives deterministic
/// open/close, and lets the app flip between `.accessory` (menu bar only, no Dock) and
/// `.regular` (Dock icon + main menu) exactly while the window is on screen.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let model: MainWindowModel
    var onVisibility: ((Bool) -> Void)?

    init(model: MainWindowModel, store: MetricsStore, terminator: ProcessTerminator, settings: AppSettings) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 660),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Sirocco"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 760, height: 420)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MainWindow")
        window.contentView = NSHostingView(rootView: MainWindowView()
            .environment(model).environment(store).environment(terminator).environment(settings))
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.setActivationPolicy(.regular)
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        onVisibility?(true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onVisibility?(false)
    }
}
