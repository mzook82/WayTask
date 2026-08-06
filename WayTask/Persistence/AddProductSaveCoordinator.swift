import Foundation
import SwiftData

// MARK: - T-15 acquisition confirmation consumer

enum ProductAcquisitionProvenance: Equatable, Sendable {
    case manual
    case custom
    case catalog(ProductID)
    case barcode(BarcodeType)
    case cameraReviewed(RecognitionInputSource)
    case aiReviewed(RecognitionInputSource)
}

enum ProductAcquisitionReviewedEvidence: Equatable, Sendable {
    case manual(name: String, imageData: Data?)
    case custom(selection: AddProductCustomSelection, imageData: Data?)
    case catalog(selection: AddProductCatalogSelection, imageData: Data?)
    case barcode(
        candidate: ProductCandidate,
        observation: BarcodeResult,
        fallbackImageData: Data?
    )
    case cameraReviewed(
        candidate: ProductCandidate,
        recognition: RecognitionResult,
        fallbackImageData: Data?
    )
    case aiReviewed(
        candidate: ProductCandidate,
        recognition: RecognitionResult,
        barcodeObservation: BarcodeResult?,
        fallbackImageData: Data?
    )

    var provenance: ProductAcquisitionProvenance {
        switch self {
        case .manual:
            .manual
        case .custom:
            .custom
        case let .catalog(selection, _):
            .catalog(selection.productID)
        case let .barcode(_, observation, _):
            .barcode(observation.type)
        case let .cameraReviewed(_, recognition, _):
            .cameraReviewed(recognition.inputSource)
        case let .aiReviewed(_, recognition, _, _):
            .aiReviewed(recognition.inputSource)
        }
    }
}

struct ProductAcquisitionConfirmation: Equatable, Sendable {
    let productID: ProductStateProductID
    let commandID: ProductStateCommandID
    let effectiveAt: Date
    let evidence: ProductAcquisitionReviewedEvidence
    let confirmed: Bool

    var provenance: ProductAcquisitionProvenance {
        evidence.provenance
    }
}

enum ProductAcquisitionUnavailableReason: Equatable, Sendable {
    case catalogEvidenceUnavailable
    case productAuthority(ProductStateUnavailableReason)
    case unexpectedAuthorityResult
}

enum ProductAcquisitionOutcome: Equatable, Sendable {
    case created(productID: ProductStateProductID, revision: UInt64)
    case alreadyActive(productID: ProductStateProductID, revision: UInt64)
    case restoreRequired(productID: ProductStateProductID, revision: UInt64)
    case ambiguity(requestedProductID: ProductStateProductID)
    case validationFailure(requestedProductID: ProductStateProductID)
    case unavailable(
        requestedProductID: ProductStateProductID,
        reason: ProductAcquisitionUnavailableReason
    )
}

struct ProductAcquisitionResult: Equatable, Sendable {
    let confirmation: ProductAcquisitionConfirmation
    let outcome: ProductAcquisitionOutcome
    let resolvedCatalogID: ProductStateCatalogID?
    let commandDiagnostic: ProductStateProductCommandDiagnostic?

    var authoritativeProductID: ProductStateProductID? {
        switch outcome {
        case let .created(productID, _),
             let .alreadyActive(productID, _),
             let .restoreRequired(productID, _):
            productID
        case .ambiguity, .validationFailure, .unavailable:
            nil
        }
    }

    var requiresExplicitRestore: Bool {
        if case .restoreRequired = outcome { return true }
        return false
    }
}

struct ProductAcquisitionRestoreConfirmation: Equatable, Sendable {
    let acquisitionResult: ProductAcquisitionResult
    let commandID: ProductStateCommandID
    let historyEventID: ProductStateHistoryEventID
    let effectiveAt: Date
    let confirmed: Bool
}

enum ProductAcquisitionRestoreOutcome: Equatable, Sendable {
    case restored(productID: ProductStateProductID, revision: UInt64)
    case alreadyActive(productID: ProductStateProductID, revision: UInt64)
    case ambiguity(productID: ProductStateProductID)
    case conflict(productID: ProductStateProductID, ProductStateCommandConflict)
    case validationFailure(productID: ProductStateProductID?)
    case unavailable(
        productID: ProductStateProductID?,
        reason: ProductAcquisitionUnavailableReason
    )
}

