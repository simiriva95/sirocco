import AppKit

/// Human name, bundle id and icon for a process. Resolved once per `ProcessID`, pruned on
/// every tick against the live pid set, so the cache can never outgrow the process table.
@MainActor
final class ProcessIdentityCache {
    struct Identity {
        var name: String
        var bundleIdentifier: String?
        var icon: NSImage?
    }

    private var cache: [ProcessID: Identity] = [:]
    private let genericIcon = NSWorkspace.shared.icon(for: .unixExecutable)

    func identity(for sample: ProcessSample) -> Identity {
        if let cached = cache[sample.id] { return cached }
        let resolved = resolve(pid: sample.pid, command: sample.command)
        cache[sample.id] = resolved
        return resolved
    }

    func prune(alive: Set<ProcessID>) {
        cache = cache.filter { alive.contains($0.key) }
    }

    private func resolve(pid: Int32, command: String) -> Identity {
        if let app = NSRunningApplication(processIdentifier: pid) {
            return Identity(name: app.localizedName ?? command, bundleIdentifier: app.bundleIdentifier,
                            icon: app.icon ?? genericIcon)
        }
        guard let path = ProcessEnumerator.path(pid: pid) else {
            return Identity(name: command, bundleIdentifier: nil, icon: genericIcon)
        }
        let name = (path as NSString).lastPathComponent
        // Helpers live inside a bundle: …/Foo.app/Contents/Frameworks/Foo Helper.app/Contents/MacOS/Foo Helper
        if let range = path.range(of: ".app/") {
            let bundlePath = String(path[..<range.lowerBound]) + ".app"
            let bundle = Bundle(path: bundlePath)
            return Identity(name: name, bundleIdentifier: bundle?.bundleIdentifier,
                            icon: NSWorkspace.shared.icon(forFile: bundlePath))
        }
        return Identity(name: name, bundleIdentifier: nil, icon: genericIcon)
    }
}
