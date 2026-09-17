import XCTest
@testable import AirconRemote

// Worker の validateSetting（design.md §5.4）が受理する JSON を生成できることを固定する。
final class SettingCodingTests: XCTestCase {
    private func json(_ s: Setting) throws -> [String: Any] {
        let data = try JSONEncoder().encode(s)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testEncodesExactlyFiveFieldsWithSpecValues() throws {
        let s = Setting(power: true, mode: .cool, temp: 26, fan: .auto, vane: .middle)
        let obj = try json(s)
        XCTAssertEqual(Set(obj.keys), ["power", "mode", "temp", "fan", "vane"])
        XCTAssertEqual(obj["power"] as? Bool, true)
        XCTAssertEqual(obj["mode"] as? String, "cool")
        XCTAssertEqual(obj["temp"] as? Int, 26)
        XCTAssertEqual(obj["fan"] as? String, "auto")
        XCTAssertEqual(obj["vane"] as? String, "middle")
    }

    func testFanIsStringNotNumber() throws {
        let obj = try json(Setting(power: true, mode: .heat, temp: 20, fan: .three, vane: .low))
        XCTAssertEqual(obj["fan"] as? String, "3")
        XCTAssertNil(obj["fan"] as? Int)
    }

    func testAllEnumRawValuesMatchSpec() {
        XCTAssertEqual(Mode.allCases.map(\.rawValue), ["auto", "cool", "dry", "heat", "fan"])
        XCTAssertEqual(Fan.allCases.map(\.rawValue), ["auto", "1", "2", "3"])
        XCTAssertEqual(Vane.allCases.map(\.rawValue), ["auto", "highest", "high", "middle", "low", "lowest", "swing"])
    }

    func testTempRangeMatchesSpec() {
        XCTAssertEqual(Setting.tempRange, 16...31)
    }

    func testRoundTrip() throws {
        let s = Setting(power: false, mode: .dry, temp: 16, fan: .one, vane: .swing)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(Setting.self, from: data), s)
    }
}