struct ProductAcquisitionRestoreResult: Equatable, Sendable {
    let confirmation: ProductAcquisitionRestoreConfirmation
    let outcome: ProductAcquisitionRestoreOutcome
    let commandDiagnostic: ProductStateProductCommandDiagnostic?
}

enum ProductAcquisitionPresentationState: Equatable, Sendable {
    case idle
    case awaitingAcquisitionConfirmation(ProductAcquisitionConfirmation)
    case acquisitionResult(ProductAcquisitionResult)
    case awaitingRestoreConfirmation(ProductAcquisitionRestoreConfirmation)
    case restoreResult(ProductAcquisitionRestoreResult)
}

enum AddProductSaveOutcome {
    case catalogInserted(Product)
    case catalogAlreadyPresent(Product)
    case manualInserted(Product)
}

enum AddProductSaveCoordinatorError: LocalizedError {
    case unresolvedCatalogIdentity(sourceProductID: String)
    case persistedCatalogIdentityMismatch(
        expectedProductID: String,
        persistedProductID: String?
    )

    var errorDescription: String? {
        switch self {
        case .unresolvedCatalogIdentity(let sourceProductID):
            return "The selected catalog product \(sourceProductID) is not available in the current catalog."
        case .persistedCatalogIdentityMismatch(
            let expectedProductID,
            let persistedProductID
        ):
            return "Catalog identity was not preserved while saving \(expectedProductID) (persisted: \(persistedProductID ?? "none"))."
        }
    }
}

@MainActor
struct AddProductSaveCoordinator {
    typealias CatalogSave = (
        _ request: CatalogProductSaveRequest,
        _ modelContext: ModelContext
    ) throws -> CatalogProductSaveOutcome

    typealias ManualSave = (
        _ name: String,
        _ imageData: Data?,
        _ modelContext: ModelContext
    ) throws -> Product

    private let catalogSave: CatalogSave
    private let manualSave: ManualSave
    private let catalogResolver: ShoppingItemCatalogResolver

    init() {
        let catalogPersistenceService = CatalogProductPersistenceService()
        let shoppingListService = ShoppingListService()
        catalogResolver = ShoppingItemCatalogResolver()
        catalogSave = { request, modelContext in
            try catalogPersistenceService.save(request, in: modelContext)
        }
        manualSave = { name, imageData, modelContext in
            try shoppingListService.addManualProduct(
                name: name,
                imageData: imageData,
                in: modelContext
            )
        }
    }

    init(
        catalogSave: @escaping CatalogSave,
        manualSave: @escaping ManualSave,
        catalogResolver: ShoppingItemCatalogResolver =
            ShoppingItemCatalogResolver()
    ) {
        self.catalogSave = catalogSave
        self.manualSave = manualSave
        self.catalogResolver = catalogResolver
    }

    func save(
        selection: AddProductSelection,
        imageData: Data?,
        in modelContext: ModelContext
    ) throws -> AddProductSaveOutcome {
        switch selection {
        case .catalog(let catalogSelection):
            guard let identity = catalogResolver.resolve(
                productIDRawValue: catalogSelection.productID.rawValue
            ) else {
                Self.logUnresolvedCatalogSelection(catalogSelection)
                throw AddProductSaveCoordinatorError
                    .unresolvedCatalogIdentity(
                        sourceProductID:
                            catalogSelection.productID.rawValue
                    )
            }
            let metadata = catalogResolver.currentCategoryMetadata(
                for: identity
            )
            let request = CatalogProductSaveRequest(
                productID: ProductID(identity.productID),
                displayNameSnapshot: catalogSelection.displayName,
                displayLocaleSnapshot: catalogSelection.displayLocale,
                categoryIDSnapshot: ProductCategoryID(
                    identity.categoryID
                ),
                categoryDisplayNameSnapshot: metadata.displayName,
                iconKeySnapshot: metadata.iconKey,
                imageData: imageData,
                source: .catalog
            )
            Self.logCatalogSelectionBoundary(
                sourceProductID: catalogSelection.productID.rawValue,
                identity: identity,
                iconKey: metadata.iconKey
            )

            switch try catalogSave(request, modelContext) {
            case .inserted(let product):
                try validatePersistedIdentity(
                    product,
                    expected: identity
                )
                return .catalogInserted(product)
            case .alreadyPresent(let product):
                try validatePersistedIdentity(
                    product,
                    expected: identity
                )
                return .catalogAlreadyPresent(product)
            }

        case .custom(let customSelection):
            return .manualInserted(
                try manualSave(
                    customSelection.name,
                    imageData,
                    modelContext
                )
            )
        }
    }

