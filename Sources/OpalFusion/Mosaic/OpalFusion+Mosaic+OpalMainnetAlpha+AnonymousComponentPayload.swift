// OpalFusion+Mosaic+OpalMainnetAlpha+AnonymousComponentPayload.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    struct AnonymousComponentPayload: Sendable, Equatable {
        let roundIdentifier: [UInt8]
        let authorizationToken: AuthorizationToken
        let component: OpalFusion.Mosaic.OpalV0.Component

        init(
            roundIdentifier: [UInt8],
            authorizationToken: AuthorizationToken,
            component: OpalFusion.Mosaic.OpalV0.Component
        ) throws {
            try RoleSeedValidator.validateFixed(
                roundIdentifier,
                field: .roundIdentifier
            )
            let componentBinding = try AuthorizationTokenInput.componentBinding(
                for: component
            )
            guard authorizationToken.input.roundIdentifier == roundIdentifier,
                  authorizationToken.input.purpose == .component,
                  authorizationToken.input.binding == componentBinding else {
                throw ContractError.invalidAuthorizationToken
            }
            self.roundIdentifier = Array(roundIdentifier)
            self.authorizationToken = authorizationToken
            self.component = component
        }
    }
}
