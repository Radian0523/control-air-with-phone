import XCTest

@testable import AirconRemote

// design.md §5.2: executeAt は UTC・小数秒なしの YYYY-MM-DDTHH:mm:ssZ だけを Worker が受理する
final class ExecuteAtFormatTests: XCTestCase {
    func testFormatsAsUtcWithoutFractionalSeconds() {
        let date = Date(timeIntervalSince1970: 1789668000.789)  // 2026-09-17T18:00:00.789Z
        XCTAssertEqual(ExecuteAtFormat.string(from: date), "2026-09-17T18:00:00Z")
    }

    func testMatchesWorkerRegex() {
        let s = ExecuteAtFormat.string(from: Date())
        XCTAssertNotNil(s.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#, options: .regularExpression), s)
    }

    func testRoundTrip() {
        let s = "2026-09-13T18:00:00Z"
        XCTAssertEqual(ExecuteAtFormat.date(from: s).map(ExecuteAtFormat.string(from:)), s)
    }

    func testScheduleRecordEncodesExpectedKeys() throws {
        let rec = ScheduleRecord(
            executeAt: "2026-09-13T18:00:00Z", setting: Setting(power: true, mode: .cool, temp: 26, fan: .auto, vane: .auto))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(rec)) as? [String: Any])
        XCTAssertEqual(Set(obj.keys), ["executeAt", "setting"])
    }
}
