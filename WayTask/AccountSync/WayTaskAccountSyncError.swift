import Foundation

enum WayTaskAccountSyncErrorCategory: String, CaseIterable, Sendable {
    case offline
    case authenticationRequired
    case sessionExpired
    case permissionDenied
    case invalidInput
    case rateLimited
    case conflict
    case serviceUnavailable
    case partialSync
    case migrationInterrupted
    case localPersistenceFailure
    case cloudPersistenceFailure
    case accountUnavailable
    case unknownRecoverable
    case unknownNonRecoverable
}

enum WayTaskAccountSyncDiagnosticCode: String, CaseIterable, Sendable {
    case networkOffline = "WTAS-001"
    case authenticationRequired = "WTAS-002"
    case sessionExpired = "WTAS-003"
    case authorizationDenied = "WTAS-004"
    case validationRejected = "WTAS-005"
    case requestRateLimited = "WTAS-006"
    case revisionConflict = "WTAS-007"
    case serviceUnavailable = "WTAS-008"
    case partialSynchronization = "WTAS-009"
    case migrationInterrupted = "WTAS-010"
    case localPersistenceFailure = "WTAS-011"
    case cloudPersistenceFailure = "WTAS-012"
    case accountUnavailable = "WTAS-013"
    case unknownRecoverable = "WTAS-014"
    case unknownNonRecoverable = "WTAS-015"
}

enum WayTaskAccountSyncRetryEligibility: String, Equatable, Sendable {
    case none
    case immediately
    case whenOnline
    case afterServerDelay
    case afterReauthentication
    case afterUserChoice
}

enum WayTaskAccountSyncLogPrivacy: String, Equatable, Sendable {
    case publicMetadataOnly
    case privateMetadataNoRecordContent
    case securityEventNoToken
}

struct WayTaskAccountSyncError: Error, Equatable, Sendable {
    let category: WayTaskAccountSyncErrorCategory
    let retryAfterSeconds: Int?

    init(
        category: WayTaskAccountSyncErrorCategory,
        retryAfterSeconds: Int? = nil
    ) {
        self.category = category
        self.retryAfterSeconds = retryAfterSeconds.map {
            min(max($0, 1), 86_400)
        }
    }

    var diagnosticCode: WayTaskAccountSyncDiagnosticCode {
        switch category {
        case .offline: .networkOffline
        case .authenticationRequired: .authenticationRequired
        case .sessionExpired: .sessionExpired
        case .permissionDenied: .authorizationDenied
        case .invalidInput: .validationRejected
        case .rateLimited: .requestRateLimited
        case .conflict: .revisionConflict
        case .serviceUnavailable: .serviceUnavailable
        case .partialSync: .partialSynchronization
        case .migrationInterrupted: .migrationInterrupted
        case .localPersistenceFailure: .localPersistenceFailure
        case .cloudPersistenceFailure: .cloudPersistenceFailure
        case .accountUnavailable: .accountUnavailable
        case .unknownRecoverable: .unknownRecoverable
        case .unknownNonRecoverable: .unknownNonRecoverable
        }
    }

    var userFacingTitle: String {
        switch category {
        case .offline: "You’re offline"
        case .authenticationRequired: "Sign in required"
        case .sessionExpired: "Your session expired"
        case .permissionDenied: "Information unavailable"
        case .invalidInput: "Check this information"
        case .rateLimited: "Please wait"
        case .conflict: "Changes need review"
        case .serviceUnavailable: "Sync is temporarily unavailable"
        case .partialSync: "Some changes are still pending"
        case .migrationInterrupted: "Backup was interrupted"
        case .localPersistenceFailure: "Could not save on this device"
        case .cloudPersistenceFailure: "Could not save to the cloud"
        case .accountUnavailable: "Accounts are unavailable"
        case .unknownRecoverable: "Sync did not finish"
        case .unknownNonRecoverable: "WayTask needs attention"
        }
    }

    var userFacingExplanation: String {
        switch category {
        case .offline:
            "Your changes are saved on this device. Sync will continue when you are back online."
        case .authenticationRequired:
            "Sign in to use cloud backup. Your local information remains available."
        case .sessionExpired:
            "Sign in again to continue syncing. Your local information remains available."
        case .permissionDenied:
            "We could not access this information. Sign in again or contact support if the problem continues."
        case .invalidInput:
            "One or more values could not be saved. Review the highlighted information and try again."
        case .rateLimited:
            "Too many attempts were made. Please wait a few minutes and try again."
        case .conflict:
            "WayTask found changes from more than one device and preserved them for review."
        case .serviceUnavailable:
            "WayTask could not sync right now. Your local information has not been lost."
        case .partialSync:
            "Some changes were backed up and the remaining changes are safe on this device."
        case .migrationInterrupted:
            "The first backup stopped before verification. It can continue without duplicating records."
        case .localPersistenceFailure:
            "WayTask could not confirm that this change was saved locally."
        case .cloudPersistenceFailure:
            "The change remains on this device and will not be marked as synchronized yet."
        case .accountUnavailable:
            "Cloud accounts are not available in this version or environment. Guest Mode still works."
        case .unknownRecoverable:
            "Your local information is safe. Try again, or continue working offline."
        case .unknownNonRecoverable:
            "WayTask could not safely continue this account operation. Local features remain available where possible."
        }
    }

    var recommendedAction: String {
        switch category {
        case .offline: "Continue offline and retry when connected."
        case .authenticationRequired, .sessionExpired, .permissionDenied:
            "Sign in again."
        case .invalidInput: "Review the values and try again."
        case .rateLimited: "Wait, then retry after the indicated time."
        case .conflict: "Review the preserved versions before choosing one."
        case .serviceUnavailable, .cloudPersistenceFailure,
             .unknownRecoverable:
            "Try again later or continue offline."
        case .partialSync, .migrationInterrupted:
            "Resume synchronization when convenient."
        case .localPersistenceFailure:
            "Keep the app open and retry; contact support if it continues."
        case .accountUnavailable:
            "Continue in Guest Mode."
        case .unknownNonRecoverable:
            "Contact support and include the diagnostic code."
        }
    }

    var retryEligibility: WayTaskAccountSyncRetryEligibility {
        switch category {
        case .offline: .whenOnline
        case .authenticationRequired, .sessionExpired, .permissionDenied:
            .afterReauthentication
        case .invalidInput, .conflict: .afterUserChoice
        case .rateLimited: .afterServerDelay
        case .serviceUnavailable, .partialSync, .migrationInterrupted,
             .cloudPersistenceFailure, .unknownRecoverable:
            .immediately
        case .localPersistenceFailure, .accountUnavailable,
             .unknownNonRecoverable:
            .none
        }
    }

    var mayContinueLocalWork: Bool {
        switch category {
        case .localPersistenceFailure, .unknownNonRecoverable:
            false
        default:
            true
        }
    }

    var loggingPrivacy: WayTaskAccountSyncLogPrivacy {
        switch category {
        case .authenticationRequired, .sessionExpired, .permissionDenied:
            .securityEventNoToken
        case .conflict, .partialSync, .migrationInterrupted,
             .localPersistenceFailure, .cloudPersistenceFailure:
            .privateMetadataNoRecordContent
        default:
            .publicMetadataOnly
        }
    }
}

extension WayTaskAccountSyncError: LocalizedError {
    var errorDescription: String? { userFacingExplanation }
}
