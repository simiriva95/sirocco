import XCTest
@testable import Sirocco

final class StartupTests: XCTestCase {
    func testPrintDisabledParsing() {
        let output = """
        disabled services = {
        \t"com.apple.CSCSupportd" => disabled
        \t"com.foo.agent" => true
        \t"com.bar.enabled" => enabled
        }
        """
        XCTAssertEqual(LaunchItems.disabledLabels(fromPrintDisabled: output), ["com.apple.CSCSupportd", "com.foo.agent"])
    }

    func testPlistToItem() {
        let plist: [String: Any] = ["Label": "com.foo.agent", "ProgramArguments": ["/usr/local/bin/foo", "--daemon"], "RunAtLoad": true]
        let item = LaunchItems.item(from: plist, path: "/Users/me/Library/LaunchAgents/com.foo.agent.plist", source: .userAgent, disabledLabels: ["com.foo.agent"])!
        XCTAssertEqual(item.program, "/usr/local/bin/foo")
        XCTAssertTrue(item.runAtLoad)
        XCTAssertFalse(item.enabled, "disabled via launchctl overrides the plist")
        XCTAssertTrue(item.canToggle)
        XCTAssertNil(LaunchItems.item(from: ["Program": "/bin/x"], path: "p", source: .systemDaemon, disabledLabels: []), "no Label → skip")
        XCTAssertFalse(LaunchItems.item(from: ["Label": "d"], path: "p", source: .systemDaemon, disabledLabels: [])!.canToggle)
    }
}