    /// T-10 target-only route. Existing V3 callers remain on `save` until
    /// their authorized consumer-conversion steps; this route never receives
    /// a ModelContext and cannot persist or restore outside Command Authority.
    func acquireTargetProduct(
        selection: AddProductSelection,
        imageData: Data?,
        productID: ProductStateProductID,
        commandID: ProductStateCommandID,
        effectiveAt: Date,
        reviewed: Bool,
        using authority: ProductStateProductCommandAuthority
    ) throws -> ProductStateProductCommandExecution {
        switch selection {
        case .catalog(let catalogSelection):
            guard let identity = catalogResolver.resolve(
                productIDRawValue: catalogSelection.productID.rawValue
            ) else {
                throw AddProductSaveCoordinatorError
                    .unresolvedCatalogIdentity(
                        sourceProductID:
                            catalogSelection.productID.rawValue
                    )
            }
            let metadata = catalogResolver.currentCategoryMetadata(
                for: identity
            )
            let request = CatalogProductSaveRequest(
                productID: ProductID(identity.productID),
                displayNameSnapshot: catalogSelection.displayName,
                displayLocaleSnapshot: catalogSelection.displayLocale,
                categoryIDSnapshot: ProductCategoryID(
                    identity.categoryID
                ),
                categoryDisplayNameSnapshot: metadata.displayName,
                iconKeySnapshot: metadata.iconKey,
                imageData: imageData,
                source: .catalog
            )
            return try CatalogProductPersistenceService()
                .acquireTargetProduct(
                    request,
                    productID: productID,
                    commandID: commandID,
                    effectiveAt: effectiveAt,
                    reviewed: reviewed,
                    using: authority
                )

        case .custom(let customSelection):
            return authority.acquire(
                ProductStateProductAcquisitionRequest(
                    commandID: commandID,
                    productID: productID,
                    effectiveAt: effectiveAt,
                    reviewed: reviewed,
                    name: customSelection.name,
                    imageData: imageData,
                    sourceRawValue: ProductSource.manual.rawValue
                )
            )
        }
    }

    /// T-15 target acquisition consumer. One explicit confirmation is mapped
    /// to exactly one call to the committed T-10 Product authority. This API
    /// receives no ModelContext, opens no transaction, performs no save, and
    /// never restores or creates list membership as a follow-up side effect.
    func confirmTargetAcquisition(
        _ confirmation: ProductAcquisitionConfirmation,
        using authority: ProductStateProductCommandAuthority
    ) -> ProductAcquisitionResult {
        guard isValidTargetConfirmation(confirmation) else {
            return localTargetResult(
                confirmation,
                outcome: .validationFailure(
                    requestedProductID: confirmation.productID
                )
            )
        }

        let execution: ProductStateProductCommandExecution
        var resolvedCatalogID: ProductStateCatalogID?
        do {
            switch confirmation.evidence {
            case let .manual(name, imageData):
                execution = authority.acquire(
                    ProductStateProductAcquisitionRequest(
                        commandID: confirmation.commandID,
                        productID: confirmation.productID,
                        effectiveAt: confirmation.effectiveAt,
                        reviewed: confirmation.confirmed,
                        name: name,
                        imageData: imageData,
                        sourceRawValue: ProductSource.manual.rawValue
                    )
                )

            case let .custom(selection, imageData):
                execution = try acquireTargetProduct(
                    selection: .custom(selection),
                    imageData: imageData,
                    productID: confirmation.productID,
                    commandID: confirmation.commandID,
                    effectiveAt: confirmation.effectiveAt,
                    reviewed: confirmation.confirmed,
                    using: authority
                )

            case let .catalog(selection, imageData):
                guard let identity = catalogResolver.resolve(
                    productIDRawValue: selection.productID.rawValue
                ) else {
                    return localTargetResult(
                        confirmation,
                        outcome: .unavailable(
                            requestedProductID: confirmation.productID,
                            reason: .catalogEvidenceUnavailable
                        )
                    )
                }
                resolvedCatalogID = ProductStateCatalogID(
                    rawValue: identity.productID
                )
                execution = try acquireTargetProduct(
                    selection: .catalog(selection),
                    imageData: imageData,
                    productID: confirmation.productID,
                    commandID: confirmation.commandID,
                    effectiveAt: confirmation.effectiveAt,
                    reviewed: confirmation.confirmed,
                    using: authority
                )

            case let .barcode(candidate, _, fallbackImageData):
                execution = authority.acquire(
                    targetRequest(
                        confirmation: confirmation,
                        candidate: candidate,
                        fallbackImageData: fallbackImageData,
                        source: .barcode
                    )
                )

            case let .cameraReviewed(
                candidate,
                _,
                fallbackImageData
            ):
                execution = authority.acquire(
                    targetRequest(
                        confirmation: confirmation,
                        candidate: candidate,
                        fallbackImageData: fallbackImageData,
                        source: .camera
                    )
                )

            case let .aiReviewed(
                candidate,
                _,
                _,
                fallbackImageData
            ):
                execution = authority.acquire(
                    targetRequest(
                        confirmation: confirmation,
                        candidate: candidate,
                        fallbackImageData: fallbackImageData,
                        source: .ai
                    )
                )
            }
        } catch let error as CatalogProductPersistenceError {
            switch error {
            case .invalidField, .unsupportedSource:
                return localTargetResult(
                    confirmation,
                    outcome: .validationFailure(
                        requestedProductID: confirmation.productID
                    ),
                    resolvedCatalogID: resolvedCatalogID
                )
            case .lookupFailed, .duplicateCatalogIdentity, .saveFailed:
                return localTargetResult(
                    confirmation,
                    outcome: .unavailable(
                        requestedProductID: confirmation.productID,
                        reason: .catalogEvidenceUnavailable
                    ),
                    resolvedCatalogID: resolvedCatalogID
                )
            }
        } catch {
            return localTargetResult(
                confirmation,
                outcome: .validationFailure(
                    requestedProductID: confirmation.productID
                ),
                resolvedCatalogID: resolvedCatalogID
            )
        }

        return targetResult(
            confirmation,
            execution: execution,
            resolvedCatalogID: resolvedCatalogID
        )
    }

