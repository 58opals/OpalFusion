// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapPublication.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One exact regular gift wrap prepared for durable three-relay publication.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapPublication: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let canonicalEventBytes: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data
        @_spi(MosaicPrivateAlpha) public let senderEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let wrapperEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let messageIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let operationIdentifier: Data

        let binding: Binding
        let relayEndpointIdentifiers: [String]

        init(
            canonicalEventBytes: Data,
            canonicalDocument: Data,
            senderEventIdentity: Data,
            recipientEventIdentity: Data,
            wrapperEventIdentity: Data,
            messageIdentifier: Data,
            operationIdentifier: Data,
            binding: Binding,
            relayEndpointIdentifiers: [String]
        ) {
            self.canonicalEventBytes = canonicalEventBytes
            self.canonicalDocument = canonicalDocument
            self.senderEventIdentity = senderEventIdentity
            self.recipientEventIdentity = recipientEventIdentity
            self.wrapperEventIdentity = wrapperEventIdentity
            self.messageIdentifier = messageIdentifier
            self.operationIdentifier = operationIdentifier
            self.binding = binding
            self.relayEndpointIdentifiers = relayEndpointIdentifiers
        }
    }
}
#endif
