import XCTest
@testable import VPNCore

final class IPCMessageTests: XCTestCase {

    // MARK: - IPCRequest encode

    func testIPCRequestConnectEncode() throws {
        let request = IPCRequest(cmd: "connect", name: "corp-vpn")
        let data = try JSONEncoder().encode(request)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"cmd\":\"connect\""), "Expected cmd field in JSON")
        XCTAssertTrue(json.contains("\"name\":\"corp-vpn\""), "Expected name field in JSON")
    }

    func testIPCRequestStatusEncodeOmitsNilName() throws {
        let request = IPCRequest(cmd: "status", name: nil)
        let data = try JSONEncoder().encode(request)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"cmd\":\"status\""), "Expected cmd field in JSON")
        XCTAssertFalse(json.contains("\"name\""), "name key should be omitted when nil")
    }

    // MARK: - IPCRequest decode

    func testIPCRequestDecode() throws {
        let json = #"{"cmd":"disconnect","name":"dev"}"#
        let data = json.data(using: .utf8)!
        let request = try JSONDecoder().decode(IPCRequest.self, from: data)
        XCTAssertEqual(request.cmd, "disconnect")
        XCTAssertEqual(request.name, "dev")
    }

    // MARK: - IPCResponse encode

    func testIPCResponseOkEncode() throws {
        let response = IPCResponse(ok: true, error: nil, configs: nil)
        let data = try JSONEncoder().encode(response)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"ok\":true"), "Expected ok:true in JSON")
        XCTAssertFalse(json.contains("\"error\""), "error key should be omitted when nil")
        XCTAssertFalse(json.contains("\"configs\""), "configs key should be omitted when nil")
    }

    func testIPCResponseErrorEncode() throws {
        let response = IPCResponse(ok: false, error: "config not found", configs: nil)
        let data = try JSONEncoder().encode(response)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"ok\":false"), "Expected ok:false in JSON")
        XCTAssertTrue(json.contains("\"error\":\"config not found\""), "Expected error field in JSON")
    }

    // MARK: - IPCResponse round-trip with configs

    func testIPCResponseStatusRoundTrip() throws {
        let configs = [
            IPCConfigStatus(name: "corp-vpn", state: "connected"),
            IPCConfigStatus(name: "dev-vpn", state: "disconnected")
        ]
        let response = IPCResponse(ok: true, error: nil, configs: configs)
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(IPCResponse.self, from: data)
        XCTAssertTrue(decoded.ok)
        XCTAssertNil(decoded.error)
        XCTAssertEqual(decoded.configs?.count, 2)
        XCTAssertEqual(decoded.configs?[0].name, "corp-vpn")
        XCTAssertEqual(decoded.configs?[0].state, "connected")
        XCTAssertEqual(decoded.configs?[1].name, "dev-vpn")
        XCTAssertEqual(decoded.configs?[1].state, "disconnected")
    }

    // MARK: - formatStatusTable

    func testFormatStatusTableAlignment() {
        let configs = [
            IPCConfigStatus(name: "corp-vpn", state: "connected"),
            IPCConfigStatus(name: "dev", state: "disconnected"),
            IPCConfigStatus(name: "staging-eu", state: "connected")
        ]
        let output = formatStatusTable(configs)
        let lines = output.components(separatedBy: "\n")
        // All lines should have same column position for state
        // Longest name is "staging-eu" (10 chars) + 4 spaces padding minimum
        // "corp-vpn" (8) -> 10 - 8 + 4 = 6 spaces
        // "dev" (3) -> 10 - 3 + 4 = 11 spaces
        // "staging-eu" (10) -> 10 - 10 + 4 = 4 spaces
        XCTAssertEqual(lines.count, 3)
        // Alphabetical order: corp-vpn, dev, staging-eu
        XCTAssertTrue(lines[0].hasPrefix("corp-vpn"), "First line should be corp-vpn (alphabetical)")
        XCTAssertTrue(lines[1].hasPrefix("dev"), "Second line should be dev (alphabetical)")
        XCTAssertTrue(lines[2].hasPrefix("staging-eu"), "Third line should be staging-eu (alphabetical)")
        // corp-vpn has 6 spaces between name and state
        XCTAssertTrue(lines[0].contains("corp-vpn      connected"), "Expected 6 spaces after corp-vpn")
        // staging-eu has 4 spaces (minimum)
        XCTAssertTrue(lines[2].contains("staging-eu    connected"), "Expected 4 spaces after staging-eu")
    }

    func testFormatStatusTableAlphabetical() {
        let configs = [
            IPCConfigStatus(name: "zzz-vpn", state: "connected"),
            IPCConfigStatus(name: "aaa-vpn", state: "disconnected"),
            IPCConfigStatus(name: "mmm-vpn", state: "authenticating")
        ]
        let output = formatStatusTable(configs)
        let lines = output.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("aaa-vpn"), "First should be aaa-vpn")
        XCTAssertTrue(lines[1].hasPrefix("mmm-vpn"), "Second should be mmm-vpn")
        XCTAssertTrue(lines[2].hasPrefix("zzz-vpn"), "Third should be zzz-vpn")
    }

    func testFormatStatusTableFailedInline() {
        let configs = [
            IPCConfigStatus(name: "staging", state: "failed: timed out")
        ]
        let output = formatStatusTable(configs)
        XCTAssertTrue(output.contains("failed: timed out"), "Failed state should include reason inline")
    }

    func testFormatStatusTableEmpty() {
        let output = formatStatusTable([])
        XCTAssertEqual(output, "", "Empty input should return empty string")
    }
}