    /// Restore is a second, explicit confirmation over the exact
    /// restore-required result. It preserves that acquisition evidence and
    /// invokes only the committed T-10 Restore command.
    func confirmTargetRestore(
        _ confirmation: ProductAcquisitionRestoreConfirmation,
        using authority: ProductStateProductCommandAuthority
    ) -> ProductAcquisitionRestoreResult {
        guard confirmation.confirmed,
              confirmation.commandID.rawValue != Self.zeroUUID,
              confirmation.historyEventID.rawValue != Self.zeroUUID,
              confirmation.effectiveAt.timeIntervalSince1970.isFinite,
              case let .restoreRequired(productID, revision) =
                confirmation.acquisitionResult.outcome,
              confirmation.acquisitionResult.authoritativeProductID ==
                productID
        else {
            return ProductAcquisitionRestoreResult(
                confirmation: confirmation,
                outcome: .validationFailure(
                    productID:
                        confirmation.acquisitionResult.authoritativeProductID
                ),
                commandDiagnostic: nil
            )
        }

        let command = ProductStateCommand(
            id: confirmation.commandID,
            expectedRevision: ProductStateExpectedRevision(
                revision: ProductStateRevision(
                    scope: .product(productID),
                    value: revision
                )
            ),
            effectiveAt: confirmation.effectiveAt,
            intent: .restoreProductToLibrary(
                RestoreProductToLibraryCommand(
                    productID: productID,
                    historyEventID: confirmation.historyEventID,
                    confirmed: confirmation.confirmed
                )
            )
        )
        let execution = authority.restoreToLibrary(command)
        let outcome: ProductAcquisitionRestoreOutcome
        switch execution.outcome {
        case let .restored(summary):
            outcome = .restored(
                productID: summary.productID,
                revision: summary.productRevisionAfter
            )
        case let .alreadyActive(activeID, activeRevision):
            outcome = .alreadyActive(
                productID: activeID,
                revision: activeRevision
            )
        case .conflict(.ambiguousIdentity):
            outcome = .ambiguity(productID: productID)
        case let .conflict(conflict):
            outcome = .conflict(productID: productID, conflict)
        case .validationFailure:
            outcome = .validationFailure(productID: productID)
        case let .unavailable(reason):
            outcome = .unavailable(
                productID: productID,
                reason: .productAuthority(reason)
            )
        case .created, .restoreRequired, .edited, .removed, .noOp:
            outcome = .unavailable(
                productID: productID,
                reason: .unexpectedAuthorityResult
            )
        }
        return ProductAcquisitionRestoreResult(
            confirmation: confirmation,
            outcome: outcome,
            commandDiagnostic: execution.diagnostic
        )
    }

