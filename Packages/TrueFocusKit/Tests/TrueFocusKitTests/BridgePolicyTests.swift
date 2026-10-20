import XCTest
@testable import TrueFocusKit

final class BridgePolicyTests: XCTestCase {
    func testTheBridgeAnswersExtensionsOnLoopbackOnly() {
        let port: UInt16 = 52525
        XCTAssertTrue(BridgePolicy.allows(host: "127.0.0.1:52525", origin: "chrome-extension://abcdefghijklmnop", port: port))
        XCTAssertTrue(BridgePolicy.allows(host: "localhost:52525", origin: nil, port: port))
        XCTAssertTrue(BridgePolicy.allows(host: "[::1]:52525", origin: "safari-web-extension://X", port: port))
        // A web page posting fake activity: browsers always send its Origin on a POST.
        XCTAssertFalse(BridgePolicy.allows(host: "127.0.0.1:52525", origin: "https://evil.example", port: port))
        XCTAssertFalse(BridgePolicy.allows(host: "127.0.0.1:52525", origin: "null", port: port))
        // DNS rebinding: a same-origin GET from a page whose own name now points at 127.0.0.1.
        XCTAssertFalse(BridgePolicy.allows(host: "127.0.0.1.evil.example:52525", origin: nil, port: port))
        XCTAssertFalse(BridgePolicy.allows(host: "localhost.evil.example", origin: nil, port: port))
        XCTAssertFalse(BridgePolicy.allows(host: "127.0.0.1:8080", origin: nil, port: port))
    }
}
