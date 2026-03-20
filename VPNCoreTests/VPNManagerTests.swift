import XCTest
@testable import VPNCore

final class VPNManagerTests: XCTestCase {
    func testConnectBlockedWhileAuthenticating() {
        // CONN-01: connect() throws .alreadyAuthenticating when another config is in .authenticating state
        XCTFail("Not implemented -- Wave 2")
    }

    func testConnectSetsAuthenticatingState() {
        // CONN-01: connect() sets connections[config.name] = .authenticating immediately
        XCTFail("Not implemented -- Wave 2")
    }

    func testRandomHexLength() {
        // CONN-02: randomHex(byteCount: 12) returns exactly 24 hex characters
        XCTFail("Not implemented -- Wave 2")
    }

    func testURLEncodingPlusChar() {
        // CONN-02: urlEncodeSAML encodes '+' as '%2B' (not left as '+')
        XCTFail("Not implemented -- Wave 2")
    }

    func testDummyCredsFileDeletedOnExit() {
        // CONN-06: after connect() returns (success or failure), dummy creds temp file no longer exists
        XCTFail("Not implemented -- Wave 2")
    }

    func testRealCredsFileDeleted() {
        // CONN-06: after connect() completes, real creds temp file no longer exists
        XCTFail("Not implemented -- Wave 2")
    }

    func testDisconnectSendsSignal() {
        // CONN-07: disconnect() sends SIGTERM to the real openvpn PID via sudo kill
        XCTFail("Not implemented -- Wave 3")
    }

    func testLogFileCreated() {
        // CONN-08: after connect(), a log file exists at ~/Library/Logs/AWSVPNClient/<name>.log
        XCTFail("Not implemented -- Wave 2")
    }
}
