import Foundation

// design.md §5.4 のエアコン設定。JSON の値と列挙値の文字列を一致させる。
// fan は文字列 "1" 〜 "3"（数値ではない）。quiet と 4 はリモコンに存在しないため持たない（ADR-019）。

enum Mode: String, Codable, CaseIterable, Identifiable {
    case auto, cool, dry, heat, fan
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "自動"
        case .cool: "冷房"
        case .dry: "ドライ"
        case .heat: "暖房"
        case .fan: "送風"
        }
    }
}

enum Fan: String, Codable, CaseIterable, Identifiable {
    case auto
    case one = "1"
    case two = "2"
    case three = "3"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "自動"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        }
    }
}

enum Vane: String, Codable, CaseIterable, Identifiable {
    case auto, highest, high, middle, low, lowest, swing
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "自動"
        case .highest: "最上"
        case .high: "上"
        case .middle: "中央"
        case .low: "下"
        case .lowest: "最下"
        case .swing: "スイング"
        }
    }
}

struct Setting: Codable, Equatable {
    var power: Bool
    var mode: Mode
    var temp: Int
    var fan: Fan
    var vane: Vane

    static let tempRange = 16...31

    static let `default` = Setting(power: false, mode: .cool, temp: 26, fan: .auto, vane: .auto)
}
