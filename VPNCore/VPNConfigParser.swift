import Foundation

public enum VPNConfigParser {
    public struct ParsedConfig: Sendable {
        public let host: String
        public let port: String
        public let proto: String
        public let filteredContent: String
    }

    /// Parse a .conf file content string. Extracts host/port/proto from "remote" and "proto"
    /// directives, and returns filtered content with auth/remote directives stripped.
    /// Ported from aws-vpn-core/src/config.rs (should_strip, field, load).
    public static func parse(content: String) throws -> ParsedConfig {
        let lines = content.components(separatedBy: "\n")

        guard let host = field(lines: lines, directive: "remote", index: 1) else {
            throw VPNError.configParseFailure("No 'remote' directive found")
        }
        guard let port = field(lines: lines, directive: "remote", index: 2) else {
            throw VPNError.configParseFailure("No port in 'remote' directive")
        }
        guard let proto = field(lines: lines, directive: "proto", index: 1) else {
            throw VPNError.configParseFailure("No 'proto' directive found")
        }

        let filtered = lines
            .filter { !shouldStripLine($0) }
            .joined(separator: "\n")

        return ParsedConfig(host: host, port: port, proto: proto, filteredContent: filtered)
    }

    /// Convenience: parse from a file URL.
    public static func parse(fileURL: URL) throws -> ParsedConfig {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return try parse(content: content)
    }

    // MARK: - Private helpers

    /// Mirrors Rust's should_strip: strips auth-user-pass, auth-federate,
    /// auth-retry interact, and remote directives.
    private static func shouldStripLine(_ line: String) -> Bool {
        let l = line.trimmingCharacters(in: .whitespaces)
        return l.hasPrefix("auth-user-pass")
            || l.hasPrefix("auth-federate")
            || (l.hasPrefix("auth-retry") && l.contains("interact"))
            || l.hasPrefix("remote")
    }

    /// Mirrors Rust's field(): finds first line starting with "directive ",
    /// splits on whitespace, returns the token at zero-based `index`.
    private static func field(lines: [String], directive: String, index: Int) -> String? {
        let prefix = directive + " "
        guard let line = lines.first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
        }) else { return nil }
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count > index else { return nil }
        return parts[index]
    }
}
