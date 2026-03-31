import SwiftUI
import VPNCore

@main
@MainActor
struct AWSVPNClientApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var vpnManager = VPNManager()
    @State private var ipcServer: IPCServer?

    var body: some Scene {
        MenuBarExtra(
            vpnManager.isAnyConnected ? "VPN Connected" : "VPN",
            systemImage: vpnManager.isAnyConnected ? "lock.fill" : "lock.open"
        ) {
            StatusMenuView()
                .environment(vpnManager)
                .task {
                    appDelegate.vpnManager = vpnManager
                    ipcServer = try? IPCServer(vpnManager: vpnManager)
                }
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        _registerAtexitSafetyNet()
    }
}

private func _registerAtexitSafetyNet() {
    atexit {
        for pid in _atexitPIDs {
            kill(pid, SIGTERM)
        }
    }
}
