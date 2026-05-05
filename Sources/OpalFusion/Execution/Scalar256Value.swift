// Scalar256Value.swift

import Foundation
import OpalCrypto
import Security

struct Scalar256Value {
    static let zero = Scalar256Value(limbs: (0, 0, 0, 0))
    static let order = Scalar256Value(
        limbs: (
            0xBFD25E8CD0364141,
            0xBAAEDCE6AF48A03B,
            0xFFFFFFFFFFFFFFFE,
            0xFFFFFFFFFFFFFFFF
        )
    )
    static let twoTo256MinusOrder = Scalar256Value(
        limbs: (
            0x402DA1732FC9BEBF,
            0x4551231950B75FC4,
            0x0000000000000001,
            0x0000000000000000
        )
    )

    let limbs: (UInt64, UInt64, UInt64, UInt64)

    var isZero: Bool {
        limbs.0 == 0 && limbs.1 == 0 && limbs.2 == 0 && limbs.3 == 0
    }

    var bytes32: [UInt8] {
        limbs.3.bigEndianBytes
            + limbs.2.bigEndianBytes
            + limbs.1.bigEndianBytes
            + limbs.0.bigEndianBytes
    }

    func addingModuloOrder(bytes: [UInt8]) throws -> Scalar256Value {
        let other = try Scalar256Value(bytes32: bytes)
        let (sum, carried) = adding(other)
        if carried {
            return sum.adding(Scalar256Value.twoTo256MinusOrder).sum
        }
        if sum.compare(to: .order) != .orderedAscending {
            return sum.subtracting(.order)
        }
        return sum
    }

    func compare(to other: Scalar256Value) -> ComparisonResult {
        let lhs = [limbs.3, limbs.2, limbs.1, limbs.0]
        let rhs = [other.limbs.3, other.limbs.2, other.limbs.1, other.limbs.0]
        for (left, right) in zip(lhs, rhs) {
            if left < right {
                return .orderedAscending
            }
            if left > right {
                return .orderedDescending
            }
        }
        return .orderedSame
    }

    private func adding(_ other: Scalar256Value) -> (sum: Scalar256Value, carry: Bool) {
        let (l0, c0) = limbs.0.addingReportingOverflow(other.limbs.0)
        let (l1p, c1p) = limbs.1.addingReportingOverflow(other.limbs.1)
        let (l1, c1) = l1p.addingReportingOverflow(c0 ? 1 : 0)
        let (l2p, c2p) = limbs.2.addingReportingOverflow(other.limbs.2)
        let (l2, c2) = l2p.addingReportingOverflow((c1p || c1) ? 1 : 0)
        let (l3p, c3p) = limbs.3.addingReportingOverflow(other.limbs.3)
        let (l3, c3) = l3p.addingReportingOverflow((c2p || c2) ? 1 : 0)
        return (
            Scalar256Value(limbs: (l0, l1, l2, l3)),
            c3p || c3
        )
    }

    private func subtracting(_ other: Scalar256Value) -> Scalar256Value {
        let (l0, b0) = limbs.0.subtractingReportingOverflow(other.limbs.0)
        let (l1p, b1p) = limbs.1.subtractingReportingOverflow(other.limbs.1)
        let (l1, b1) = l1p.subtractingReportingOverflow(b0 ? 1 : 0)
        let (l2p, b2p) = limbs.2.subtractingReportingOverflow(other.limbs.2)
        let (l2, b2) = l2p.subtractingReportingOverflow((b1p || b1) ? 1 : 0)
        let (l3p, b3p) = limbs.3.subtractingReportingOverflow(other.limbs.3)
        let (l3, b3) = l3p.subtractingReportingOverflow((b2p || b2) ? 1 : 0)
        precondition((b3p || b3) == false)
        return Scalar256Value(limbs: (l0, l1, l2, l3))
    }

    private init(limbs: (UInt64, UInt64, UInt64, UInt64)) {
        self.limbs = limbs
    }

    private init(bytes32: [UInt8]) throws {
        guard bytes32.count == 32 else {
            throw OpalFusion.Execution.WorkflowFailure.protocolValidationFailed(
                "Expected a 32-byte scalar"
            )
        }
        let limb0 = UInt64(bigEndianBytes: Array(bytes32[24..<32]))
        let limb1 = UInt64(bigEndianBytes: Array(bytes32[16..<24]))
        let limb2 = UInt64(bigEndianBytes: Array(bytes32[8..<16]))
        let limb3 = UInt64(bigEndianBytes: Array(bytes32[0..<8]))
        self.limbs = (limb0, limb1, limb2, limb3)
    }
}

private extension UInt64 {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.bigEndian) { Array($0) }
    }

    init(bigEndianBytes: [UInt8]) {
        precondition(bigEndianBytes.count == 8)
        self = bigEndianBytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}
