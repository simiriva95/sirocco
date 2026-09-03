import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let store = MetricsStore()
    let terminator = ProcessTerminator()
    private var sampler: Sampler?
    private var statusItem: StatusItemController?
    private var observers: [any NSObjectProtocol] = []
    private var popoverVisible = false
    private var screenAsleep = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let sampler = Sampler(store: store)
        self.sampler = sampler
        let statusItem = StatusItemController(store: store, settings: settings, terminator: terminator)
        statusItem.onPopoverVisibility = { [weak self] visible in
            self?.popoverVisible = visible
            self?.pushDemand()
        }
        self.statusItem = statusItem

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

    private func pushDemand() {
        let demand = SamplingDemand(
            interests: popoverVisible ? [.systemOverview, .processes] : [.systemOverview],
            popoverVisible: popoverVisible, screenAsleep: screenAsleep, thermalState: store.thermalState)
        Task { [sampler] in await sampler?.setDemand(demand) }
    }

    /// Development-only switches, read once. SIROCCO_LOG_SELF prints our own cost per tick
    /// (README numbers); SIROCCO_POPOVER=cycle|open drives the popover for leak soaks / steady-state cost.
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
    }
}
