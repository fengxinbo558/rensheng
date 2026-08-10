import Foundation

final class AvailableAudioBuilder: @unchecked Sendable {
    private let store: ProjectStore
    private let fileManager: FileManager

    init(store: ProjectStore, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    func availableSegmentCount(in project: NarrationProject) -> Int {
        availableSegments(in: project).count
    }

    func build(project: NarrationProject) throws -> AudioAssemblyResult {
        let segments = availableSegments(in: project)
        guard !segments.isEmpty else { throw AvailableAudioBuilderError.noAvailableAudio }

        var previewProject = project
        previewProject.segments = segments
        let destination = try store.resolveProjectFileURL(
            projectID: project.id,
            relativePath: "previews/已完成部分.wav"
        )
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".available-\(UUID().uuidString).tmp.wav"
        )
        do {
            let assembled = try AudioAssembler(store: store).assemble(
                project: previewProject,
                destination: temporary
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporary, to: destination)
            return AudioAssemblyResult(
                outputURL: destination,
                segmentCount: assembled.segmentCount,
                durationSeconds: assembled.durationSeconds,
                sampleRate: assembled.sampleRate
            )
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func availableSegments(in project: NarrationProject) -> [NarrationSegment] {
        var result: [NarrationSegment] = []
        for segment in project.segments.sorted(by: { $0.order < $1.order }) {
            guard segment.generationState == .completed,
                  let selectedID = segment.selectedCandidateID,
                  let candidate = segment.candidates.first(where: { $0.id == selectedID }),
                  candidate.inputFingerprint == segment.inputFingerprint,
                  let url = try? store.resolveProjectFileURL(
                    projectID: project.id,
                    relativePath: candidate.relativePath
                  ),
                  fileManager.fileExists(atPath: url.path) else {
                break
            }
            result.append(segment)
        }
        return result
    }
}

enum AvailableAudioBuilderError: LocalizedError {
    case noAvailableAudio

    var errorDescription: String? {
        "第一段完成后就可以开始试听"
    }
}
