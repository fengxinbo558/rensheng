import Foundation

private enum ExistingAudioDeliveryTestFailure: Error {
    case assertion(String)
}

private func deliveryExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw ExistingAudioDeliveryTestFailure.assertion(message) }
}

@main
struct ExistingAudioDeliverySelfTest {
    static func main() throws {
        guard let rootPath = ProcessInfo.processInfo.environment["LOCAL_AUDIO_PROBE_TEST_ROOT"] else {
            throw ExistingAudioDeliveryTestFailure.assertion("缺少测试目录")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let source = root.appendingPathComponent("source.m4a")
        let destination = root.appendingPathComponent("delivered.m4a")
        let replacement = Data("new-audio".utf8)
        try Data("old-audio".utf8).write(to: source)
        try Data("stale".utf8).write(to: destination)

        try AudioExporter().deliverExisting(source, to: destination, format: .m4a)
        let firstDelivery = try Data(contentsOf: destination)
        try deliveryExpect(firstDelivery == Data("old-audio".utf8), "没有交付成品")

        try replacement.write(to: source)
        try AudioExporter().deliverExisting(source, to: destination, format: .m4a)
        let secondDelivery = try Data(contentsOf: destination)
        try deliveryExpect(secondDelivery == replacement, "没有安全替换旧成品")

        do {
            try AudioExporter().deliverExisting(
                source,
                to: root.appendingPathComponent("wrong.mp3"),
                format: .m4a
            )
            throw ExistingAudioDeliveryTestFailure.assertion("错误扩展名不应通过")
        } catch AudioExporterError.wrongFileExtension {
            // 预期结果。
        }

        print("ExistingAudioDeliverySelfTest: PASS")
    }
}
