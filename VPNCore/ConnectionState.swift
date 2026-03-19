public enum ConnectionState {
    case disconnected
    case authenticating
    case connected
    case disconnecting
    case failed(Error)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
