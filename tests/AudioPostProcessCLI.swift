import Foundation

@main
struct AudioPostProcessCLI {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw AudioPostProcessCLIError.invalidArguments
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let destination = URL(fileURLWithPath: CommandLine.arguments[2])
        try AudioProcessor.postProcessOutput(from: source, to: destination)
        let quality = try AudioProcessor.analyzePCM16WAV(at: destination)
        print("AudioPostProcessCLI PASS")
        print(String(format: "peak=%.2f dBFS", quality.peakDBFS))
        print("output=\(destination.path)")
    }
}

enum AudioPostProcessCLIError: LocalizedError {
    case invalidArguments

    var errorDescription: String? {
        "用法：AudioPostProcessCLI <输入 WAV> <输出 WAV>"
    }
}