    private func targetRequest(
        confirmation: ProductAcquisitionConfirmation,
        candidate: ProductCandidate,
        fallbackImageData: Data?,
        source: ProductSource
    ) -> ProductStateProductAcquisitionRequest {
        ProductStateProductAcquisitionRequest(
            commandID: confirmation.commandID,
            productID: confirmation.productID,
            effectiveAt: confirmation.effectiveAt,
            reviewed: confirmation.confirmed,
            name: candidate.name,
            imageData: targetProductImageData(
                candidate,
                fallbackImageData: fallbackImageData
            ),
            brand: candidate.brand,
            category: candidate.category,
            barcode: ProductKnowledgeNormalizer.barcode(candidate.barcode),
            imageURLString: candidate.imageURL?.absoluteString,
            sourceRawValue: source.rawValue
        )
    }

    private func targetProductImageData(
        _ candidate: ProductCandidate,
        fallbackImageData: Data?
    ) -> Data? {
        if let imageData = candidate.imageData { return imageData }
        if candidate.imageURL != nil { return nil }
        return fallbackImageData
    }

    private func isValidTargetConfirmation(
        _ confirmation: ProductAcquisitionConfirmation
    ) -> Bool {
        guard confirmation.confirmed,
              confirmation.productID.rawValue != Self.zeroUUID,
              confirmation.commandID.rawValue != Self.zeroUUID,
              confirmation.effectiveAt.timeIntervalSince1970.isFinite
        else { return false }

        switch confirmation.evidence {
        case let .manual(name, _):
            return hasNonemptyText(name)

        case let .custom(selection, _):
            return hasNonemptyText(selection.name)

        case let .catalog(selection, _):
            return hasExactNonemptyText(selection.productID.rawValue) &&
                hasNonemptyText(selection.displayName) &&
                hasExactNonemptyText(selection.displayLocale) &&
                hasExactNonemptyText(selection.categoryID.rawValue) &&
                hasNonemptyText(selection.categoryDisplayName) &&
                hasExactNonemptyText(selection.iconKey)

        case let .barcode(candidate, observation, _):
            return candidate.source == .barcode &&
                isValidCandidate(candidate) &&
                hasExactNonemptyText(observation.value) &&
                candidate.barcode == observation.value &&
                observation.scannedAt.timeIntervalSince1970.isFinite &&
                isValidConfidence(observation.confidence)

        case let .cameraReviewed(candidate, recognition, _):
            return isValidCameraRecognition(
                candidate,
                recognition: recognition
            )

        case let .aiReviewed(
            candidate,
            recognition,
            barcodeObservation,
            _
        ):
            guard isValidReviewedRecognition(
                candidate,
                recognition: recognition,
                permittedSources: [.ai]
            ) else { return false }
            if let barcodeObservation {
                return recognition.inputSource == .barcode &&
                    hasExactNonemptyText(barcodeObservation.value) &&
                    candidate.barcode == barcodeObservation.value &&
                    barcodeObservation.scannedAt.timeIntervalSince1970
                        .isFinite &&
                    isValidConfidence(barcodeObservation.confidence)
            }
            return recognition.inputSource != .barcode &&
                candidate.barcode == nil
        }
    }

    private func isValidReviewedRecognition(
        _ candidate: ProductCandidate,
        recognition: RecognitionResult,
        permittedSources: [ProductCandidateSource]
    ) -> Bool {
        recognition.status == .recognized &&
            recognition.createdAt.timeIntervalSince1970.isFinite &&
            permittedSources.contains(candidate.source) &&
            recognition.candidates.contains(candidate) &&
            isValidCandidate(candidate)
    }

    private func isValidCameraRecognition(
        _ candidate: ProductCandidate,
        recognition: RecognitionResult
    ) -> Bool {
        guard isValidReviewedRecognition(
            candidate,
            recognition: recognition,
            permittedSources: [.cameraPhoto, .photoLibrary]
        ) else { return false }

        switch candidate.source {
        case .cameraPhoto:
            return recognition.inputSource == .cameraCapture
        case .photoLibrary:
            return recognition.inputSource == .photoLibrary
        case .barcode, .ai, .manual, .unknown:
            return false
        }
    }

