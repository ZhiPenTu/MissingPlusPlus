import Foundation

enum TriggerTag: String, Codable, CaseIterable, Hashable, Identifiable {
    case noReply       = "noReply"
    case silent        = "silent"
    case fight         = "fight"
    case alone         = "alone"
    case sawSomething  = "sawSomething"
    case pastMemory    = "pastMemory"
    case separation    = "separation"
    case comparison    = "comparison"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .noReply:      return "💬"
        case .silent:       return "🔇"
        case .fight:        return "⚡️"
        case .alone:        return "🏠"
        case .sawSomething: return "👀"
        case .pastMemory:   return "🕰"
        case .separation:   return "✈️"
        case .comparison:   return "🪞"
        }
    }

    var label: String {
        switch self {
        case .noReply:      return "TA 没及时回"
        case .silent:       return "TA 没说想我"
        case .fight:        return "刚吵完架"
        case .alone:        return "独处时"
        case .sawSomething: return "看到某物/某地"
        case .pastMemory:   return "想到过去"
        case .separation:   return "分离/即将分离"
        case .comparison:   return "比较/嫉妒"
        }
    }

    /// "💬 TA 没及时回"  — chip / notification body 共用
    var displayString: String { "\(emoji) \(label)" }
}
