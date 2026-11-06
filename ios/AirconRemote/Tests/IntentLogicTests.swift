import XCTest

@testable import AirconRemote

// ショートカット・ウィジェット・コントロールの共通ロジック（ADR-023）
final class IntentLogicTests: XCTestCase {
    private let base = Setting(power: false, mode: .cool, temp: 26, fan: .two, vane: .swing)

    func testOverridingKeepsUnspecifiedItems() throws {
        let s = try base.overriding(power: true)
        XCTAssertEqual(s, Setting(power: true, mode: .cool, temp: 26, fan: .two, vane: .swing))
    }

    func testOverridingReplacesSpecifiedItems() throws {
        let s = try base.overriding(power: true, mode: .heat, temp: 22, fan: .auto, vane: .low)
        XCTAssertEqual(s, Setting(power: true, mode: .heat, temp: 22, fan: .auto, vane: .low))
    }

    func testOverridingRejectsTemperatureOutsideTheRemoteRange() {
        XCTAssertThrowsError(try base.overriding(temp: 15)) {
            XCTAssertEqual($0 as? Setting.OverrideError, .tempOutOfRange(15))
        }
        XCTAssertThrowsError(try base.overriding(temp: 32))
        XCTAssertNoThrow(try base.overriding(temp: 16))
        XCTAssertNoThrow(try base.overriding(temp: 31))
    }

    func testSleepTimer() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(SleepTimer.executeAt(minutes: 60, now: now), now.addingTimeInterval(3600))
        XCTAssertNil(SleepTimer.executeAt(minutes: 0, now: now))
        XCTAssertNil(SleepTimer.executeAt(minutes: 721, now: now))
    }

    func testQuickActionMapsEveryLightButtonOnce() {
        let buttons = QuickAction.allCases.compactMap(\.lightButton)
        XCTAssertEqual(buttons, LightButton.allCases)
        XCTAssertNil(QuickAction.airconOn.lightButton)
        XCTAssertNil(QuickAction.airconOff.lightButton)
    }

    func testQuickActionDisplayIsComplete() {
        for action in QuickAction.allCases {
            XCTAssertFalse(action.label.isEmpty)
            XCTAssertFalse(action.systemImage.isEmpty)
            XCTAssertNotNil(QuickAction.caseDisplayRepresentations[action])
        }
    }

    func testEveryEnumCaseHasAShortcutsDisplay() {
        for c in LightButton.allCases { XCTAssertNotNil(LightButton.caseDisplayRepresentations[c]) }
        for c in Mode.allCases { XCTAssertNotNil(Mode.caseDisplayRepresentations[c]) }
        for c in Fan.allCases { XCTAssertNotNil(Fan.caseDisplayRepresentations[c]) }
        for c in Vane.allCases { XCTAssertNotNil(Vane.caseDisplayRepresentations[c]) }
    }

    func testScheduleSummaryContainsTheSetting() {
        let record = ScheduleRecord(executeAt: "2026-11-06T14:00:00Z", setting: base)
        XCTAssertTrue(record.summary.hasSuffix("電源OFF"))
    }

    func testLastResultRoundTrip() throws {
        let r = LastResult(action: "照明 全灯", success: true, message: "送信要求を受け付けました", at: Date(timeIntervalSince1970: 1_800_000_000))
        let decoded = try JSONDecoder().decode(LastResult.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(decoded, r)
    }
}
