import Foundation

enum Mood: String, Codable, CaseIterable, Identifiable {
    case happy
    case joyful
    case delighted
    case sad
    case longing

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .joyful: return "😄"
        case .delighted: return "🥰"
        case .sad: return "😢"
        case .longing: return "🥺"
        }
    }

    var label: String {
        switch self {
        case .happy: return "开心"
        case .joyful: return "愉悦"
        case .delighted: return "欢乐"
        case .sad: return "难过"
        case .longing: return "思念"
        }
    }
}
