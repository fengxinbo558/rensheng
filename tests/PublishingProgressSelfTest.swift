import Foundation

private enum PublishingProgressTestFailure: Error {
    case assertion(String)
}

private func publishingExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw PublishingProgressTestFailure.assertion(message) }
}

@main
struct PublishingProgressSelfTest {
    static func main() throws {
        var project = NarrationProject(
            name: "出版进度测试",
            sourceText: "这是一份准备制作成声音的原稿。",
            voiceID: "voice-a"
        )
        var progress = PublishingProgress(project: project, availableFormats: [])
        try publishingExpect(progress.milestones[0].state == .completed, "原稿应已完成")
        try publishingExpect(progress.milestones[1].state == .waiting, "朗读稿应等待整理")
        try publishingExpect(progress.milestones[2].state == .waiting, "声音应等待生成")

        project.scriptState = .completed
        project.segments = [
            NarrationSegment(
                order: 0,
                text: "第一段。",
                kind: .explanation,
                voiceID: project.voiceID
            ),
            NarrationSegment(
                order: 1,
                text: "第二段。",
                kind: .conclusion,
                voiceID: project.voiceID
            ),
        ]
        project.segments[0].generationState = .completed
        progress = PublishingProgress(project: project, availableFormats: [.wav])
        try publishingExpect(progress.milestones[1].state == .completed, "朗读稿应已完成")
        try publishingExpect(progress.milestones[2].state == .active, "声音应处于制作中")
        try publishingExpect(progress.milestones[3].state == .active, "部分成品应处于制作中")

        project.segments[1].generationState = .completed
        progress = PublishingProgress(project: project, availableFormats: AudioExportFormat.allCases)
        try publishingExpect(progress.milestones[2].state == .completed, "全部声音应已完成")
        try publishingExpect(progress.milestones[3].state == .completed, "三种成品应已完成")

        project.segments[1].generationState = .failed
        progress = PublishingProgress(project: project, availableFormats: [])
        try publishingExpect(
            progress.milestones[2].state == .needsAttention,
            "失败片段应显示需要处理"
        )

        print("PublishingProgressSelfTest: PASS")
    }
}
