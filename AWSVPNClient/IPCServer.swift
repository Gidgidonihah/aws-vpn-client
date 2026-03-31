import Foundation
import Network
import VPNCore

final class IPCServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.local.IPCServer", qos: .utility)
    private weak var vpnManager: VPNManager?

    static let socketPath: String = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AWSVPNClient/daemon.sock")
            .path
    }()

    init(vpnManager: VPNManager) throws {
        self.vpnManager = vpnManager

        // Stale socket cleanup (D-14, IPC-01): remove file before starting listener.
        // allowLocalEndpointReuse is broken on macOS (rdar://FB8658821) — must unlink manually.
        try? FileManager.default.removeItem(atPath: Self.socketPath)

        // NWParameters for Unix domain socket (Pattern 3 from RESEARCH.md).
        // Do NOT use NWParameters.tcp — use NWParameters() + transportProtocol override.
        // Do NOT set allowLocalEndpointReuse — broken on macOS.
        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: Self.socketPath)

        listener = try NWListener(using: params)

        // Set BOTH handlers BEFORE start() (Pitfall 3: connections arrive immediately after start).
        listener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("IPCServer failed: \(error)")
            }
        }
        listener.start(queue: queue)
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }

            var buf = buffer
            if let data { buf.append(data) }

            if let nlIndex = buf.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buf[..<nlIndex]
                self.handleRequest(Data(lineData), on: connection)
                return
            }
            if !isComplete && error == nil {
                self.receiveRequest(connection, buffer: buf)
            }
        }
    }

    private func handleRequest(_ data: Data, on connection: NWConnection) {
        guard let request = try? JSONDecoder().decode(IPCRequest.self, from: data) else {
            sendResponse(IPCResponse(ok: false, error: "invalid request", configs: nil), on: connection)
            return
        }

        Task { @MainActor [weak self] in
            guard let vpnManager = self?.vpnManager else {
                self?.sendResponse(IPCResponse(ok: false, error: "app shutting down", configs: nil), on: connection)
                return
            }

            switch request.cmd {
            case "connect":
                guard let name = request.name else {
                    self?.sendResponse(IPCResponse(ok: false, error: "missing config name", configs: nil), on: connection)
                    return
                }
                guard let config = vpnManager.configs.first(where: { $0.name == name }) else {
                    self?.sendResponse(IPCResponse(ok: false, error: "config not found", configs: nil), on: connection)
                    return
                }
                do {
                    try await vpnManager.connect(config)
                    self?.sendResponse(IPCResponse(ok: true, error: nil, configs: nil), on: connection)
                } catch {
                    self?.sendResponse(IPCResponse(ok: false, error: error.localizedDescription, configs: nil), on: connection)
                }

            case "disconnect":
                guard let name = request.name else {
                    self?.sendResponse(IPCResponse(ok: false, error: "missing config name", configs: nil), on: connection)
                    return
                }
                guard let config = vpnManager.configs.first(where: { $0.name == name }) else {
                    self?.sendResponse(IPCResponse(ok: false, error: "config not found", configs: nil), on: connection)
                    return
                }
                do {
                    try await vpnManager.disconnect(config)
                    self?.sendResponse(IPCResponse(ok: true, error: nil, configs: nil), on: connection)
                } catch {
                    self?.sendResponse(IPCResponse(ok: false, error: error.localizedDescription, configs: nil), on: connection)
                }

            case "status":
                let statuses = vpnManager.configs.map { config in
                    IPCConfigStatus(
                        name: config.name,
                        state: vpnManager.connections[config.name]?.ipcLabel ?? "disconnected"
                    )
                }
                self?.sendResponse(IPCResponse(ok: true, error: nil, configs: statuses), on: connection)

            default:
                self?.sendResponse(IPCResponse(ok: false, error: "unknown command", configs: nil), on: connection)
            }
        }
    }

    // MARK: - Response sending

    private func sendResponse(_ response: IPCResponse, on connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        var line = data
        line.append(UInt8(ascii: "\n"))
        connection.send(content: line, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
