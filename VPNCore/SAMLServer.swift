import Foundation
import Network

public final class SAMLServer: @unchecked Sendable {
    private let listener: NWListener
    private var continuation: CheckedContinuation<String, Error>?
    private let queue = DispatchQueue(label: "com.local.SAMLServer", qos: .utility)

    public init() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: 35001)

        // Set BOTH handlers before start (Pitfall 12)
        listener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                break // Listening
            case .failed(let error):
                print("SAMLServer failed: \(error)")
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    /// Suspends until exactly one SAMLResponse POST arrives.
    /// Throws CancellationError if cancelCurrentWait() is called, or VPNError.samlResponseMissing if body is bad.
    public func waitForSAMLResponse() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.queue.async {
                self.continuation = continuation
            }
        }
    }

    /// Cancels the current wait, resuming the continuation with CancellationError.
    public func cancelCurrentWait() {
        queue.async {
            self.continuation?.resume(throwing: CancellationError())
            self.continuation = nil
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPBody(connection: connection, accumulated: Data())
    }

    private func receiveHTTPBody(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }

            var buffer = accumulated
            if let data { buffer.append(data) }

            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerText = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
                let contentLength = Self.parseContentLength(from: headerText)
                let bodyStart = headerEnd.upperBound
                let body = buffer[bodyStart...]

                if body.count >= contentLength {
                    self.handlePOSTBody(Data(body), connection: connection)
                    return
                }
            }

            if !isComplete && error == nil {
                self.receiveHTTPBody(connection: connection, accumulated: buffer)
            }
        }
    }

    /// Parse Content-Length from HTTP headers (case-insensitive).
    /// Internal visibility for testing.
    static func parseContentLength(from headers: String) -> Int {
        for line in headers.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    private func handlePOSTBody(_ body: Data, connection: NWConnection) {
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        let saml = Self.extractSAMLResponse(from: bodyString)

        // Send HTTP 200 response before resuming continuation
        let responseText = "Got SAMLResponse; it is now safe to close this window"
        let response = "HTTP/1.1 200 OK\r\nContent-Length: \(responseText.utf8.count)\r\n\r\n\(responseText)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })

        if let saml, !saml.isEmpty {
            self.continuation?.resume(returning: saml)
        } else {
            self.continuation?.resume(throwing: VPNError.samlResponseMissing)
        }
        self.continuation = nil
    }

    /// Extract SAMLResponse value from URL-encoded POST body.
    /// Internal visibility for testing.
    /// Handles base64 '=' padding in the value by re-joining after the first '='.
    static func extractSAMLResponse(from body: String) -> String? {
        for pair in body.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            guard kv.count >= 2, kv[0] == "SAMLResponse" else { continue }
            // Re-join everything after the first "=" to preserve base64 padding
            let encoded = kv.dropFirst().joined(separator: "=")
            let decoded = encoded.removingPercentEncoding ?? encoded
            return decoded.isEmpty ? nil : decoded
        }
        return nil
    }
}
