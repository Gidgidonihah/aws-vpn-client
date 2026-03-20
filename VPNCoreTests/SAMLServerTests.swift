import XCTest
@testable import VPNCore

final class SAMLServerTests: XCTestCase {
    func testExtractSAMLResponseFromURLEncodedBody() {
        let body = "SAMLResponse=PHNhbWxwOlJlc3BvbnNl&RelayState=token"
        let result = SAMLServer.extractSAMLResponse(from: body)
        XCTAssertEqual(result, "PHNhbWxwOlJlc3BvbnNl")
    }

    func testExtractSAMLResponseWithEqualsInValue() {
        // Base64 values contain '=' padding -- must not split on them
        let body = "SAMLResponse=PHNhbWxwOlJlc3BvbnNl=="
        let result = SAMLServer.extractSAMLResponse(from: body)
        XCTAssertEqual(result, "PHNhbWxwOlJlc3BvbnNl==")
    }

    func testReturnsNilForMissingSAMLResponse() {
        let body = "RelayState=token&Other=value"
        let result = SAMLServer.extractSAMLResponse(from: body)
        XCTAssertNil(result)
    }

    func testReturnsNilForEmptySAMLResponse() {
        let body = "SAMLResponse=&RelayState=token"
        let result = SAMLServer.extractSAMLResponse(from: body)
        XCTAssertNil(result)
    }

    func testParseContentLengthFromHeaders() {
        let headers = "POST / HTTP/1.1\r\nContent-Length: 4096\r\nHost: localhost"
        let result = SAMLServer.parseContentLength(from: headers)
        XCTAssertEqual(result, 4096)
    }

    func testParseContentLengthCaseInsensitive() {
        let headers = "content-length: 512"
        let result = SAMLServer.parseContentLength(from: headers)
        XCTAssertEqual(result, 512)
    }
}
