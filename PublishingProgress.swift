import Foundation

enum PublishingMilestoneState: Equatable {
    case waiting
    case active
    case completed
    case needsAttention
}

struct PublishingMilestone: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let state: PublishingMilestoneState
}

struct PublishingProgress: Equatable {
    let milestones: [PublishingMilestone]

    init(project: NarrationProject, availableFormats: [AudioExportFormat]) {
        let completedSegments = project.segments.filter {
            $0.generationState == .completed
        }.count
        let hasFailedSegment = project.segments.contains {
            $0.generationState == .failed
        }
        let formats = Set(availableFormats.map(\.rawValue))
        let requiredFormats = Set(AudioExportFormat.allCases.map(\.rawValue))

        milestones = [
            PublishingMilestone(
                id: "source",
                title: "原稿",
                detail: Self.sourceDetail(project),
                state: Self.sourceState(project)
            ),
            PublishingMilestone(
                id: "script",
                title: "朗读稿",
                detail: Self.scriptDetail(project),
                state: Self.scriptState(project)
            ),
            PublishingMilestone(
                id: "audio",
                title: "声音",
                detail: project.segments.isEmpty
                    ? "等待生成"
                    : "(completedSegments) / (project.segments.count) 段",
                state: hasFailedSegment
                    ? .needsAttention
                    : completedSegments == project.segments.count && !project.segments.isEmpty
                        ? .completed
                        : completedSegments > 0
                            || project.segments.contains(where: { $0.generationState == .generating })
                            ? .active
                            : .waiting
            ),
            PublishingMilestone(
                id: "delivery",
                title: "成品",
                detail: formats == requiredFormats
                    ? "3 种格式"
                    : formats.isEmpty ? "等待制作" : "(formats.count) / 3 种格式",
                state: formats == requiredFormats
                    ? .completed
                    : formats.isEmpty ? .waiting : .active
            ),
        ]
    }

    private static func sourceState(_ project: NarrationProject) -> PublishingMilestoneState {
        switch project.importState {
        case .ready:
            return project.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .needsAttention
                : .completed
        case .captured, .extracting:
            return .active
        case .needsAttention:
            return .needsAttention
        }
    }

    private static func sourceDetail(_ project: NarrationProject) -> String {
        switch project.importState {
        case .captured, .extracting: return "正在导入"
        case .needsAttention: return "需要处理"
        case .ready: return "(project.sourceText.count) 字"
        }
    }

    private static func scriptState(_ project: NarrationProject) -> PublishingMilestoneState {
        switch project.scriptState {
        case .completed, .fallback:
            return project.segments.isEmpty ? .waiting : .completed
        case .preparing:
            return .active
        case .failed:
            return .needsAttention
        case .pending:
            return .waiting
        }
    }

    private static func scriptDetail(_ project: NarrationProject) -> String {
        switch project.scriptState {
        case .completed: return "(project.segments.count) 个语义段"
        case .fallback: return "安全逐字稿"
        case .preparing: return "正在整理"
        case .failed: return "需要重新整理"
        case .pending: return "等待整理"
        }
    }
}
