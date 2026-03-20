import XCTest
@testable import VPNCore

final class AuthHelpersTests: XCTestCase {

    // MARK: - randomHex

    func testRandomHexProduces24CharStringForByteCount12() {
        let hex = randomHex(byteCount: 12)
        XCTAssertEqual(hex.count, 24, "randomHex(byteCount: 12) must return exactly 24 characters")
    }

    func testRandomHexContainsOnlyHexCharacters() {
        let hex = randomHex(byteCount: 12)
        let allHex = hex.allSatisfy { "0123456789abcdef".contains($0) }
        XCTAssertTrue(allHex, "randomHex output must contain only lowercase hex characters [0-9a-f]")
    }

    func testRandomHexProducesUniqueValues() {
        let hex1 = randomHex(byteCount: 12)
        let hex2 = randomHex(byteCount: 12)
        XCTAssertNotEqual(hex1, hex2, "Two randomHex calls should produce different values")
    }

    // MARK: - urlEncodeSAML

    func testURLEncodingSAMLResponseEncodesPlus() {
        let encoded = urlEncodeSAML("abc+def")
        XCTAssertEqual(encoded, "abc%2Bdef", "'+' must be encoded as '%2B'")
    }

    func testURLEncodingSAMLResponseEncodesSpaceAsPercent20() {
        let encoded = urlEncodeSAML("abc def")
        XCTAssertEqual(encoded, "abc%20def", "space must be encoded as '%20'")
    }

    func testURLEncodingSAMLResponsePreservesAlphanumeric() {
        let encoded = urlEncodeSAML("abcABC123")
        XCTAssertEqual(encoded, "abcABC123", "alphanumeric characters must not be encoded")
    }

    // MARK: - Credential formatting

    func testDummyCredsFormat() {
        let creds = dummyCredentials()
        XCTAssertEqual(creds, "N/A\nACS::35001\n",
                       "dummyCredentials() must be exactly 'N/A\\nACS::35001\\n'")
    }

    func testRealCredsFormat() {
        let creds = realCredentials(sid: "abc", urlEncodedSAML: "xyz")
        XCTAssertEqual(creds, "N/A\nCRV1::abc::xyz\n",
                       "realCredentials must be exactly 'N/A\\nCRV1::<sid>::<urlEncoded>\\n'")
    }
}
