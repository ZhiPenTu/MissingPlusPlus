import Foundation

struct Missing: Identifiable, Codable, Hashable {
    let id: UUID
    let who: String
    let mood: Mood
    let intensity: Intensity
    let createdAt: Date
    var triggerTags: [TriggerTag]
    var resolvedAt: Date?
    var realityCheck: RealityCheck?

    init(
        id: UUID = UUID(),
        who: String,
        mood: Mood,
        intensity: Intensity,
        createdAt: Date = Date(),
        triggerTags: [TriggerTag] = [],
        resolvedAt: Date? = nil,
        realityCheck: RealityCheck? = nil
    ) {
        self.id = id
        self.who = who
        self.mood = mood
        self.intensity = intensity
        self.createdAt = createdAt
        self.triggerTags = triggerTags
        self.resolvedAt = resolvedAt
        self.realityCheck = realityCheck
    }

    private enum CodingKeys: String, CodingKey {
        case id, who, mood, intensity, createdAt
        case triggerTags, resolvedAt, realityCheck
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.who = try c.decode(String.self, forKey: .who)
        self.mood = try c.decode(Mood.self, forKey: .mood)
        self.intensity = try c.decode(Intensity.self, forKey: .intensity)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)

        // Forward-compat: 老 JSON 缺 triggerTags → []; 未来加新 case 后老 JSON
        // 里的旧 rawValue → 过滤掉
        let rawTags = try c.decodeIfPresent([String].self, forKey: .triggerTags) ?? []
        self.triggerTags = rawTags.compactMap(TriggerTag.init(rawValue:))

        self.resolvedAt = try c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        self.realityCheck = try c.decodeIfPresent(RealityCheck.self, forKey: .realityCheck)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(who, forKey: .who)
        try c.encode(mood, forKey: .mood)
        try c.encode(intensity, forKey: .intensity)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(triggerTags, forKey: .triggerTags)
        try c.encodeIfPresent(resolvedAt, forKey: .resolvedAt)
        try c.encodeIfPresent(realityCheck, forKey: .realityCheck)
    }
}

struct RealityCheck: Codable, Hashable {
    var evidenceFor: String?
    var evidenceAgainst: String?
    var nextAction: String?
    var checkedAt: Date
}
