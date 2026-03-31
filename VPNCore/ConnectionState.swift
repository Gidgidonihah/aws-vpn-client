import Foundation

public enum ConnectionState: Sendable {
    case disconnected
    case authenticating
    case connected
    case disconnecting
    case failed(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var isAuthenticating: Bool {
        if case .authenticating = self { return true }
        return false
    }

    public var isDisconnecting: Bool {
        if case .disconnecting = self { return true }
        return false
    }

    public var isActive: Bool {
        isConnected || isAuthenticating || isDisconnecting
    }

    public var ipcLabel: String {
        switch self {
        case .disconnected:    return "disconnected"
        case .authenticating:  return "authenticating"
        case .connected:       return "connected"
        case .disconnecting:   return "disconnecting"
        case .failed(let msg): return "failed: \(msg)"
        }
    }
}
