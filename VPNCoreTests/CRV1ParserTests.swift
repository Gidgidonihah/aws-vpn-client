import XCTest
@testable import VPNCore

final class CRV1ParserTests: XCTestCase {
    // Standard CRV1 line matching real openvpn output.
    // Colon-split (0-indexed):
    //   0: AUTH_FAILED,CRV1
    //   1: R
    //   2: instance/profile
    //   3: b
    //   4: enc
    //   5: auth
    //   6: MYSID123         <- SID
    //   7: https            <- start of URL (but URL reconstructed via "https://" split)
    //   ...
    private let crv1Line = "AUTH_FAILED,CRV1:R:instance/profile:b:enc:auth:MYSID123:https://sso.example.com/saml?SAMLRequest=abc"

    func testExtractsURLFromCRV1Line() {
        let result = parseCRV1Line(crv1Line)
        XCTAssertNotNil(result, "parseCRV1Line must return non-nil for a valid CRV1 line")
        XCTAssertTrue(result?.url.hasPrefix("https://") == true, "URL must start with 'https://'")
        XCTAssertTrue(result?.url.contains("sso.example.com") == true, "URL must contain the host")
    }

    func testExtractsSIDFromCRV1Line() {
        let result = parseCRV1Line(crv1Line)
        XCTAssertEqual(result?.sid, "MYSID123", "SID must be colon-split field at index 6")
    }

    func testReturnsNilForLineWithoutCRV1() {
        let result = parseCRV1Line("normal log line with no CRV1 marker")
        XCTAssertNil(result, "Non-CRV1 line must return nil")
    }

    func testHandlesURLWithMultipleColons() {
        // URL containing port number ("https://host:8443/path") has extra colons
        // SID extraction must still use field index 6 correctly
        let lineWithPort = "AUTH_FAILED,CRV1:R:instance/profile:b:enc:auth:MYSID456:https://sso.example.com:8443/saml"
        let result = parseCRV1Line(lineWithPort)
        XCTAssertEqual(result?.sid, "MYSID456", "SID must be correct even when URL has extra colons")
        XCTAssertTrue(result?.url.hasPrefix("https://") == true, "URL must start with https://")
    }
}
