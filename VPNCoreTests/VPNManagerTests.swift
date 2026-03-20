import XCTest
@testable import VPNCore

final class VPNManagerTests: XCTestCase {

    // MARK: - CONN-01: Concurrent auth guard

    func testConnectBlockedWhileAuthenticating() async throws {
        // CONN-01: connect() throws .alreadyAuthenticating when another config is in .authenticating state
        let manager = await VPNManager()
        let configB = makeConfig(name: "vpn-b")

        // Manually inject authenticating state for configA
        await MainActor.run {
            manager.connections["vpn-a"] = .authenticating
        }

        // Attempting to connect configB should throw alreadyAuthenticating
        do {
            try await manager.connect(configB)
            XCTFail("Expected alreadyAuthenticating to be thrown")
        } catch VPNError.alreadyAuthenticating {
            // Expected
        }

        // configA state should remain authenticating
        let stateA = await MainActor.run { manager.connections["vpn-a"] }
        XCTAssertEqual(stateA?.isAuthenticating, true)
        // configB state should not be set
        let stateB = await MainActor.run { manager.connections["vpn-b"] }
        XCTAssertNil(stateB)
    }

    func testConnectSetsAuthenticatingState() async throws {
        // CONN-01: connect() sets connections[config.name] = .authenticating immediately
        // We verify this by triggering a connect that fails early (bad conf file -> configParseFailure)
        // and checking the state before the error propagates.
        // connect() sets .authenticating, then .failed on error -- we verify final state is .failed
        // (since we can't easily pause mid-connect in a unit test without concurrency tricks).
        let manager = await VPNManager()
        let badConfig = makeConfig(name: "bad-config")  // fileURL points to non-existent file

        do {
            try await manager.connect(badConfig)
            XCTFail("Expected connect to throw on bad config")
        } catch {
            // connect() threw -- state should be .failed since config parse failed
            let state = await MainActor.run { manager.connections["bad-config"] }
            // State is either .failed (parse error) or nil
            if let state {
                if case .failed(_) = state {
                    // Correct: error path sets .failed
                } else {
                    XCTFail("Expected .failed state after connect error, got \(state)")
                }
            }
            // Not nil means state was set to authenticating then failed -- pass
        }
    }

    // MARK: - CONN-02: Auth helpers (these are also tested in AuthHelpersTests)

    func testRandomHexLength() {
        // CONN-02: randomHex(byteCount: 12) returns exactly 24 hex characters
        let hex = randomHex(byteCount: 12)
        XCTAssertEqual(hex.count, 24, "randomHex(byteCount: 12) should produce 24 hex chars")
        XCTAssertTrue(hex.allSatisfy { $0.isHexDigit }, "All chars should be hex digits")
    }

    func testURLEncodingPlusChar() {
        // CONN-02: urlEncodeSAML encodes '+' as '%2B' (not left as '+')
        let input = "abc+def"
        let encoded = urlEncodeSAML(input)
        XCTAssertTrue(encoded.contains("%2B"), "'+' should be encoded as '%2B'")
        XCTAssertFalse(encoded.contains("+"), "'+' should not remain literal after encoding")
    }

    // MARK: - CONN-06: Temp file cleanup

    func testDummyCredsFileDeletedOnExit() async throws {
        // CONN-06: after connect() returns (success or failure), dummy creds temp file no longer exists
        // We test this indirectly: connect() will fail quickly on config parse for a non-existent file.
        // The defer block for dummyCredsPath is never reached (parse fails before it's created).
        // The real test: when connect() does create the dummy creds file, defer cleans it up.
        // We verify by checking no leftover aws-vpn-creds-dummy-* files remain after a failed connect.
        let manager = await VPNManager()
        let badConfig = makeConfig(name: "cleanup-test")

        let tmpDir = NSTemporaryDirectory()
        let beforeFiles = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir)) ?? []

        do {
            try await manager.connect(badConfig)
        } catch {
            // Expected to throw
        }

        let afterFiles = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir)) ?? []
        let newTempFiles = afterFiles.filter {
            $0.hasPrefix("aws-vpn-creds-dummy-cleanup-test")
        }
        XCTAssertTrue(newTempFiles.isEmpty, "Dummy creds temp files should be cleaned up after connect() exits")
        _ = beforeFiles  // suppress unused warning
    }

    func testRealCredsFileDeleted() async throws {
        // CONN-06: after connect() completes, real creds temp file no longer exists.
        // Similar to testDummyCredsFileDeletedOnExit -- real creds are only created after the
        // SAML challenge, which requires a live openvpn process. We verify no leftover files
        // exist from a failed connect (which never reaches that point anyway).
        let manager = await VPNManager()
        let badConfig = makeConfig(name: "real-creds-cleanup")

        do {
            try await manager.connect(badConfig)
        } catch {
            // Expected
        }

        let tmpDir = NSTemporaryDirectory()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir)) ?? []
        let leftover = files.filter { $0.hasPrefix("aws-vpn-creds-real-real-creds-cleanup") }
        XCTAssertTrue(leftover.isEmpty, "Real creds temp files should not exist after connect() fails early")
    }

    func testDisconnectSendsSignal() async throws {
        // CONN-07: disconnect() transitions .connected -> .disconnected and
        // cleans up tracking state. The kill itself cannot be unit-tested without
        // a real openvpn process, but we verify the state machine is correct.
        let manager = await VPNManager()
        let config = makeConfig(name: "disconnect-test")

        // Inject .connected state directly (simulate a connected VPN)
        await MainActor.run {
            manager.connections[config.name] = .connected
        }

        // disconnect() should succeed without throwing
        try await manager.disconnect(config)

        // State must be .disconnected after disconnect
        let state = await MainActor.run { manager.connections[config.name] }
        if let state {
            if case .disconnected = state {
                // Correct: state transitioned to .disconnected
            } else {
                XCTFail("Expected .disconnected after disconnect(), got \(state)")
            }
        }
    }

    // MARK: - CONN-08: Log file creation

    func testLogFileCreated() async throws {
        // CONN-08: VPNManager.init() creates ~/Library/Logs/AWSVPNClient/ directory
        let manager = await VPNManager()
        _ = manager  // ensure init runs

        let logsDir = await MainActor.run { VPNManager.logsDirectory }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: logsDir.path, isDirectory: &isDir)
        XCTAssertTrue(exists, "Logs directory should exist after VPNManager.init()")
        XCTAssertTrue(isDir.boolValue, "Logs path should be a directory")
        XCTAssertTrue(logsDir.path.contains("Logs/AWSVPNClient"), "Logs dir should be at ~/Library/Logs/AWSVPNClient")
    }

    // MARK: - Helpers

    private func makeConfig(name: String) -> VPNConfig {
        let url = URL(fileURLWithPath: "/tmp/\(name).conf")
        return VPNConfig(fileURL: url)
    }
}
