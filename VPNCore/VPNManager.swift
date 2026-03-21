import AppKit
import Foundation
import Observation

/// Global PID set for atexit safety net.
/// Updated from @MainActor, read from atexit (data race is acceptable for crash path).
public nonisolated(unsafe) var _atexitPIDs: [Int32] = []

/// Called from VPNManager whenever openvpnPIDs changes.
/// Also called from AWSVPNClientApp to keep atexit PID set current.
public func _updateAtexitPIDs(_ pids: [Int32]) {
    _atexitPIDs = pids
}

@Observable
@MainActor
public final class VPNManager {
    public var configs: [VPNConfig] = []
    public var connections: [String: ConnectionState] = [:]

    public var isAnyConnected: Bool {
        connections.values.contains { $0.isConnected }
    }

    public static let configsDirectory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AWSVPNClient/configs", isDirectory: true)
    }()

    public static let logsDirectory: URL = {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/AWSVPNClient", isDirectory: true)
    }()

    private let samlServer: SAMLServer?
    private var activeProcesses: [String: Process] = [:]   // configName -> sudo openvpn Process
    private var openvpnPIDs: [String: Int32] = [:]          // configName -> real openvpn PID from --writepid
    private let samlTimeoutSeconds: TimeInterval = 30

    private let openvpnPath: String = {
        for path in ["/usr/local/bin/openvpn", "/opt/homebrew/bin/openvpn", "/usr/bin/openvpn"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return "openvpn"
    }()

    public init() {
        try? FileManager.default.createDirectory(
            at: Self.configsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? FileManager.default.createDirectory(
            at: Self.logsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        self.samlServer = try? SAMLServer()
        loadConfigs()
    }

    public func connect(_ config: VPNConfig) async throws {
        // CONN-01: Guard -- block if any config is authenticating
        if let authenticatingEntry = connections.first(where: {
            if case .authenticating = $0.value { return true }
            return false
        }) {
            // If THIS config is authenticating, cancel it (CONTEXT.md: cancel on click)
            if authenticatingEntry.key == config.name {
                await cancelAuth(for: config)
                return
            }
            // Another config is authenticating -- block
            throw VPNError.alreadyAuthenticating
        }

        // Set state to authenticating (if .failed, allow immediate retry)
        connections[config.name] = .authenticating

        do {
            // 1. Parse config
            let parsed = try VPNConfigParser.parse(fileURL: config.fileURL)

            // 2. Write filtered config to temp file.
            // NOTE: Do NOT defer-delete filteredConfURL here. The sudo openvpn process needs
            // this file to remain on disk while it runs. The terminationHandler in
            // spawnSudoOpenvpn() deletes it after the process exits.
            let filteredConfURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("aws-vpn-conf-\(config.name)-\(UUID().uuidString).conf")
            try parsed.filteredContent.write(to: filteredConfURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: filteredConfURL.path
            )

            // 3. Resolve hostname: randomHex(12) + "." + host, then dig
            let randPrefix = randomHex(byteCount: 12)
            let fqdn = "\(randPrefix).\(parsed.host)"
            let serverIP = try await resolveDNS(hostname: fqdn)

            // 4. Write dummy creds (CONN-06: temp file with 0600, defer cleanup)
            let dummyCredsPath = NSTemporaryDirectory()
                + "aws-vpn-creds-dummy-\(config.name)-\(UUID().uuidString).txt"
            FileManager.default.createFile(
                atPath: dummyCredsPath,
                contents: dummyCredentials().data(using: .utf8),
                attributes: [.posixPermissions: 0o600]
            )
            defer { try? FileManager.default.removeItem(atPath: dummyCredsPath) }

            // 5. Run dummy openvpn to get CRV1 challenge
            let challenge = try await runDummyOpenvpn(
                filteredConfPath: filteredConfURL.path,
                proto: parsed.proto,
                serverIP: serverIP,
                port: parsed.port,
                credsPath: dummyCredsPath
            )

            // Check if cancelled during dummy openvpn
            guard connections[config.name]?.isAuthenticating == true else { return }

            // 6. Open browser for SAML
            guard let samlURL = URL(string: challenge.url) else {
                throw VPNError.authChallengeFailed("Invalid SAML URL: \(challenge.url)")
            }
            NSWorkspace.shared.open(samlURL)

            // 7. Wait for SAML response with timeout
            guard let samlServer else {
                throw VPNError.connectionFailed("SAML server not initialized")
            }

            let samlResponse: String
            do {
                samlResponse = try await withThrowingTaskGroup(of: String.self) { group in
                    group.addTask {
                        try await samlServer.waitForSAMLResponse()
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(self.samlTimeoutSeconds * 1_000_000_000))
                        samlServer.cancelCurrentWait()
                        throw VPNError.samlTimeout
                    }
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
            } catch is CancellationError {
                throw VPNError.samlTimeout
            }

            // Check if cancelled during SAML wait
            guard connections[config.name]?.isAuthenticating == true else { return }

            // 8. URL-encode SAML response and write real creds (CONN-06)
            let encoded = urlEncodeSAML(samlResponse)
            let realCredsPath = NSTemporaryDirectory()
                + "aws-vpn-creds-real-\(config.name)-\(UUID().uuidString).txt"
            FileManager.default.createFile(
                atPath: realCredsPath,
                contents: realCredentials(sid: challenge.sid, urlEncodedSAML: encoded).data(using: .utf8),
                attributes: [.posixPermissions: 0o600]
            )
            defer { try? FileManager.default.removeItem(atPath: realCredsPath) }

            // 9. Create log file (CONN-08)
            let logFileURL = Self.logsDirectory.appendingPathComponent("\(config.name).log")
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
            let logFileHandle = try FileHandle(forWritingTo: logFileURL)

            // 10. Spawn sudo openvpn (CONN-04)
            // Pass filteredConfPath so the terminationHandler can delete it after openvpn exits
            let pidPath = "/tmp/aws-vpn-\(config.name).pid"
            try spawnSudoOpenvpn(
                config: config,
                filteredConfPath: filteredConfURL.path,
                proto: parsed.proto,
                serverIP: serverIP,
                port: parsed.port,
                credsPath: realCredsPath,
                pidPath: pidPath,
                logFileHandle: logFileHandle
            )

        } catch {
            if connections[config.name] != nil {
                connections[config.name] = .failed(VPNError.shortDesc(error))
            }
            throw error
        }
    }

    public func disconnect(_ config: VPNConfig) async throws {
        let currentState = connections[config.name]

        // If authenticating, cancel the auth flow (cancel-on-click: no .failed)
        if case .authenticating = currentState {
            await cancelAuth(for: config)
            return
        }

        // Only disconnect if connected
        guard case .connected = currentState else { return }

        connections[config.name] = .disconnecting

        // Send SIGTERM to the REAL openvpn PID (not the sudo wrapper) -- Pitfall 1
        if let pid = openvpnPIDs[config.name] {
            let killProcess = Process()
            killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            killProcess.arguments = ["kill", "-TERM", String(pid)]
            try? killProcess.run()
            killProcess.waitUntilExit()  // kill is instant
        } else if let process = activeProcesses[config.name], process.isRunning {
            // Fallback: terminate the sudo wrapper (less reliable but better than nothing)
            process.terminate()
        }

        // Clean up PID file
        let pidPath = "/tmp/aws-vpn-\(config.name).pid"
        try? FileManager.default.removeItem(atPath: pidPath)

        // Clean up tracking
        activeProcesses.removeValue(forKey: config.name)
        openvpnPIDs.removeValue(forKey: config.name)
        _updateAtexitPIDs(Array(openvpnPIDs.values))

        // The terminationHandler will fire and sees .disconnecting -> transitions to .disconnected
        connections[config.name] = .disconnected
    }

    /// All currently tracked openvpn PIDs. Used by atexit safety net.
    /// Must be called from @MainActor context.
    public var allOpenvpnPIDs: [Int32] {
        Array(openvpnPIDs.values)
    }

    /// Synchronous disconnect-all for use in atexit handler.
    /// Sends SIGTERM directly to all known openvpn PIDs.
    /// This is NOT @MainActor safe -- acceptable only as a crash-path safety net.
    public nonisolated func killAllOpenvpnProcesses(pids: [Int32]) {
        for pid in pids {
            kill(pid, SIGTERM)
        }
    }

    // MARK: - Config Management (Phase 3)

    public func loadConfigs() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.configsDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        configs = urls
            .filter { $0.pathExtension == "conf" }
            .map { VPNConfig(fileURL: $0) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    public func addConfig(from sourceURL: URL) throws {
        // Ensure directory exists (guard against directory deletion)
        try? FileManager.default.createDirectory(
            at: Self.configsDirectory, withIntermediateDirectories: true, attributes: nil)
        let destURL = Self.configsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        // Silently overwrite if exists
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        // Remove existing entry with same name before appending (prevents duplicates)
        let newConfig = VPNConfig(fileURL: destURL)
        configs.removeAll { $0.name == newConfig.name }
        configs.append(newConfig)
        configs.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    public func removeConfig(_ config: VPNConfig) {
        try? FileManager.default.trashItem(at: config.fileURL, resultingItemURL: nil)
        configs.removeAll { $0.id == config.id }
        connections.removeValue(forKey: config.name)
    }

    // MARK: - Private helpers

    private func cancelAuth(for config: VPNConfig) async {
        // Cancel SAML wait
        samlServer?.cancelCurrentWait()

        // Kill dummy openvpn if running
        if let process = activeProcesses[config.name], process.isRunning {
            process.terminate()
        }
        activeProcesses.removeValue(forKey: config.name)

        // Reset to disconnected (CONTEXT.md: no .failed on cancel)
        connections[config.name] = .disconnected
    }

    private func resolveDNS(hostname: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dig")
        process.arguments = ["a", "+short", hostname]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()  // OK here -- dig is fast (< 1 second)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8),
              let ip = output.components(separatedBy: "\n").first(where: { !$0.isEmpty }) else {
            throw VPNError.connectionFailed("DNS resolution failed for \(hostname)")
        }
        return ip
    }

    private func runDummyOpenvpn(
        filteredConfPath: String,
        proto: String,
        serverIP: String,
        port: String,
        credsPath: String
    ) async throws -> CRV1Challenge {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: openvpnPath)
        process.arguments = [
            "--config", filteredConfPath,
            "--verb", "3",
            "--proto", proto,
            "--remote", serverIP, port,
            "--auth-user-pass", credsPath
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()  // Expected to fail quickly with AUTH_FAILED

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard let crv1Line = findCRV1Line(in: output),
              let challenge = parseCRV1Line(crv1Line) else {
            throw VPNError.authChallengeFailed("No AUTH_FAILED,CRV1 line in openvpn output")
        }
        return challenge
    }

    private func spawnSudoOpenvpn(
        config: VPNConfig,
        filteredConfPath: String,
        proto: String,
        serverIP: String,
        port: String,
        credsPath: String,
        pidPath: String,
        logFileHandle: FileHandle
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = [
            openvpnPath,
            "--config", filteredConfPath,
            "--verb", "3",
            "--auth-nocache",
            "--inactive", "3600",
            "--script-security", "2",
            "--proto", proto,
            "--remote", serverIP, port,
            "--auth-user-pass", credsPath,
            "--writepid", pidPath
        ]

        // CONN-08: stdout + stderr to same pipe, then to log file + line scanner
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Swift 6 safe: use @unchecked Sendable wrapper for mutable state in readabilityHandler
        final class LineScanner: @unchecked Sendable {
            var buffer = Data()
            var connected = false
        }
        let scanner = LineScanner()
        let configName = config.name

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                try? logFileHandle.close()
                return
            }

            // Write to log file (CONN-08: file only, no in-memory buffer)
            try? logFileHandle.write(contentsOf: data)

            // Scan for "Initialization Sequence Completed" (only until connected)
            guard !scanner.connected else { return }
            scanner.buffer.append(data)

            while let nl = scanner.buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = scanner.buffer[scanner.buffer.startIndex...nl]
                if let line = String(data: lineData, encoding: .utf8),
                   line.contains("Initialization Sequence Completed") {
                    scanner.connected = true
                    Task { @MainActor [weak self] in
                        self?.connections[configName] = .connected
                        // Read PID file after connected and update atexit safety net
                        if let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8),
                           let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            self?.openvpnPIDs[configName] = pid
                            if let self {
                                _updateAtexitPIDs(Array(self.openvpnPIDs.values))
                            }
                        }
                    }
                    scanner.buffer = Data()
                    break
                }
                scanner.buffer = Data(scanner.buffer[scanner.buffer.index(after: nl)...])
            }
        }

        // Termination handler: unexpected exit -> .failed (Pitfall 13: never use waitUntilExit)
        // Also cleans up the filtered conf file since openvpn no longer needs it after exit.
        process.terminationHandler = { [weak self] proc in
            // Delete filtered conf file now that openvpn has exited
            try? FileManager.default.removeItem(atPath: filteredConfPath)

            Task { @MainActor [weak self] in
                guard let self else { return }
                // Clean up PID tracking and keep atexit PID set current
                self.activeProcesses.removeValue(forKey: configName)
                self.openvpnPIDs.removeValue(forKey: configName)
                _updateAtexitPIDs(Array(self.openvpnPIDs.values))
                try? FileManager.default.removeItem(atPath: pidPath)

                switch self.connections[configName] {
                case .connected:
                    self.connections[configName] = .failed("openvpn exited unexpectedly")
                case .disconnecting:
                    self.connections[configName] = .disconnected
                case .authenticating:
                    self.connections[configName] = .failed("openvpn exited during auth")
                default:
                    break  // Already handled elsewhere
                }
            }
        }

        try process.run()
        activeProcesses[config.name] = process
    }
}
