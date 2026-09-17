import XCTest
@testable import AirconRemote

// design.md §6 のエラー表の文言方針を固定する
final class CommandOutcomeTests: XCTestCase {
    func testAcceptedDoesNotClaimTheAirconMoved() {
        XCTAssertTrue(CommandOutcome.accepted.isSuccess)
        XCTAssertEqual(CommandOutcome.accepted.message, "送信要求を受け付けました")
        XCTAssertFalse(CommandOutcome.accepted.message.contains("動きました"))
    }

    func testFailuresAreNotSuccess() {
        for o in [CommandOutcome.badRequest, .unauthorized, .deviceOffline, .serverError, .unexpected(418), .network("x"), .notConfigured] {
            XCTAssertFalse(o.isSuccess, "\(o)")
            XCTAssertFalse(o.message.isEmpty)
        }
    }

    func testDeviceOfflineGuidesToPowerAndWifi() {
        XCTAssertTrue(CommandOutcome.deviceOffline.message.contains("Wi-Fi"))
        XCTAssertTrue(CommandOutcome.unauthorized.message.contains("APP_TOKEN"))
    }
}
