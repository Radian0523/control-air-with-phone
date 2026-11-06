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

extension Setting {
    /// 画面表示用の1行要約。電源OFFなら運転内容は出さない
    static func summary(_ s: Setting) -> String {
        s.power ? "\(s.mode.label) \(s.temp)℃ 風量\(s.fan.label) 風向\(s.vane.label)" : "電源OFF"
    }
}

// 照明（オーデリック NRL-3321）のボタン。JSON の値は POST /light の button と一致させる（ADR-022）
enum LightButton: String, Codable, CaseIterable, Identifiable {
    case on, eco, mame, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .on: "全灯"
        case .eco: "ECO"
        case .mame: "常夜灯"
        case .off: "消灯"
        }
    }
    var systemImage: String {
        switch self {
        case .on: "lightbulb.max"
        case .eco: "leaf"
        case .mame: "moon"
        case .off: "lightbulb.slash"
        }
    }
}
