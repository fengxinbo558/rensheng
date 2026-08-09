import Foundation

private enum DevicePolicyTestFailure: Error {
    case assertion(String)
}

private func policyExpect(_ condition: Bool, _ message: String) throws {
    guard condition else { throw DevicePolicyTestFailure.assertion(message) }
}

@main
struct DeviceSynthesisPolicySelfTest {
    static func main() throws {
        let gibibyte: UInt64 = 1_024 * 1_024 * 1_024
        try policyExpect(
            DeviceSynthesisPolicy.recommendedEngine(
                naturalResourcesAvailable: true,
                physicalMemoryBytes: 8 * gibibyte
            ) == .compatibility,
            "8GB 设备必须使用兼容引擎"
        )
        try policyExpect(
            DeviceSynthesisPolicy.recommendedEngine(
                naturalResourcesAvailable: true,
                physicalMemoryBytes: 16 * gibibyte
            ) == .natural,
            "16GB 设备且资源完整时应启用自然人声"
        )
        try policyExpect(
            DeviceSynthesisPolicy.recommendedEngine(
                naturalResourcesAvailable: false,
                physicalMemoryBytes: 32 * gibibyte
            ) == .compatibility,
            "缺少自然人声资源时必须回退兼容引擎"
        )
        print("DeviceSynthesisPolicySelfTest: PASS")
    }
}
