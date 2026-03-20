import XCTest
@testable import VPNCore

final class CRV1ParserTests: XCTestCase {
    func testExtractsURLFromCRV1Line() {
        // Input: "AUTH_FAILED,CRV1:R:...:...:...:...:sid123:https://sso.example.com/saml?SAMLRequest=..."
        // Expected URL starts with "https://"
        XCTFail("Not implemented -- Wave 1")
    }

    func testExtractsSIDFromCRV1Line() {
        // SID is colon-split field at zero-based index 6
        XCTFail("Not implemented -- Wave 1")
    }

    func testReturnsNilForLineWithoutCRV1() {
        // Non-CRV1 line returns nil
        XCTFail("Not implemented -- Wave 1")
    }

    func testHandlesURLWithMultipleColons() {
        // "https://..." contains colons -- SID extraction must use correct field index
        XCTFail("Not implemented -- Wave 1")
    }
}
