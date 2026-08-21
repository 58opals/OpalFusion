// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapOpenedPublication.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapOpenedPublication<Document: Sendable>:
        Sendable
    {
        @_spi(MosaicPrivateAlpha) public let document: Document
        @_spi(MosaicPrivateAlpha) public let senderEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let wrapperEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let messageIdentifier: Data

        init(
            document: Document,
            senderEventIdentity: Data,
            recipientEventIdentity: Data,
            wrapperEventIdentity: Data,
            messageIdentifier: Data
        ) {
            self.document = document
            self.senderEventIdentity = senderEventIdentity
            self.recipientEventIdentity = recipientEventIdentity
            self.wrapperEventIdentity = wrapperEventIdentity
            self.messageIdentifier = messageIdentifier
        }
    }
}
#endif
