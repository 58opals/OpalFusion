// MosaicPrivateAlphaWorkBenchmark.swift

import CryptoKit
import Foundation

private let privateDeploymentIdentifier =
    "nostr-tor/0-opal-mainnet-alpha-private-deployment.1"
private let protocolIdentifier = "Mosaic/0-opal-mainnet-alpha.4"
private let workDomain = Data(
    "Mosaic/0-opal-mainnet-alpha.4/private-deployment/availability-beacon-work".utf8
)
private let mainnetGenesisHash: [UInt8] = [
    0x00, 0x00, 0x00, 0x00, 0x00, 0x19, 0xd6, 0x68,
    0x9c, 0x08, 0x5a, 0xe1, 0x65, 0x83, 0x1e, 0x93,
    0x4f, 0xf7, 0x63, 0xae, 0x46, 0xa2, 0xa6, 0xc1,
    0x72, 0xb3, 0xf1, 0xb6, 0x0a, 0x8c, 0xe2, 0x6f,
]
private let discoveryIdentity: [UInt8] = [
    0x79, 0xbe, 0x66, 0x7e, 0xf9, 0xdc, 0xbb, 0xac,
    0x55, 0xa0, 0x62, 0x95, 0xce, 0x87, 0x0b, 0x07,
    0x02, 0x9b, 0xfc, 0xdb, 0x2d, 0xce, 0x28, 0xd9,
    0x59, 0xf2, 0x81, 0x5b, 0x16, 0xf8, 0x17, 0x98,
]
private let discoveryEpochStartUnixSeconds: UInt64 = 1_800_000_000

private func leadingZeroBitCount<D: Sequence>(in digest: D) -> Int where D.Element == UInt8 {
    var result = 0
    for byte in digest {
        if byte == 0 {
            result += 8
        } else {
            result += byte.leadingZeroBitCount
            break
        }
    }
    return result
}

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

private func appendUInt64(_ value: UInt64, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

private func appendCanonicalText(_ value: String, to data: inout Data) {
    let bytes = Array(value.utf8)
    appendUInt32(UInt32(bytes.count), to: &data)
    data.append(contentsOf: bytes)
}

private func makeWorkInput(trial: Int) -> (data: Data, nonceOffset: Int) {
    var data = workDomain
    data.append(contentsOf: privateDeploymentIdentifier.utf8)
    appendCanonicalText(privateDeploymentIdentifier, to: &data)
    appendCanonicalText(protocolIdentifier, to: &data)
    data.append(contentsOf: mainnetGenesisHash)
    appendUInt64(discoveryEpochStartUnixSeconds, to: &data)
    data.append(contentsOf: repeatElement(UInt8(trial + 1), count: 32))
    data.append(contentsOf: discoveryIdentity)
    data.append(contentsOf: repeatElement(UInt8(0x40 + trial), count: 32))
    let nonceOffset = data.count
    appendUInt64(0, to: &data)
    appendUInt64(discoveryEpochStartUnixSeconds + 60, to: &data)
    precondition(data.count == 364, "The production work preimage size drifted.")
    return (data, nonceOffset)
}

private func mine(targetBitCount: Int, trial: Int) -> (UInt64, Duration) {
    let workInput = makeWorkInput(trial: trial)
    var body = workInput.data
    var nonce = UInt64(trial) << 48
    let start = ContinuousClock.now
    while true {
        var bigEndian = nonce.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes in
            body.replaceSubrange(
                workInput.nonceOffset ..< workInput.nonceOffset + 8,
                with: bytes
            )
        }
        let digest = SHA256.hash(data: body)
        if leadingZeroBitCount(in: digest) >= targetBitCount {
            return (nonce - (UInt64(trial) << 48) + 1, start.duration(to: .now))
        }
        nonce &+= 1
    }
}

for target in [16, 18, 20] {
    var attemptCounts: [UInt64] = []
    var durations: [Double] = []
    for trial in 0 ..< 10 {
        let result = mine(targetBitCount: target, trial: trial)
        attemptCounts.append(result.0)
        durations.append(Double(result.1.components.seconds) + Double(result.1.components.attoseconds) / 1e18)
    }
    let sortedDurations = durations.sorted()
    let medianDuration = (sortedDurations[4] + sortedDurations[5]) / 2
    let totalAttempts = attemptCounts.reduce(0, +)
    let totalDuration = durations.reduce(0, +)
    let rate = Double(totalAttempts) / totalDuration
    print("target=\(target) trials=10 attempts=\(attemptCounts) median_seconds=\(medianDuration) total_seconds=\(totalDuration) hashes_per_second=\(rate)")
}
