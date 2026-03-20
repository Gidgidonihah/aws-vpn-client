import XCTest
@testable import VPNCore

final class ConnectionStateTests: XCTestCase {
    func testIsConnectedTrueForConnectedState() {
        let state = ConnectionState.connected
        XCTAssertTrue(state.isConnected)
    }

    func testIsConnectedFalseForDisconnectedState() {
        let state = ConnectionState.disconnected
        XCTAssertFalse(state.isConnected)
    }

    func testIsConnectedFalseForAuthenticatingState() {
        let state = ConnectionState.authenticating
        XCTAssertFalse(state.isConnected)
    }

    func testIsConnectedFalseForFailedState() {
        let state = ConnectionState.failed("some error")
        XCTAssertFalse(state.isConnected)
    }

    func testIsConnectedFalseForDisconnectingState() {
        let state = ConnectionState.disconnecting
        XCTAssertFalse(state.isConnected)
    }
}
