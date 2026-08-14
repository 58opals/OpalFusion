// OpalFusion+Mosaic+OpalMainnetAlpha+ReservationMaterialLeaseValidator.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    enum ReservationMaterialLeaseValidator {
        enum ValidationError: Error, Sendable, Equatable {
            case mismatch
        }

        static func validate(
            actualLease: OpalFusion.Host.MosaicReservationLease,
            materialLease: OpalFusion.Host.MosaicReservationLease
        ) throws(ValidationError) {
            guard actualLease == materialLease else {
                throw .mismatch
            }
        }
    }
}
