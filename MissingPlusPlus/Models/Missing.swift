import Foundation

struct Missing: Identifiable, Codable, Equatable {
    let id: UUID
    let who: String
    let mood: Mood
    let intensity: Intensity
    let createdAt: Date

    init(
        id: UUID = UUID(),
        who: String,
        mood: Mood,
        intensity: Intensity,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.who = who
        self.mood = mood
        self.intensity = intensity
        self.createdAt = createdAt
    }
}
