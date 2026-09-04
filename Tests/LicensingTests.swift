import XCTest
@testable import Sirocco

final class LicensingTests: XCTestCase {
    let install = Date(timeIntervalSince1970: 1_700_000_000)

    func testTrialCountdownAndExpiry() {
        XCTAssertEqual(TrialClock.state(installDate: install, lastSeen: install, now: install, unlocked: false), .trial(daysLeft: 14))
        XCTAssertEqual(TrialClock.state(installDate: install, lastSeen: install, now: install.addingTimeInterval(13.9 * 86_400), unlocked: false), .trial(daysLeft: 1))
        XCTAssertEqual(TrialClock.state(installDate: install, lastSeen: install, now: install.addingTimeInterval(14 * 86_400), unlocked: false), .expired)
        XCTAssertEqual(TrialClock.state(installDate: install, lastSeen: install, now: install.addingTimeInterval(400 * 86_400), unlocked: true), .unlocked)
    }

    func testClockRollbackDoesNotRevive() {
        let lastSeen = install.addingTimeInterval(20 * 86_400)
        XCTAssertEqual(TrialClock.state(installDate: install, lastSeen: lastSeen, now: install.addingTimeInterval(2 * 86_400), unlocked: false), .expired)
    }

    func testPasswordHashing() {
        let hash = Unlock.derive(password: "correct horse battery staple", iterations: 1_000)
        XCTAssertEqual(hash.count, 64)
        XCTAssertEqual(hash, Unlock.derive(password: "correct horse battery staple", iterations: 1_000), "deterministic")
        XCTAssertNotEqual(hash, Unlock.derive(password: "Correct horse battery staple", iterations: 1_000))
        XCTAssertFalse(Unlock.verify(password: "anything", expectedHex: ""), "no hash configured → nobody unlocks")
    }
}
