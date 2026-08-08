// OpalFusion+Mosaic+OpalV0+AggregateDigest.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalV0 {
    static func isValidAggregateMemberCount(_ count: Int) -> Bool {
        let componentsPerContributor = componentAuthorizationCountPerContributor
        let roster = OpalFusion.Mosaic.RosterPolicy.opalV0
        let minimum = roster.minimumContributorCount
            * componentsPerContributor
        let maximum = (roster.maximumCandidateCount - roster.conductorCount)
            * componentsPerContributor
        return (minimum ... maximum).contains(count)
            && count.isMultiple(of: componentsPerContributor)
    }

    static func aggregateDigest(
        profile: OpalFusion.Mosaic.Profile = .opalV0,
        domainSuffix: String,
        canonicalBytes: [UInt8]
    ) -> [UInt8] {
        [UInt8](
            OpalCrypto.Hashing.sha256(
                Data(
                    "\(profile.rawValue)/\(domainSuffix)".utf8
                )
                    + Data(canonicalBytes)
            )
        )
    }
}
