import Foundation

struct GenerationJournalEntry: Identifiable, Hashable {
    enum Event: String {
        case started
        case completed
        case retrying
        case failed
        case cancelled
        case reused
    }

    let id: String
    let job: GenerationJob
    let event: Event
    let message: String?
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        job: GenerationJob,
        event: Event,
        message: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.job = job
        self.event = event
        self.message = message
        self.createdAt = createdAt
    }
}

struct GenerationJournal {
    private(set) var entries: [GenerationJournalEntry] = []

    mutating func record(
        _ event: GenerationJournalEntry.Event,
        job: GenerationJob,
        message: String? = nil
    ) {
        entries.append(
            GenerationJournalEntry(job: job, event: event, message: message)
        )
    }
}
