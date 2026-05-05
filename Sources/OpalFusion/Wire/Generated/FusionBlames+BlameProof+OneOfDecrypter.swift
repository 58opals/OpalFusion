// FusionBlames+BlameProof+OneOfDecrypter.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftProtobuf

extension FusionBlames.BlameProof {
    enum OneOfDecrypter: Equatable, Sendable {
      /// 32 byte, preferred if the proof decryption works at all
      case sessionKey(Data)
      /// 32 byte scalar
      case privkey(Data)

    }
}
