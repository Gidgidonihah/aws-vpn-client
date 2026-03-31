import Foundation

/// IPC request sent from the CLI to the app over the Unix domain socket.
public struct IPCRequest: Codable, Sendable {
    public let cmd: String
    public let name: String?

    public init(cmd: String, name: String?) {
        self.cmd = cmd
        self.name = name
    }
}

/// Per-config status entry in an IPC status response.
public struct IPCConfigStatus: Codable, Sendable {
    public let name: String
    public let state: String

    public init(name: String, state: String) {
        self.name = name
        self.state = state
    }
}

/// IPC response sent from the app back to the CLI.
public struct IPCResponse: Codable, Sendable {
    public let ok: Bool
    public let error: String?
    public let configs: [IPCConfigStatus]?

    public init(ok: Bool, error: String?, configs: [IPCConfigStatus]?) {
        self.ok = ok
        self.error = error
        self.configs = configs
    }
}

/// Format a status table from an array of IPCConfigStatus entries.
/// Output: two plain aligned columns, no header row, sorted alphabetically (D-07/D-08/D-10).
/// Failed state shows error reason inline: "failed: <msg>" (D-09).
/// Returns "" for empty input.
public func formatStatusTable(_ configs: [IPCConfigStatus]) -> String {
    guard !configs.isEmpty else { return "" }
    let maxNameLen = configs.map(\.name.count).max() ?? 0
    return configs
        .sorted { $0.name < $1.name }
        .map { c in
            let pad = String(repeating: " ", count: maxNameLen - c.name.count + 4)
            return "\(c.name)\(pad)\(c.state)"
        }
        .joined(separator: "\n")
}