    private func isValidCandidate(_ candidate: ProductCandidate) -> Bool {
        hasNonemptyText(candidate.name) &&
            isValidConfidence(candidate.confidence)
    }

    private func isValidConfidence(_ confidence: Double?) -> Bool {
        guard let confidence else { return true }
        return confidence.isFinite && (0...1).contains(confidence)
    }

    private func hasNonemptyText(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func hasExactNonemptyText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == value
    }

    private func localTargetResult(
        _ confirmation: ProductAcquisitionConfirmation,
        outcome: ProductAcquisitionOutcome,
        resolvedCatalogID: ProductStateCatalogID? = nil
    ) -> ProductAcquisitionResult {
        ProductAcquisitionResult(
            confirmation: confirmation,
            outcome: outcome,
            resolvedCatalogID: resolvedCatalogID,
            commandDiagnostic: nil
        )
    }

    private func targetResult(
        _ confirmation: ProductAcquisitionConfirmation,
        execution: ProductStateProductCommandExecution,
        resolvedCatalogID: ProductStateCatalogID?
    ) -> ProductAcquisitionResult {
        let outcome: ProductAcquisitionOutcome
        switch execution.outcome {
        case let .created(summary):
            outcome = .created(
                productID: summary.productID,
                revision: summary.productRevisionAfter
            )
        case let .alreadyActive(productID, revision):
            outcome = .alreadyActive(
                productID: productID,
                revision: revision
            )
        case let .restoreRequired(productID, revision):
            outcome = .restoreRequired(
                productID: productID,
                revision: revision
            )
        case .conflict(.ambiguousIdentity):
            outcome = .ambiguity(
                requestedProductID: confirmation.productID
            )
        case .validationFailure, .conflict:
            outcome = .validationFailure(
                requestedProductID: confirmation.productID
            )
        case let .unavailable(reason):
            outcome = .unavailable(
                requestedProductID: confirmation.productID,
                reason: .productAuthority(reason)
            )
        case .edited, .removed, .restored, .noOp:
            outcome = .unavailable(
                requestedProductID: confirmation.productID,
                reason: .unexpectedAuthorityResult
            )
        }
        return ProductAcquisitionResult(
            confirmation: confirmation,
            outcome: outcome,
            resolvedCatalogID: resolvedCatalogID,
            commandDiagnostic: execution.diagnostic
        )
    }

    private static let zeroUUID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000"
    )!

    private func validatePersistedIdentity(
        _ product: Product,
        expected identity: ResolvedShoppingItemCatalogIdentity
    ) throws {
        let persistedIdentity = catalogResolver.resolve(
            productIDRawValue: product.catalogProductIDRawValue
        )
        guard persistedIdentity?.productID == identity.productID else {
            #if DEBUG
            assertionFailure(
                "Catalog identity loss at selection-to-persistence boundary: expected \(identity.productID), persisted \(product.catalogProductIDRawValue ?? "nil")"
            )
            #endif
            throw AddProductSaveCoordinatorError
                .persistedCatalogIdentityMismatch(
                    expectedProductID: identity.productID,
                    persistedProductID:
                        product.catalogProductIDRawValue
                )
        }

        #if DEBUG
        print(
            "[WayTask Catalog Identity] persisted product=\(product.id.uuidString) catalogID=\(persistedIdentity?.productID ?? "nil")"
        )
        #endif
    }

    private static func logCatalogSelectionBoundary(
        sourceProductID: String,
        identity: ResolvedShoppingItemCatalogIdentity,
        iconKey: String
    ) {
        #if DEBUG
        print(
            "[WayTask Catalog Identity] selected sourceID=\(sourceProductID) canonicalID=\(identity.productID) categoryID=\(identity.categoryID) subcategoryID=\(identity.subcategoryID ?? "nil") iconKey=\(iconKey)"
        )
        #endif
    }

    private static func logUnresolvedCatalogSelection(
        _ selection: AddProductCatalogSelection
    ) {
        #if DEBUG
        print(
            "[WayTask Catalog Identity] rejected unresolved catalog selection sourceID=\(selection.productID.rawValue) query=\(selection.preselectionQuery)"
        )
        #endif
    }
}
