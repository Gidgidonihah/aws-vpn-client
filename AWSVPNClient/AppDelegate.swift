import AppKit
import VPNCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by AWSVPNClientApp after init
    var vpnManager: VPNManager?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let vpnManager else { return .terminateNow }

        // Check if any connections need cleanup
        let activeConnections = vpnManager.connections.filter { _, state in
            state.isConnected || state.isDisconnecting || state.isAuthenticating
        }
        guard !activeConnections.isEmpty else { return .terminateNow }

        // Disconnect all active connections then allow termination
        Task { @MainActor in
            for config in vpnManager.configs {
                let state = vpnManager.connections[config.name]
                if case .connected = state {
                    try? await vpnManager.disconnect(config)
                } else if case .authenticating = state {
                    try? await vpnManager.disconnect(config)
                }
            }
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }

        // 5-second hard timeout -- force quit if disconnect hangs
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }
}
