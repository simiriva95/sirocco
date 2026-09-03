import AppKit
import SwiftUI
import Observation

/// Owns the `NSStatusItem` and the popover. Pure AppKit on purpose: `MenuBarExtra` cannot
/// avoid activating the app, cannot expose the button frame, and mishandles Esc/on-blur.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: MetricsStore
    private let settings: AppSettings
    private let terminator: ProcessTerminator
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var lastModel: MenuBarIconModel?
    private var escapeMonitor: Any?

    var onPopoverVisibility: ((Bool) -> Void)?

    init(store: MetricsStore, settings: AppSettings, terminator: ProcessTerminator) {
        self.store = store
        self.settings = settings
        self.terminator = terminator
        super.init()

        item.button?.target = self
        item.button?.action = #selector(buttonClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel(String(localized: "Sirocco system monitor"))
        item.autosaveName = "it.simoneriva.sirocco.status"

        popover.behavior = .transient
        popover.delegate = self
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let hosting = NSHostingController(rootView: PopoverView(close: { [weak self] in self?.close() })
            .environment(store).environment(settings).environment(terminator))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting

        observe()
    }

    /// Re-armed after every change; `withObservationTracking` fires once per registration,
    /// so no observers pile up across ticks.
    private func observe() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }

    private func render() {
        let history: [Double] = switch settings.iconContent {
        case .thermal, .cpu: store.cpuHistory.elements
        case .memory: store.memoryHistory.elements
        }
        let model = MenuBarIconRenderer.model(history: history, thermal: store.thermalState, content: settings.iconContent)
        let cpuText = store.latest?.cpu.map { "\(Int(($0.total * 100).rounded()))%" } ?? "—"
        item.button?.setAccessibilityValue(String(localized: "Thermal \(store.thermalState.localizedName), CPU \(cpuText)"))
        item.button?.toolTip = String(localized: "Thermal \(store.thermalState.localizedName), CPU \(cpuText)")
        guard model != lastModel else { return }   // redraw only on perceptible change
        lastModel = model
        item.button?.image = MenuBarIconRenderer.image(for: model)
    }

    @objc private func buttonClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { toggle() }
    }

    func toggle() {
        popover.isShown ? close() : open()
    }

    private func open() {
        guard let button = item.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        onPopoverVisibility?(true)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Esc
            MainActor.assumeIsolated { self?.close() }
            return nil
        }
    }

    func close() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        onPopoverVisibility?(false)
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit Sirocco"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil   // back to popover behaviour on the next left click
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate()
    }
}
