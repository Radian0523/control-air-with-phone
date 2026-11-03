import XCTest

@testable import AirconRemote

// POST /light の button の値（design.md §5.5、ADR-022）を固定する
final class LightButtonTests: XCTestCase {
    func testRawValuesMatchTheAPI() {
        XCTAssertEqual(LightButton.allCases.map(\.rawValue), ["on", "eco", "mame", "off"])
    }

    func testRequestBodyShape() throws {
        let data = try JSONEncoder().encode(["button": LightButton.mame.rawValue])
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(obj, ["button": "mame"])
    }

    func testLabelsAreNotEmpty() {
        for b in LightButton.allCases {
            XCTAssertFalse(b.label.isEmpty)
            XCTAssertFalse(b.systemImage.isEmpty)
        }
    }
}
