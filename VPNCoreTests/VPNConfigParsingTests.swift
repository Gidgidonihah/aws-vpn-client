import XCTest
@testable import VPNCore

final class VPNConfigParsingTests: XCTestCase {

    // MARK: - Extraction tests

    func testExtractsHostFromRemoteDirective() throws {
        let content = "remote vpn.example.com 443\nproto udp\ncipher AES-256-GCM\n"
        let parsed = try VPNConfigParser.parse(content: content)
        XCTAssertEqual(parsed.host, "vpn.example.com")
    }

    func testExtractsPortFromRemoteDirective() throws {
        let content = "remote vpn.example.com 443\nproto udp\ncipher AES-256-GCM\n"
        let parsed = try VPNConfigParser.parse(content: content)
        XCTAssertEqual(parsed.port, "443")
    }

    func testExtractsProtoFromProtoDirective() throws {
        let content = "remote vpn.example.com 443\nproto udp\ncipher AES-256-GCM\n"
        let parsed = try VPNConfigParser.parse(content: content)
        XCTAssertEqual(parsed.proto, "udp")
    }

    // MARK: - Filtering tests

    func testStripsAuthUserPassDirective() throws {
        let content = "remote vpn.example.com 443\nproto udp\nauth-user-pass /path\ncipher AES-256-GCM\n"
        let parsed = try VPNConfigParser.parse(content: content)
        XCTAssertFalse(parsed.filteredContent.contains("auth-user-pass"),
                       "filteredContent must not contain 'auth-user-pass'")
    }

    func testStripsAuthFederateDirective() throws {
        let content = "remote vpn.example.com 443\nproto udp\nauth-federate\ncipher AES-256-GCM\n"
        let parsed = try VPNConfigParser.parse(content: content)
        XCTAssertFalse(parsed.filteredContent.contains("auth-federate"),
                       "filteredContent must not contain 'auth-federate'")
    }

    func testStripsAuthRetryInteractDirective() throws {
        let content = "remote vpn.example.com 443\nproto udp\nauth-retry interact\nauth-retry none\ncipher AES-256-GCM\n"
        let parsed = try VPNConfigParser.parse(content: content)
        XCTAssertFalse(parsed.filteredContent.contains("auth-retry interact"),
                       "filteredContent must not contain 'auth-retry interact'")
        XCTAssertTrue(parsed.filteredContent.contains("auth-retry none"),
                      "filteredContent must keep 'auth-retry none'")
    }

    func testStripsRemoteDirective() throws {
        let content = "remote vpn.example.com 443\nproto udp\ncipher AES-256-GCM\n"
        let parsed = try VPNConfigParser.parse(content: content)
        XCTAssertFalse(parsed.filteredContent.contains("remote"),
                       "filteredContent must not contain 'remote'")
    }

    func testKeepsNonStrippedLines() throws {
        let content = "remote vpn.example.com 443\nproto udp\ncipher AES-256-GCM\ndev tun\n"
        let parsed = try VPNConfigParser.parse(content: content)
        XCTAssertTrue(parsed.filteredContent.contains("cipher AES-256-GCM"),
                      "filteredContent must keep 'cipher AES-256-GCM'")
        XCTAssertTrue(parsed.filteredContent.contains("dev tun"),
                      "filteredContent must keep 'dev tun'")
    }

    // MARK: - Error tests

    func testThrowsOnMissingRemoteDirective() {
        let content = "proto udp\ncipher AES-256-GCM\n"
        XCTAssertThrowsError(try VPNConfigParser.parse(content: content)) { error in
            guard case VPNError.configParseFailure = error else {
                XCTFail("Expected VPNError.configParseFailure, got \(error)")
                return
            }
        }
    }
}
