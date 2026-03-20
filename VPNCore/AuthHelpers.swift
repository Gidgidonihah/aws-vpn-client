import Foundation
import Security

/// Generates `byteCount` random bytes as a lowercase hex string.
/// `randomHex(byteCount: 12)` produces a 24-character hex string.
/// Ported from aws-vpn-core/src/vpn.rs `random_hex(n)`.
public func randomHex(byteCount: Int) -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
    return bytes.map { String(format: "%02x", $0) }.joined()
}

/// URL-encodes a SAML response string for openvpn credentials.
/// Matches Rust's `urlencoding::encode` behavior: space -> %20, + -> %2B.
/// `.urlQueryAllowed` leaves '+' unencoded, so we remove it from the allowed set.
public func urlEncodeSAML(_ samlResponse: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove("+")
    return samlResponse.addingPercentEncoding(withAllowedCharacters: allowed) ?? samlResponse
}

/// Dummy credentials for the initial openvpn auth challenge.
/// Line 1: "N/A", Line 2: "ACS::35001"
/// Ported from aws-vpn-core/src/vpn.rs `get_auth_challenge`.
public func dummyCredentials() -> String {
    "N/A\nACS::35001\n"
}

/// Real credentials with the SAML token for the sudo openvpn connection.
/// Line 1: "N/A", Line 2: "CRV1::<sid>::<urlEncodedSAML>"
/// Ported from aws-vpn-core/src/vpn.rs `connect`.
public func realCredentials(sid: String, urlEncodedSAML: String) -> String {
    "N/A\nCRV1::\(sid)::\(urlEncodedSAML)\n"
}

/// Result of parsing a CRV1 challenge line from openvpn output.
public struct CRV1Challenge: Sendable {
    public let url: String
    public let sid: String
}

/// Parses an AUTH_FAILED,CRV1 line from openvpn stdout/stderr.
/// Extracts the SAML redirect URL and session ID (colon-split field index 6).
/// Returns nil if the line does not contain "AUTH_FAILED,CRV1".
/// Ported from aws-vpn-core/src/vpn.rs `get_auth_challenge`.
public func parseCRV1Line(_ line: String) -> CRV1Challenge? {
    guard line.contains("AUTH_FAILED,CRV1") else { return nil }

    // Extract URL: matches Rust's crv1.split("https://").nth(1)
    guard let urlSuffix = line.components(separatedBy: "https://").dropFirst().first else {
        return nil
    }
    let url = "https://" + urlSuffix.trimmingCharacters(in: .whitespacesAndNewlines)

    // Extract SID: matches Rust's crv1.split(':').collect()[6] (awk field 7 / 1-indexed)
    let parts = line.components(separatedBy: ":")
    guard parts.count > 6 else { return nil }
    let sid = parts[6]
    guard !sid.isEmpty else { return nil }

    return CRV1Challenge(url: url, sid: sid)
}

/// Finds the first line containing "AUTH_FAILED,CRV1" in combined openvpn output.
public func findCRV1Line(in output: String) -> String? {
    output.components(separatedBy: "\n")
        .first { $0.contains("AUTH_FAILED,CRV1") }
}
