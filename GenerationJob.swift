import Foundation

struct GenerationJob: Identifiable, Hashable {
    let id: String
    let projectID: String
    let segmentID: String
    let attempt: Int

    init(
        id: String = UUID().uuidString,
        projectID: String,
        segmentID: String,
        attempt: Int
    ) {
        self.id = id
        self.projectID = projectID
        self.segmentID = segmentID
        self.attempt = attempt
    }
}

struct GenerationQueueProgress {
    let completed: Int
    let total: Int
    let currentSegment: Int
    let status: String
}

struct GenerationQueueSummary {
    var completed = 0
    var skipped = 0
    var failed = 0
    var cancelled = false
}
