import Foundation
import Observation

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

    public init() {
        try? FileManager.default.createDirectory(
            at: Self.configsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    public func connect(_ config: VPNConfig) async throws {
        fatalError("Phase 2")
    }

    public func disconnect(_ config: VPNConfig) async throws {
        fatalError("Phase 2")
    }
}
