import Foundation

/// A launchd job description found on disk. Login items registered through the Background Task
/// Management database are not readable without root and are therefore not listed.
struct LaunchItem: Identifiable, Equatable, Sendable {
    enum Source: Sendable { case userAgent, systemAgent, systemDaemon }

    var id: String { path }
    var label: String
    var path: String
    var program: String?
    var runAtLoad: Bool
    var source: Source
    var enabled: Bool

    /// Only the user's own agents can be toggled without administrator rights.
    var canToggle: Bool { source == .userAgent }
}

enum LaunchItems {
    static let userAgentsDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    static let systemAgentsDirectory = URL(fileURLWithPath: "/Library/LaunchAgents")
    static let systemDaemonsDirectory = URL(fileURLWithPath: "/Library/LaunchDaemons")

    /// Pure: plist dictionary → item.
    static func item(from plist: [String: Any], path: String, source: LaunchItem.Source, disabledLabels: Set<String>) -> LaunchItem? {
        guard let label = plist["Label"] as? String else { return nil }
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        let disabledInPlist = plist["Disabled"] as? Bool ?? false
        return LaunchItem(label: label, path: path, program: program, runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
                          source: source, enabled: !disabledInPlist && !disabledLabels.contains(label))
    }

    /// Pure: parses `launchctl print-disabled <domain>` output, e.g. `"com.foo.agent" => disabled`.
    static func disabledLabels(fromPrintDisabled output: String) -> Set<String> {
        var result = Set<String>()
        for line in output.split(separator: "\n") {
            guard line.contains("=> disabled") || line.contains("=> true"),
                  let start = line.firstIndex(of: "\""), let end = line[line.index(after: start)...].firstIndex(of: "\"") else { continue }
            result.insert(String(line[line.index(after: start)..<end]))
        }
        return result
    }

    static func scan(directory: URL, source: LaunchItem.Source, disabledLabels: Set<String>) -> [LaunchItem] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "plist" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
            return item(from: plist, path: url.path, source: source, disabledLabels: disabledLabels)
        }
    }
}

/// Thin wrapper over the `launchctl` binary. Only user-domain operations: no privilege escalation.
struct LaunchctlClient: Sendable {
    var userDomain: String { "gui/\(getuid())" }

    func run(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func disabledLabels(system: Bool) -> Set<String> {
        LaunchItems.disabledLabels(fromPrintDisabled: run(["print-disabled", system ? "system" : userDomain]).output)
    }

    /// Disable = mark disabled (survives reboot) + unload now. Enable = the reverse.
    func setEnabled(_ enabled: Bool, item: LaunchItem) -> String? {
        guard item.canToggle else { return String(localized: "Only your own LaunchAgents can be changed without administrator rights.") }
        let target = "\(userDomain)/\(item.label)"
        if enabled {
            let enable = run(["enable", target])
            guard enable.status == 0 else { return enable.output }
            _ = run(["bootstrap", userDomain, item.path])   // may already be loaded: not an error worth showing
        } else {
            let disable = run(["disable", target])
            guard disable.status == 0 else { return disable.output }
            _ = run(["bootout", target])
        }
        return nil
    }
}
