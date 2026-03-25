import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VPNCore

struct StatusMenuView: View {
    @Environment(VPNManager.self) private var vpnManager

    var body: some View {
        // 1. Config list (or empty state)
        if vpnManager.configs.isEmpty {
            Text("No configs — use Add Config...")
                .foregroundStyle(.secondary)
                .disabled(true)
        } else {
            ForEach(vpnManager.configs) { config in
                Button {
                    let manager = vpnManager
                    let capturedConfig = config
                    let state = manager.connections[capturedConfig.name] ?? .disconnected
                    if state.isConnected || state.isDisconnecting {
                        Task { @MainActor in try? await manager.disconnect(capturedConfig) }
                    } else {
                        Task { @MainActor in try? await manager.connect(capturedConfig) }
                    }
                } label: {
                    HStack {
                        Text(config.name)
                        Spacer()
                        Text(stateLabel(for: config))
                            .foregroundStyle(stateColor(for: config))
                    }
                }
                .disabled(isConfigDisabled(config))
            }
        }

        // 3. Divider
        Divider()

        // 4. Add Config...
        Button("Add Config...") {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.title = "Select OpenVPN Config File"
            if let confType = UTType(filenameExtension: "conf") {
                panel.allowedContentTypes = [confType]
            } else {
                panel.allowedFileTypes = ["conf"]
            }
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url {
                try? vpnManager.addConfig(from: url)
            }
        }

        // 5. Remove Config submenu
        Menu("Remove Config") {
            ForEach(vpnManager.configs) { config in
                Button(config.name) {
                    vpnManager.removeConfig(config)
                }
                .disabled(isActiveConfig(config))
            }
        }

        // 6. View Logs submenu
        Menu("View Logs") {
            ForEach(vpnManager.configs) { config in
                Button(config.name) {
                    let logURL = VPNManager.logsDirectory
                        .appendingPathComponent("\(config.name).log")
                    if !FileManager.default.fileExists(atPath: logURL.path) {
                        FileManager.default.createFile(
                            atPath: logURL.path,
                            contents: nil,
                            attributes: nil
                        )
                    }
                    NSWorkspace.shared.open(logURL)
                }
            }
        }

        // 7. Divider
        Divider()

        // 8. Quit
        Button("Quit AWSVPNClient") {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Private helpers

    private func stateLabel(for config: VPNConfig) -> String {
        switch vpnManager.connections[config.name] ?? .disconnected {
        case .connected:       return "● Connected"
        case .authenticating:  return "⏳ authenticating"
        case .disconnecting:   return "disconnecting..."
        case .failed(let msg): return "⚠ \(msg.prefix(30))"
        case .disconnected:    return ""
        }
    }

    private func stateColor(for config: VPNConfig) -> Color {
        switch vpnManager.connections[config.name] ?? .disconnected {
        case .connected:      return .green
        case .authenticating: return .secondary
        case .disconnecting:  return .secondary
        case .failed:         return .red
        case .disconnected:   return .primary
        }
    }

    private func isConfigDisabled(_ config: VPNConfig) -> Bool {
        let isAnyAuthenticating = vpnManager.connections.values.contains { $0.isAuthenticating }
        let state = vpnManager.connections[config.name] ?? .disconnected
        // Disconnected configs disabled while any auth is in progress (single-auth-at-a-time)
        if isAnyAuthenticating, case .disconnected = state { return true }
        return false
    }

    private func isActiveConfig(_ config: VPNConfig) -> Bool {
        let state = vpnManager.connections[config.name] ?? .disconnected
        return state.isActive
    }
}
