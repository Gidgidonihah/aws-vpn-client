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
}
