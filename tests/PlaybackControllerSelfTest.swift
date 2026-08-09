import Foundation

private enum PlaybackControllerTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func playbackExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw PlaybackControllerTestFailure.assertion(message) }
}

@main
struct PlaybackControllerSelfTest {
    @MainActor
    static func main() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["LOCAL_AUDIO_PROBE_TEST_ROOT"] else {
            throw PlaybackControllerTestFailure.assertion("缺少测试目录")
        }
        let audio = URL(fileURLWithPath: rootPath).appendingPathComponent("playback-silence.wav")
        try AudioProcessor.writePCM16WAV(
            PCM16Wave(sampleRate: 48_000, samples: Array(repeating: 0, count: 192_000)),
            to: audio
        )

        let controller = PlaybackController()
        try controller.play(url: audio, title: "播放器自检", contextID: "self-test", initialRate: 1.0)
        try playbackExpect(controller.state == .playing, "开始播放后状态不正确")
        try await Task.sleep(for: .milliseconds(250))
        controller.pause()
        let pausedTime = controller.currentTime
        try playbackExpect(controller.state == .paused, "暂停播放后状态不正确")
        try playbackExpect(pausedTime > 0, "暂停时没有记录播放进度")
        try await Task.sleep(for: .milliseconds(250))
        try playbackExpect(abs(controller.currentTime - pausedTime) < 0.03, "暂停后进度仍在移动")

        controller.setRate(3.0)
        try playbackExpect(controller.rate == 3.0, "试听速度无法调整到3倍")
        controller.resume()
        try playbackExpect(controller.state == .playing, "继续播放后状态不正确")
        try await Task.sleep(for: .milliseconds(150))
        controller.stop()
        try playbackExpect(controller.state == .stopped, "停止播放后状态不正确")
        try playbackExpect(controller.currentTime == 0, "停止播放后没有回到起点")

        controller.setRate(0.1)
        try playbackExpect(controller.rate == 0.1, "试听速度无法调整到0.1倍")
        controller.stopAndUnload()
        try playbackExpect(controller.state == .empty && !controller.hasAudio, "卸载音频后状态不正确")

        print("PlaybackControllerSelfTest: PASS")
    }
}
