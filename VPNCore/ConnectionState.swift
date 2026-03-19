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
}
