import Foundation

private enum QwenWorkerTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func workerExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw QwenWorkerTestFailure.assertion(message) }
}

private func workerCreateFile(_ url: URL, contents: Data = Data("test".utf8)) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try contents.write(to: url, options: .atomic)
}

@main
struct QwenWorkerSelfTest {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment["LOCAL_AUDIO_PROBE_TEST_ROOT"] else {
            throw QwenWorkerTestFailure.assertion("缺少测试目录")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let runner = root.appendingPathComponent("fake-qwen-worker.py")
        let model = root.appendingPathComponent("model", isDirectory: true)
        let deepFilter = root.appendingPathComponent("deepfilter", isDirectory: true)
        let reference = root.appendingPathComponent("reference.wav")
        try workerCreateFile(model.appendingPathComponent("config.json"))
        try workerCreateFile(deepFilter.appendingPathComponent("model.safetensors"))
        try workerCreateFile(reference)

        let script = #"""
import argparse
import json
import os
from pathlib import Path
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--worker", action="store_true")
parser.add_argument("--model-dir", required=True)
parser.add_argument("--deepfilter-model")
parser.add_argument("--deepfilter-wet")
parser.add_argument("--streaming-interval")
args = parser.parse_args()
model = Path(args.model_dir)
with (model / "starts.txt").open("a", encoding="utf-8") as handle:
    handle.write(f"{os.getpid()}\n")
print(json.dumps({"event": "worker_ready", "sampleRate": 24000}), flush=True)

for line in sys.stdin:
    message = json.loads(line)
    request_id = message["requestId"]
    if message["command"] == "shutdown":
        (model / "shutdown.txt").write_text("stopped", encoding="utf-8")
        print(json.dumps({"event": "worker_stopped", "requestId": request_id}), flush=True)
        break
    with (model / "requests.txt").open("a", encoding="utf-8") as handle:
        handle.write(message["text"] + "\n")
    print(json.dumps({"event": "voice_reused", "requestId": request_id}), flush=True)
    print(json.dumps({"event": "first_audio", "requestId": request_id}), flush=True)
    print(json.dumps({"event": "progress", "requestId": request_id, "chunks": 1}), flush=True)
    output = Path(message["output"])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(b"RIFF-fake-worker-output")
    print(json.dumps({"event": "completed", "requestId": request_id}), flush=True)
"""#
        try workerCreateFile(runner, contents: Data(script.utf8))

        let resources = QwenRuntimeResources(
            python: URL(fileURLWithPath: "/usr/bin/python3"),
            runner: runner,
            model: model,
            deepFilterModel: deepFilter
        )
        try workerExpect(resources.isAvailable, "伪 Worker 资源应当可用")
        let voice = VoiceProfile(
            id: "worker-voice",
            name: "Worker 测试音色",
            referenceAudioPath: reference.path,
            originalAudioPath: reference.path,
            processedAudioPath: nil,
            qualitySummary: nil,
            referenceText: "这是参考原文。",
            createdAt: Date(),
            authorizationConfirmedAt: Date(),
            isBuiltIn: false
        )
        var engine: QwenSpeechEngine? = QwenSpeechEngine(resources: resources)
        var progressEvents = 0
        for index in 0..<2 {
            let output = root.appendingPathComponent("output-\(index).wav")
            _ = try engine!.synthesize(
                request: SpeechSynthesisRequest(
                    text: "第\(index + 1)个连续语义段。",
                    voice: voice,
                    outputURL: output,
                    zipVoiceSteps: 8,
                    seed: 42 + index
                )
            ) { _ in
                progressEvents += 1
            }
            try workerExpect(
                FileManager.default.fileExists(atPath: output.path),
                "Worker 没有写入第 \(index + 1) 个结果"
            )
        }
        let starts = try String(
            contentsOf: model.appendingPathComponent("starts.txt"),
            encoding: .utf8
        ).split(whereSeparator: { $0.isNewline })
        try workerExpect(starts.count == 1, "连续生成两段时不应重启 Worker")
        let requests = try String(
            contentsOf: model.appendingPathComponent("requests.txt"),
            encoding: .utf8
        ).split(whereSeparator: { $0.isNewline })
        try workerExpect(requests.count == 2, "Worker 没有收到两个生成请求")
        try workerExpect(progressEvents >= 6, "Worker 进度事件没有传回应用")

        engine = nil
        try workerExpect(
            FileManager.default.fileExists(
                atPath: model.appendingPathComponent("shutdown.txt").path
            ),
            "引擎释放时没有有序关闭 Worker"
        )
        print("QwenWorkerSelfTest: PASS")
    }
}
