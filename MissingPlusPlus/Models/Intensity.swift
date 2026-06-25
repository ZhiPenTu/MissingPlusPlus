import Foundation

enum Intensity: String, Codable, CaseIterable, Identifiable {
    case none
    case mild
    case strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "无"
        case .mild: return "一般"
        case .strong: return "非常"
        }
    }
}
