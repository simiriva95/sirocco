import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let store = MetricsStore()
    let terminator = ProcessTerminator()
    private(set) lazy var mainModel = MainWindowModel(store: store, terminator: terminator)
    private(set) lazy var mainWindow = MainWindowController(model: mainModel, store: store, terminator: terminator)
    private var sampler: Sampler?
    private var statusItem: StatusItemController?
    private var hotKey: GlobalHotKey?
    private var observers: [any NSObjectProtocol] = []
    private var popoverVisible = false
    private var windowVisible = false
    private var screenAsleep = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let sampler = Sampler(store: store)
        self.sampler = sampler
        let statusItem = StatusItemController(store: store, settings: settings, terminator: terminator,
                                              openMainWindow: { [weak self] in self?.showMainWindow() })
        statusItem.onPopoverVisibility = { [weak self] visible in
            self?.popoverVisible = visible
            self?.pushDemand()
        }
        self.statusItem = statusItem
        mainWindow.onVisibility = { [weak self] visible in
            self?.windowVisible = visible
            self?.pushDemand()
        }
        hotKey = GlobalHotKey { [weak self] in self?.statusItem?.toggle() }
        mainModel.onTabChange = { [weak self] in self?.pushDemand() }

        let center = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.screenAsleep = asleep
                    self?.pushDemand()
                }
            })
        }

        Task { await sampler.start() }
        applyDebugFlags()
    }

    func showMainWindow() {
        mainWindow.show()
    }

    /// Re-evaluated whenever a surface appears/disappears or the window's tab changes.
    func pushDemand() {
        var interests: Set<SamplingInterest> = [.systemOverview]
        if popoverVisible { interests.insert(.processes) }
        if windowVisible && mainModel.tab == .processes { interests.formUnion([.processes, .processDetails]) }
        if windowVisible && mainModel.tab == .sensors { interests.insert(.sensors) }
        let demand = SamplingDemand(interests: interests, popoverVisible: popoverVisible, windowVisible: windowVisible,
                                    screenAsleep: screenAsleep, thermalState: store.thermalState)
        Task { [sampler] in await sampler?.setDemand(demand) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()   // Dock icon click while the window is open
        return false
    }

    /// Development-only switches, read once. SIROCCO_LOG_SELF prints our own cost per tick
    /// (README numbers); SIROCCO_POPOVER=cycle|open drives the popover; SIROCCO_WINDOW=1 opens the main window.
    private func applyDebugFlags() {
        let env = ProcessInfo.processInfo.environment
        store.logSelf = env["SIROCCO_LOG_SELF"] != nil
        switch env["SIROCCO_POPOVER"] {   // "cycle": open/close every 2 s (leak soak); "open": open once (steady-state cost)
        case "cycle":
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    self?.statusItem?.toggle()
                }
            }
        case "open":
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.statusItem?.toggle()
            }
        default: break
        }
        if let tab = env["SIROCCO_WINDOW"] {   // "1" or a tab name: processes|performance|…
            if let index = ["overview", "processes", "performance", "sensors", "startup"].firstIndex(of: tab) { mainModel.tab = MainTab(rawValue: index)! }
            showMainWindow()
        }
    }
}
