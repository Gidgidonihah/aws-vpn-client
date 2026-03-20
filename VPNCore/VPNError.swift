import Foundation

public enum VPNError: Error, Sendable, LocalizedError {
    case configParseFailure(String)
    case authChallengeFailed(String)
    case samlResponseMissing
    case samlTimeout
    case connectionFailed(String)
    case alreadyAuthenticating
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .configParseFailure(let detail): return "Config parse failed: \(detail)"
        case .authChallengeFailed(let detail): return "Auth challenge failed: \(detail)"
        case .samlResponseMissing: return "SAML response missing"
        case .samlTimeout: return "SAML auth timed out"
        case .connectionFailed(let detail): return "Connection failed: \(detail)"
        case .alreadyAuthenticating: return "Another auth in progress"
        case .cancelled: return "Cancelled"
        }
    }

    /// Truncated description for menu display (max 30 chars)
    public var shortDescription: String {
        let full = errorDescription ?? "Unknown error"
        return full.count <= 30 ? full : String(full.prefix(27)) + "..."
    }
}
