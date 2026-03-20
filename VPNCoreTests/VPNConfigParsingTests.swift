import XCTest
@testable import VPNCore

final class VPNConfigParsingTests: XCTestCase {
    func testExtractsHostFromRemoteDirective() {
        // Input: "remote vpn.example.com 443\nproto udp\n..."
        // Expected: host == "vpn.example.com"
        XCTFail("Not implemented -- Wave 1")
    }

    func testExtractsPortFromRemoteDirective() {
        // Expected: port == "443"
        XCTFail("Not implemented -- Wave 1")
    }

    func testExtractsProtoFromProtoDirective() {
        // Expected: proto == "udp"
        XCTFail("Not implemented -- Wave 1")
    }

    func testStripsAuthUserPassDirective() {
        // "auth-user-pass" line must not appear in filtered output
        XCTFail("Not implemented -- Wave 1")
    }

    func testStripsAuthFederateDirective() {
        // "auth-federate" line must not appear in filtered output
        XCTFail("Not implemented -- Wave 1")
    }

    func testStripsAuthRetryInteractDirective() {
        // "auth-retry interact" stripped but "auth-retry none" kept
        XCTFail("Not implemented -- Wave 1")
    }

    func testStripsRemoteDirective() {
        // "remote ..." line stripped from filtered output
        XCTFail("Not implemented -- Wave 1")
    }

    func testKeepsNonStrippedLines() {
        // Lines like "cipher AES-256-GCM" must survive filtering
        XCTFail("Not implemented -- Wave 1")
    }

    func testThrowsOnMissingRemoteDirective() {
        // Config with no "remote" line should throw VPNError.configParseFailure
        XCTFail("Not implemented -- Wave 1")
    }
}
