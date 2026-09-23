import SwiftUI

enum ProfileColorOption: String, CaseIterable, Identifiable {
    case orange
    case blue
    case green
    case red
    case purple
    case pink

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .orange: return .orange
        case .blue: return .blue
        case .green: return .green
        case .red: return .red
        case .purple: return .purple
        case .pink: return .pink
        }
    }

    var displayName: String {
        switch self {
        case .orange: return "オレンジ"
        case .blue: return "ブルー"
        case .green: return "グリーン"
        case .red: return "レッド"
        case .purple: return "パープル"
        case .pink: return "ピンク"
        }
    }
}

enum ProfileIconOption: String, CaseIterable, Identifiable {
    case tortoiseFill = "tortoise.fill"
    case hareFill = "hare.fill"
    case pawprintFill = "pawprint.fill"
    case birdFill = "bird.fill"
    case ladybugFill = "ladybug.fill"
    case antFill = "ant.fill"
    case motorcycle = "motorcycle"
    case mapFill = "map.fill"
    case locationFill = "location.fill"
    case flagCheckered = "flag.checkered"
    case fuelpumpFill = "fuelpump.fill"
    case helmet = "helmet"


    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tortoiseFill: return "カメ"
        case .hareFill: return "ウサギ"
        case .pawprintFill: return "肉球"
        case .birdFill: return "鳥"
        case .ladybugFill: return "てんとう虫"
        case .antFill: return "アリ"
        case .motorcycle: return "バイク"
        case .mapFill: return "地図"
        case .locationFill: return "現在地"
        case .flagCheckered: return "旗"
        case .fuelpumpFill: return "給油"
        case .helmet: return "ヘルメット"
        }
    }
}
