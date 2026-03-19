import SwiftUI
import VPNCore

@main
@MainActor
struct AWSVPNClientApp: App {
    @State private var vpnManager = VPNManager()

    var body: some Scene {
        MenuBarExtra(
            vpnManager.isAnyConnected ? "VPN Connected" : "VPN",
            systemImage: vpnManager.isAnyConnected ? "lock.fill" : "lock.open"
        ) {
            StatusMenuView()
                .environment(vpnManager)
        }
        .menuBarExtraStyle(.menu)
    }
}
