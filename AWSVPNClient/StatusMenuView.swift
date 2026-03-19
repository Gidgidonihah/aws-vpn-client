import SwiftUI
import VPNCore

struct StatusMenuView: View {
    @Environment(VPNManager.self) private var vpnManager

    var body: some View {
        if vpnManager.configs.isEmpty {
            Text("No configs — add .conf files")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Quit AWSVPNClient") {
            NSApplication.shared.terminate(nil)
        }
    }
}
