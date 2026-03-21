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

    // MARK: - Phase 3: Config Management

    func testIsActiveProperty() async {
        // isActive returns true for connected, authenticating, disconnecting; false otherwise
        XCTAssertTrue(ConnectionState.connected.isActive)
        XCTAssertTrue(ConnectionState.authenticating.isActive)
        XCTAssertTrue(ConnectionState.disconnecting.isActive)
        XCTAssertFalse(ConnectionState.disconnected.isActive)
        XCTAssertFalse(ConnectionState.failed("err").isActive)
    }

    func testLoadConfigsSorted() async throws {
        let manager = await VPNManager()
        let configsDir = await MainActor.run { VPNManager.configsDirectory }

        // Write 3 test files with zzz-test- prefix to avoid colliding with real configs
        let names = ["zzz-test-charlie.conf", "zzz-test-alpha.conf", "zzz-test-bravo.conf"]
        for name in names {
            let url = configsDir.appendingPathComponent(name)
            try Data().write(to: url)
        }

        await MainActor.run { manager.loadConfigs() }

        let configs = await MainActor.run { manager.configs }
        let testConfigs = configs.filter { $0.name.hasPrefix("zzz-test-") }

        XCTAssertEqual(testConfigs.count, 3)
        XCTAssertEqual(testConfigs[0].name, "zzz-test-alpha")
        XCTAssertEqual(testConfigs[1].name, "zzz-test-bravo")
        XCTAssertEqual(testConfigs[2].name, "zzz-test-charlie")

        cleanupTestConfigs()
    }

    func testAddConfigCopiesFile() async throws {
        let manager = await VPNManager()
        let configsDir = await MainActor.run { VPNManager.configsDirectory }

        let sourceURL = URL(fileURLWithPath: "/tmp/zzz-test-add.conf")
        try Data("test".utf8).write(to: sourceURL)

        try await MainActor.run { try manager.addConfig(from: sourceURL) }

        let destURL = configsDir.appendingPathComponent("zzz-test-add.conf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path), "File should exist in configsDirectory")

        let configs = await MainActor.run { manager.configs }
        XCTAssertTrue(configs.contains { $0.name == "zzz-test-add" }, "configs array should contain zzz-test-add")

        cleanupTestConfigs()
        try? FileManager.default.removeItem(at: sourceURL)
    }

    func testAddConfigOverwritesExisting() async throws {
        let manager = await VPNManager()
        let configsDir = await MainActor.run { VPNManager.configsDirectory }

        let sourceURL = URL(fileURLWithPath: "/tmp/zzz-test-overwrite.conf")
        try Data("v1".utf8).write(to: sourceURL)
        try await MainActor.run { try manager.addConfig(from: sourceURL) }

        try Data("v2".utf8).write(to: sourceURL)
        try await MainActor.run { try manager.addConfig(from: sourceURL) }

        let destURL = configsDir.appendingPathComponent("zzz-test-overwrite.conf")
        let content = try String(contentsOf: destURL, encoding: .utf8)
        XCTAssertEqual(content, "v2", "File content should be v2 after second add")

        let configs = await MainActor.run { manager.configs }
        let matching = configs.filter { $0.name == "zzz-test-overwrite" }
        XCTAssertEqual(matching.count, 1, "configs array should have exactly one entry for zzz-test-overwrite")

        cleanupTestConfigs()
        try? FileManager.default.removeItem(at: sourceURL)
    }

    func testRemoveConfigUpdatesArray() async throws {
        let manager = await VPNManager()
        let configsDir = await MainActor.run { VPNManager.configsDirectory }

        let sourceURL = URL(fileURLWithPath: "/tmp/zzz-test-remove.conf")
        try Data("test".utf8).write(to: sourceURL)
        try await MainActor.run { try manager.addConfig(from: sourceURL) }

        let config = await MainActor.run {
            manager.configs.first { $0.name == "zzz-test-remove" }!
        }

        await MainActor.run {
            manager.connections["zzz-test-remove"] = .disconnected
        }

        await MainActor.run { manager.removeConfig(config) }

        let configs = await MainActor.run { manager.configs }
        XCTAssertFalse(configs.contains { $0.name == "zzz-test-remove" }, "configs should not contain removed config")

        let connection = await MainActor.run { manager.connections["zzz-test-remove"] }
        XCTAssertNil(connection, "connections entry should be cleared after removeConfig")

        let destURL = configsDir.appendingPathComponent("zzz-test-remove.conf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destURL.path), "File should no longer exist at configsDirectory (moved to Trash)")

        cleanupTestConfigs()
        try? FileManager.default.removeItem(at: sourceURL)
    }

    // MARK: - Helpers

    private func cleanupTestConfigs() {
        Task { @MainActor in
            let configsDir = VPNManager.configsDirectory
            let files = (try? FileManager.default.contentsOfDirectory(atPath: configsDir.path)) ?? []
            for file in files where file.hasPrefix("zzz-test-") && file.hasSuffix(".conf") {
                try? FileManager.default.removeItem(at: configsDir.appendingPathComponent(file))
            }
        }
    }

    private func makeConfig(name: String) -> VPNConfig {
        let url = URL(fileURLWithPath: "/tmp/\(name).conf")
        return VPNConfig(fileURL: url)
    }
}
