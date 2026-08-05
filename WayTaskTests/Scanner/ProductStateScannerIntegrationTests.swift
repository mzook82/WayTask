import Foundation
import SwiftData
import XCTest
@testable import WayTask

@MainActor
final class ProductStateScannerIntegrationTests: XCTestCase {
    func testManualConfirmationCreatesExactProductIdentityLibraryOnly()
        throws {
        let fixture = try makeFixture("manual")
        let confirmation = ProductAcquisitionConfirmation(
            productID: productID(10),
            commandID: commandID(11),
            effectiveAt: instant,
            evidence: .manual(
                name: "Reviewed Manual Product",
                imageData: Data([0x10])
            ),
            confirmed: true
        )

        let result = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .created(productID: productID(10), revision: 1)
        )
        XCTAssertEqual(result.confirmation, confirmation)
        XCTAssertEqual(result.confirmation.provenance, .manual)
        XCTAssertEqual(result.authoritativeProductID, productID(10))
        XCTAssertFalse(result.requiresExplicitRestore)
        let stored = try fetchProduct(fixture, id: 10)
        XCTAssertEqual(stored.id, uuid(10))
        XCTAssertEqual(stored.name, "Reviewed Manual Product")
        XCTAssertEqual(stored.imageData, Data([0x10]))
        XCTAssertEqual(stored.sourceRawValue, ProductSource.manual.rawValue)
        XCTAssertEqual(try countLists(fixture), 0)
        XCTAssertEqual(try countHistory(fixture), 0)
    }

    func testCustomConfirmationCreatesExactUUIDAndPreservesCustomEvidence()
        throws {
        let fixture = try makeFixture("custom")
        let selection = AddProductCustomSelection(
            name: "Reviewed Custom Product",
            preselectionQuery: "custom input"
        )
        let confirmation = ProductAcquisitionConfirmation(
            productID: productID(20),
            commandID: commandID(21),
            effectiveAt: instant,
            evidence: .custom(
                selection: selection,
                imageData: Data([0x20])
            ),
            confirmed: true
        )

        let result = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .created(productID: productID(20), revision: 1)
        )
        XCTAssertEqual(result.confirmation.evidence, confirmation.evidence)
        XCTAssertEqual(result.confirmation.provenance, .custom)
        let stored = try fetchProduct(fixture, id: 20)
        XCTAssertEqual(stored.id, uuid(20))
        XCTAssertEqual(stored.name, selection.name)
        XCTAssertEqual(stored.imageData, Data([0x20]))
        XCTAssertEqual(stored.sourceRawValue, ProductSource.manual.rawValue)
    }

    func testCatalogConfirmationPreservesCanonicalIdentityAndSnapshots()
        throws {
        let fixture = try makeFixture("catalog")
        let selection = catalogSelection()
        let confirmation = ProductAcquisitionConfirmation(
            productID: productID(30),
            commandID: commandID(31),
            effectiveAt: instant,
            evidence: .catalog(
                selection: selection,
                imageData: Data([0x30])
            ),
            confirmed: true
        )

        let result = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .created(productID: productID(30), revision: 1)
        )
        XCTAssertEqual(
            result.resolvedCatalogID,
            ProductStateCatalogID(rawValue: "milk_3_percent")
        )
        XCTAssertEqual(
            result.confirmation.provenance,
            .catalog(selection.productID)
        )
        let stored = try fetchProduct(fixture, id: 30)
        XCTAssertEqual(stored.id, uuid(30))
        XCTAssertEqual(stored.catalogProductIDRawValue, "milk_3_percent")
        XCTAssertEqual(stored.catalogDisplayNameSnapshot, "חלב 3%")
        XCTAssertEqual(stored.catalogDisplayLocaleSnapshot, "he")
        XCTAssertEqual(stored.catalogCategoryIDSnapshotRawValue, "dairy")
        XCTAssertEqual(stored.catalogCategoryDisplayNameSnapshot, "מוצרי חלב")
        XCTAssertEqual(stored.catalogIconKeySnapshot, "product.dairy")
        XCTAssertEqual(stored.catalogSnapshotUpdatedAt, instant)
        XCTAssertEqual(stored.imageData, Data([0x30]))
    }

    func testBarcodeConfirmationPreservesObservationAndDoesNotUseCandidateID()
        throws {
        let fixture = try makeFixture("barcode")
        let observation = barcodeObservation(40, value: "000111222333")
        let candidate = barcodeCandidate(
            41,
            name: "Reviewed Barcode Product",
            barcode: observation.value
        )
        let confirmation = ProductAcquisitionConfirmation(
            productID: productID(42),
            commandID: commandID(43),
            effectiveAt: instant,
            evidence: .barcode(
                candidate: candidate,
                observation: observation,
                fallbackImageData: Data([0x41])
            ),
            confirmed: true
        )

        let result = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .created(productID: productID(42), revision: 1)
        )
        XCTAssertEqual(result.confirmation.evidence, confirmation.evidence)
        XCTAssertEqual(result.confirmation.provenance, .barcode(.ean13))
        let stored = try fetchProduct(fixture, id: 42)
        XCTAssertEqual(stored.id, uuid(42))
        XCTAssertNotEqual(stored.id, candidate.id)
        XCTAssertEqual(stored.barcode, observation.value)
        XCTAssertEqual(stored.sourceRawValue, ProductSource.barcode.rawValue)
        XCTAssertEqual(stored.brand, candidate.brand)
        XCTAssertEqual(stored.category, candidate.category)
        XCTAssertEqual(stored.imageData, candidate.imageData)
    }

    func testAIReviewedConfirmationPreservesRecognitionAndBarcodeEvidence()
        throws {
        let fixture = try makeFixture("ai")
        let observation = barcodeObservation(50, value: "999888777666")
        let candidate = ProductCandidate(
            id: uuid(51),
            name: "Reviewed AI Product",
            brand: "Synthetic Brand",
            category: "Synthetic Category",
            confidence: 0.87,
            productType: "Synthetic Type",
            flavor: "Synthetic Flavor",
            packageSize: "1 unit",
            packageType: "box",
            visibleText: "Reviewed package text",
            source: .ai,
            productHints: ["AI hint"],
            searchKeywords: ["AI keyword"],
            imageData: Data([0x51]),
            barcode: observation.value
        )
        let recognition = RecognitionResult(
            id: uuid(52),
            status: .recognized,
            candidates: [candidate],
            message: "Reviewed AI evidence",
            inputSource: .barcode,
            createdAt: instant.addingTimeInterval(-1)
        )
        let confirmation = ProductAcquisitionConfirmation(
            productID: productID(53),
            commandID: commandID(54),
            effectiveAt: instant,
            evidence: .aiReviewed(
                candidate: candidate,
                recognition: recognition,
                barcodeObservation: observation,
                fallbackImageData: Data([0xff])
            ),
            confirmed: true
        )

        let result = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .created(productID: productID(53), revision: 1)
        )
        XCTAssertEqual(result.confirmation.evidence, confirmation.evidence)
        XCTAssertEqual(
            result.confirmation.provenance,
            .aiReviewed(.barcode)
        )
        let stored = try fetchProduct(fixture, id: 53)
        XCTAssertEqual(stored.id, uuid(53))
        XCTAssertNotEqual(stored.id, candidate.id)
        XCTAssertEqual(stored.sourceRawValue, ProductSource.ai.rawValue)
        XCTAssertEqual(stored.barcode, observation.value)
        XCTAssertEqual(stored.imageData, candidate.imageData)
    }

    func testCameraReviewedConfirmationPreservesRecognitionEvidence()
        throws {
        let fixture = try makeFixture("camera")
        let candidate = ProductCandidate(
            id: uuid(60),
            name: "Reviewed Camera Product",
            confidence: 0.75,
            source: .cameraPhoto,
            imageData: Data([0x60])
        )
        let recognition = RecognitionResult(
            id: uuid(61),
            status: .recognized,
            candidates: [candidate],
            message: "Reviewed Camera evidence",
            inputSource: .cameraCapture,
            createdAt: instant.addingTimeInterval(-1)
        )
        let confirmation = ProductAcquisitionConfirmation(
            productID: productID(62),
            commandID: commandID(63),
            effectiveAt: instant,
            evidence: .cameraReviewed(
                candidate: candidate,
                recognition: recognition,
                fallbackImageData: nil
            ),
            confirmed: true
        )

        let result = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .created(productID: productID(62), revision: 1)
        )
        XCTAssertEqual(
            result.confirmation.provenance,
            .cameraReviewed(.cameraCapture)
        )
        XCTAssertEqual(result.confirmation.evidence, confirmation.evidence)
        XCTAssertEqual(
            try fetchProduct(fixture, id: 62).sourceRawValue,
            ProductSource.camera.rawValue
        )

        let mismatchedRecognition = RecognitionResult(
            id: uuid(64),
            status: .recognized,
            candidates: [candidate],
            message: "Mismatched Camera provenance",
            inputSource: .photoLibrary,
            createdAt: instant.addingTimeInterval(-1)
        )
        let mismatchedConfirmation = ProductAcquisitionConfirmation(
            productID: productID(65),
            commandID: commandID(66),
            effectiveAt: instant,
            evidence: .cameraReviewed(
                candidate: candidate,
                recognition: mismatchedRecognition,
                fallbackImageData: nil
            ),
            confirmed: true
        )
        XCTAssertEqual(
            consumer.confirmTargetAcquisition(
                mismatchedConfirmation,
                using: makeAuthority(fixture)
            ).outcome,
            .validationFailure(requestedProductID: productID(65))
        )
        XCTAssertEqual(try countProducts(fixture), 1)
    }

    func testExactProductUUIDReturnsAlreadyActiveWithoutMutation()
        throws {
        let fixture = try makeFixture("already-uuid")
        let existing = makeProduct(70, revision: 4, name: "Existing")
        fixture.repositories.products.stageInsertion(of: existing)
        try fixture.context.save()
        let confirmation = manualConfirmation(
            product: 70,
            command: 71,
            name: "Different Display Text"
        )

        let result = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .alreadyActive(productID: productID(70), revision: 4)
        )
        XCTAssertEqual(existing.name, "Existing")
        XCTAssertEqual(existing.revision, 4)
        XCTAssertFalse(fixture.context.hasChanges)
        XCTAssertFalse(result.commandDiagnostic?.claimsDurableSuccess ?? true)
    }

    func testExactCatalogIdentityReturnsExistingProductUUID()
        throws {
        let fixture = try makeFixture("already-catalog")
        let existing = makeProduct(
            80,
            revision: 6,
            name: "Saved Catalog Snapshot",
            catalogID: "milk_3_percent"
        )
        fixture.repositories.products.stageInsertion(of: existing)
        try fixture.context.save()
        let confirmation = ProductAcquisitionConfirmation(
            productID: productID(81),
            commandID: commandID(82),
            effectiveAt: instant,
            evidence: .catalog(
                selection: catalogSelection(),
                imageData: Data([0x81])
            ),
            confirmed: true
        )

        let result = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .alreadyActive(productID: productID(80), revision: 6)
        )
        XCTAssertEqual(result.authoritativeProductID, productID(80))
        XCTAssertNotEqual(result.authoritativeProductID, confirmation.productID)
        XCTAssertEqual(existing.name, "Saved Catalog Snapshot")
        XCTAssertEqual(try countProducts(fixture), 1)
    }

    func testRemovedBarcodeReturnsRestoreRequiredWithoutRestore()
        throws {
        let fixture = try makeFixture("restore-required")
        let removedAt = instant.addingTimeInterval(-100)
        let removed = makeProduct(
            90,
            revision: 7,
            lifecycle: .removed,
            name: "Removed Snapshot",
            barcode: "123123123123",
            removedAt: removedAt
        )
        fixture.repositories.products.stageInsertion(of: removed)
        try fixture.context.save()
        let observation = barcodeObservation(91, value: "123123123123")
        let confirmation = ProductAcquisitionConfirmation(
            productID: productID(92),
            commandID: commandID(93),
            effectiveAt: instant,
            evidence: .barcode(
                candidate: barcodeCandidate(
                    94,
                    name: "Different Reviewed Text",
                    barcode: observation.value
                ),
                observation: observation,
                fallbackImageData: nil
            ),
            confirmed: true
        )

        let result = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .restoreRequired(productID: productID(90), revision: 7)
        )
        XCTAssertTrue(result.requiresExplicitRestore)
        XCTAssertEqual(result.authoritativeProductID, productID(90))
        XCTAssertEqual(removed.libraryLifecycleRawValue, "removed")
        XCTAssertEqual(removed.libraryRemovedAt, removedAt)
        XCTAssertEqual(removed.name, "Removed Snapshot")
        XCTAssertEqual(try countProducts(fixture), 1)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testExplicitRestorePreservesUUIDEvidenceAndCreatesNoMembership()
        throws {
        let fixture = try makeFixture("explicit-restore")
        let removed = makeProduct(
            100,
            revision: 3,
            lifecycle: .removed,
            barcode: "456456456456",
            removedAt: instant.addingTimeInterval(-100)
        )
        fixture.repositories.products.stageInsertion(of: removed)
        try fixture.context.save()
        let acquisition = consumer.confirmTargetAcquisition(
            barcodeConfirmation(
                product: 101,
                command: 102,
                candidate: 103,
                observation: 104,
                barcode: "456456456456"
            ),
            using: makeAuthority(fixture)
        )
        let restore = ProductAcquisitionRestoreConfirmation(
            acquisitionResult: acquisition,
            commandID: commandID(105),
            historyEventID: historyID(106),
            effectiveAt: instant.addingTimeInterval(1),
            confirmed: true
        )

        let result = consumer.confirmTargetRestore(
            restore,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .restored(productID: productID(100), revision: 4)
        )
        XCTAssertEqual(result.confirmation.acquisitionResult, acquisition)
        let stored = try fetchProduct(fixture, id: 100)
        XCTAssertEqual(stored.id, uuid(100))
        XCTAssertEqual(stored.libraryLifecycleRawValue, "active")
        XCTAssertNil(stored.libraryRemovedAt)
        XCTAssertEqual(try countLists(fixture), 0)
        XCTAssertEqual(try countEntries(fixture), 0)
        XCTAssertEqual(try countHistory(fixture), 1)
        let event = try XCTUnwrap(
            try verificationContext(fixture).fetch(
                FetchDescriptor<WayTaskSchemaV4.ProductHistoryEvent>()
            ).first
        )
        XCTAssertEqual(event.productID, uuid(100))
        XCTAssertEqual(event.id, uuid(106))
        XCTAssertEqual(event.meaningRawValue, "productRestoredToLibrary")
    }

    func testRestoreWithoutExplicitConfirmationIsValidationFailure()
        throws {
        let fixture = try makeFixture("restore-unconfirmed")
        let removedAt = instant.addingTimeInterval(-100)
        let removed = makeProduct(
            110,
            revision: 2,
            lifecycle: .removed,
            barcode: "777666555444",
            removedAt: removedAt
        )
        fixture.repositories.products.stageInsertion(of: removed)
        try fixture.context.save()
        let acquisition = consumer.confirmTargetAcquisition(
            barcodeConfirmation(
                product: 111,
                command: 112,
                candidate: 113,
                observation: 114,
                barcode: "777666555444"
            ),
            using: makeAuthority(fixture)
        )
        let confirmation = ProductAcquisitionRestoreConfirmation(
            acquisitionResult: acquisition,
            commandID: commandID(115),
            historyEventID: historyID(116),
            effectiveAt: instant,
            confirmed: false
        )

        let result = consumer.confirmTargetRestore(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .validationFailure(productID: productID(110))
        )
        XCTAssertNil(result.commandDiagnostic)
        XCTAssertEqual(removed.libraryLifecycleRawValue, "removed")
        XCTAssertEqual(removed.libraryRemovedAt, removedAt)
        XCTAssertEqual(removed.revision, 2)
        XCTAssertEqual(try countHistory(fixture), 0)
    }

    func testMultipleExactCatalogMatchesReturnAmbiguityWithoutMerge()
        throws {
        let fixture = try makeFixture("ambiguity")
        let first = makeProduct(
            120,
            revision: 1,
            name: "First",
            catalogID: "milk_3_percent"
        )
        let second = makeProduct(
            121,
            revision: 1,
            name: "Second",
            catalogID: "milk_3_percent"
        )
        fixture.repositories.products.stageInsertion(of: second)
        fixture.repositories.products.stageInsertion(of: first)
        try fixture.context.save()
        let confirmation = ProductAcquisitionConfirmation(
            productID: productID(122),
            commandID: commandID(123),
            effectiveAt: instant,
            evidence: .catalog(
                selection: catalogSelection(),
                imageData: nil
            ),
            confirmed: true
        )

        let result = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .ambiguity(requestedProductID: productID(122))
        )
        XCTAssertNil(result.authoritativeProductID)
        XCTAssertEqual(try countProducts(fixture), 2)
        XCTAssertEqual(first.name, "First")
        XCTAssertEqual(second.name, "Second")
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testDisplayTextNeverInfersProductIdentity()
        throws {
        let fixture = try makeFixture("no-name-identity")
        let existing = makeProduct(
            130,
            revision: 5,
            name: "Same Display Text"
        )
        fixture.repositories.products.stageInsertion(of: existing)
        try fixture.context.save()
        let confirmation = manualConfirmation(
            product: 131,
            command: 132,
            name: "Same Display Text"
        )

        let result = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .created(productID: productID(131), revision: 1)
        )
        XCTAssertEqual(try countProducts(fixture), 2)
        XCTAssertEqual(existing.id, uuid(130))
        XCTAssertEqual(existing.revision, 5)
    }

    func testInvalidReviewedEvidenceReturnsOneValidationFailureWithoutCommand()
        throws {
        let fixture = try makeFixture("invalid-evidence")
        let observation = barcodeObservation(140, value: "111111111111")
        let invalid = ProductAcquisitionConfirmation(
            productID: productID(141),
            commandID: commandID(142),
            effectiveAt: instant,
            evidence: .barcode(
                candidate: barcodeCandidate(
                    143,
                    name: "Mismatched Evidence",
                    barcode: "222222222222"
                ),
                observation: observation,
                fallbackImageData: nil
            ),
            confirmed: true
        )

        let result = consumer.confirmTargetAcquisition(
            invalid,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .validationFailure(requestedProductID: productID(141))
        )
        XCTAssertNil(result.commandDiagnostic)
        XCTAssertNil(result.authoritativeProductID)
        XCTAssertEqual(result.confirmation.evidence, invalid.evidence)
        XCTAssertEqual(try countProducts(fixture), 0)
        XCTAssertFalse(fixture.context.hasChanges)

        let wrongSourceCandidate = ProductCandidate(
            id: uuid(144),
            name: "AI candidate wrapped as barcode",
            source: .ai,
            barcode: observation.value
        )
        let wrongSource = ProductAcquisitionConfirmation(
            productID: productID(145),
            commandID: commandID(146),
            effectiveAt: instant,
            evidence: .barcode(
                candidate: wrongSourceCandidate,
                observation: observation,
                fallbackImageData: nil
            ),
            confirmed: true
        )
        XCTAssertEqual(
            consumer.confirmTargetAcquisition(
                wrongSource,
                using: makeAuthority(fixture)
            ).outcome,
            .validationFailure(requestedProductID: productID(145))
        )
        XCTAssertEqual(try countProducts(fixture), 0)
    }

    func testUnconfirmedAcquisitionReturnsValidationFailureWithoutMutation()
        throws {
        let fixture = try makeFixture("unconfirmed")
        let confirmation = ProductAcquisitionConfirmation(
            productID: productID(150),
            commandID: commandID(151),
            effectiveAt: instant,
            evidence: .manual(name: "Not confirmed", imageData: nil),
            confirmed: false
        )

        let result = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .validationFailure(requestedProductID: productID(150))
        )
        XCTAssertNil(result.commandDiagnostic)
        XCTAssertEqual(try countProducts(fixture), 0)
    }

    func testUnavailableProductAuthorityMapsBoundedOutcome()
        throws {
        let fixture = try makeFixture("unavailable")
        let confirmation = manualConfirmation(
            product: 160,
            command: 161,
            name: "Unavailable"
        )

        let incomplete = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture, writeState: .migrationIncomplete)
        )
        let nonDurable = consumer.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture, writeState: .nonDurable)
        )

        XCTAssertEqual(
            incomplete.outcome,
            .unavailable(
                requestedProductID: productID(160),
                reason: .productAuthority(.migrationIncomplete)
            )
        )
        XCTAssertEqual(
            nonDurable.outcome,
            .unavailable(
                requestedProductID: productID(160),
                reason: .productAuthority(.durableAuthorityUnavailable)
            )
        )
        XCTAssertEqual(try countProducts(fixture), 0)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testFailedCommitIsAttemptedOnceAndNeverSilentlyRetried()
        throws {
        let fixture = try makeFixture("no-retry")
        var commitAttempts = 0
        let authority = ProductStateProductCommandAuthority(
            products: fixture.repositories.products,
            coordinator: ProductStateCommandCoordinator(
                repositories: fixture.repositories
            ),
            writeState: .writableTarget,
            commitPrepared: { prepared in
                commitAttempts += 1
                fixture.context.rollback()
                return ProductStateTransactionResult(
                    commandResult: .unavailable(
                        commandID: prepared.commandID,
                        reason: .durableAuthorityUnavailable
                    ),
                    preparedResult: prepared,
                    disposition: .rolledBack(.saveFailed)
                )
            }
        )

        let result = consumer.confirmTargetAcquisition(
            manualConfirmation(
                product: 170,
                command: 171,
                name: "One Attempt"
            ),
            using: authority
        )

        XCTAssertEqual(commitAttempts, 1)
        XCTAssertEqual(
            result.outcome,
            .unavailable(
                requestedProductID: productID(170),
                reason: .productAuthority(.durableAuthorityUnavailable)
            )
        )
        XCTAssertEqual(result.commandDiagnostic?.failure, .saveFailed)
        XCTAssertEqual(try countProducts(fixture), 0)
    }

    func testCameraViewModelPreservesBarcodeConfirmationPresentationState()
        throws {
        let fixture = try makeFixture("camera-state")
        let viewModel = CameraViewModel()
        let observation = barcodeObservation(180, value: "314159265358")
        let candidate = barcodeCandidate(
            181,
            name: "Camera Reviewed Barcode",
            barcode: observation.value
        )
        viewModel.confirmedBarcodeResult = observation

        let confirmation = try XCTUnwrap(
            viewModel.prepareTargetAcquisitionConfirmation(
                for: candidate,
                productID: productID(182),
                commandID: commandID(183),
                effectiveAt: instant,
                confirmed: true
            )
        )
        XCTAssertEqual(
            viewModel.targetAcquisitionPresentationState,
            .awaitingAcquisitionConfirmation(confirmation)
        )

        let result = viewModel.confirmTargetAcquisition(
            confirmation,
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(
            result.outcome,
            .created(productID: productID(182), revision: 1)
        )
        XCTAssertEqual(
            viewModel.targetAcquisitionPresentationState,
            .acquisitionResult(result)
        )
        XCTAssertEqual(result.confirmation.evidence, confirmation.evidence)
    }

    func testAutocompleteCustomConfirmationStatePreservesSelection() async throws {
        let viewModel = AddProductAutocompleteViewModel(
            suggestionProvider: { _, _, _ in [] },
            slowSearchDelay: { }
        )
        viewModel.updateQuery(
            "Reviewed Custom Selection",
            localeIdentifier: "en"
        )
        try await waitUntil { viewModel.phase == .noMatch }
        let selection = try XCTUnwrap(viewModel.selectCustomProduct())

        let confirmation = try XCTUnwrap(
            viewModel.prepareTargetAcquisitionConfirmation(
                productID: productID(190),
                commandID: commandID(191),
                effectiveAt: instant,
                imageData: Data([0x19]),
                confirmed: true
            )
        )

        XCTAssertEqual(
            confirmation.evidence,
            .custom(selection: selection, imageData: Data([0x19]))
        )
        XCTAssertEqual(
            viewModel.targetAcquisitionPresentationState,
            .awaitingAcquisitionConfirmation(confirmation)
        )
    }

    func testProductKnowledgeBuildsEvidenceWithoutLifecyclePersistence()
        throws {
        let service = ProductKnowledgeService()
        let observation = barcodeObservation(200, value: "271828182845")
        let barcode = barcodeCandidate(
            201,
            name: "Knowledge Candidate",
            barcode: observation.value
        )
        XCTAssertEqual(
            service.targetBarcodeAcquisitionEvidence(
                candidate: barcode,
                observation: observation,
                fallbackImageData: Data([0x20])
            ),
            .barcode(
                candidate: barcode,
                observation: observation,
                fallbackImageData: Data([0x20])
            )
        )

        let ai = ProductCandidate(
            id: uuid(202),
            name: "AI Knowledge Candidate",
            confidence: 0.91,
            source: .ai,
            imageData: Data([0x21])
        )
        let recognition = RecognitionResult(
            id: uuid(203),
            status: .recognized,
            candidates: [ai],
            message: "Reviewed",
            inputSource: .cameraCapture,
            createdAt: instant
        )
        XCTAssertEqual(
            service.targetAIReviewedAcquisitionEvidence(
                candidate: ai,
                recognition: recognition,
                barcodeObservation: nil,
                fallbackImageData: nil
            ),
            .aiReviewed(
                candidate: ai,
                recognition: recognition,
                barcodeObservation: nil,
                fallbackImageData: nil
            )
        )
        XCTAssertNil(
            service.targetBarcodeAcquisitionEvidence(
                candidate: barcode,
                observation: barcodeObservation(
                    204,
                    value: "000000000000"
                ),
                fallbackImageData: nil
            )
        )
        XCTAssertNil(
            service.targetBarcodeAcquisitionEvidence(
                candidate: ProductCandidate(
                    id: uuid(205),
                    name: "AI candidate wrapped as barcode",
                    source: .ai,
                    barcode: observation.value
                ),
                observation: observation,
                fallbackImageData: nil
            )
        )
    }

    func testLibraryOnlyAcquisitionLeavesUnrelatedPlanValueUnchanged()
        throws {
        let fixture = try makeFixture("plan-unchanged")
        let plan = ProductStateShoppingPlan(
            id: planID(210),
            sourceListID: listID(211),
            sourceRevision: ProductStateListRevision(value: 12),
            includedEntries: [
                ProductStateListEntryIdentity(
                    id: entryID(212),
                    listID: listID(211),
                    productID: productID(213)
                )
            ],
            exclusions: [],
            status: .ready
        )
        let before = plan

        let result = consumer.confirmTargetAcquisition(
            manualConfirmation(
                product: 214,
                command: 215,
                name: "Unrelated Library Product"
            ),
            using: makeAuthority(fixture)
        )

        XCTAssertEqual(plan, before)
        XCTAssertEqual(
            result.outcome,
            .created(productID: productID(214), revision: 1)
        )
        XCTAssertEqual(result.commandDiagnostic?.affectedListCount, 0)
        XCTAssertEqual(try countLists(fixture), 0)
        XCTAssertEqual(try countEntries(fixture), 0)
    }

    func testEquivalentConfirmationsProduceDeterministicOutcomeAndState()
        throws {
        let first = try runDeterministicFixture("determinism-a")
        let second = try runDeterministicFixture("determinism-b")

        XCTAssertEqual(first.result, second.result)
        XCTAssertEqual(first.productID, second.productID)
        XCTAssertEqual(first.revision, second.revision)
        XCTAssertEqual(first.name, second.name)
        XCTAssertEqual(first.lifecycle, second.lifecycle)
    }

    func testStaticBoundaryKeepsPersistenceInTargetAuthorityAfterActivation()
        throws {
        let root = repositoryRoot
        let coordinator = try source(
            "WayTask/Persistence/AddProductSaveCoordinator.swift",
            root: root
        )
        let cameraView = try source("CameraView.swift", root: root)
        let productView = try source("ProductListView.swift", root: root)
        let startup = try source(
            "WayTask/Persistence/WayTaskStartupPersistence.swift",
            root: root
        )
        let app = try source("WayTask/WayTaskApp.swift", root: root)
        let content = try source("WayTask/ContentView.swift", root: root)
        let targetSection = try XCTUnwrap(
            coordinator.components(
                separatedBy: "/// T-15 target acquisition consumer."
            ).last?.components(
                separatedBy: "private func validatePersistedIdentity"
            ).first
        )

        XCTAssertTrue(targetSection.contains("authority.acquire("))
        XCTAssertTrue(targetSection.contains("authority.restoreToLibrary("))
        XCTAssertFalse(targetSection.contains("ModelContext("))
        XCTAssertFalse(targetSection.contains(".save()"))
        XCTAssertFalse(targetSection.contains("ProductStateTransactionCoordinator("))
        XCTAssertFalse(targetSection.contains("addTargetEntry("))
        XCTAssertFalse(targetSection.contains("retry"))
        XCTAssertTrue(cameraView.contains("confirmTargetAcquisition("))
        XCTAssertFalse(cameraView.contains("ModelContext"))
        XCTAssertFalse(cameraView.contains("modelContext"))
        XCTAssertFalse(cameraView.contains(".save()"))
        XCTAssertFalse(
            cameraView.contains("ProductStateTransactionCoordinator(")
        )
        XCTAssertFalse(
            cameraView.contains("ProductStateProductCommandAuthority")
        )
        XCTAssertFalse(productView.contains("confirmTargetAcquisition("))
        XCTAssertFalse(startup.contains("confirmTargetAcquisition("))
        XCTAssertFalse(app.contains("ProductStateProductCommandAuthority"))
        XCTAssertFalse(content.contains("ProductStateProductCommandAuthority"))
    }

    // MARK: - Fixtures

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let repositories: ProductStateRepositories
    }

    private struct DeterministicResult {
        let result: ProductAcquisitionResult
        let productID: UUID
        let revision: UInt64
        let name: String
        let lifecycle: String
    }

    private let instant = Date(timeIntervalSince1970: 1_780_000_000)
    private let consumer = AddProductSaveCoordinator()

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeFixture(_ name: String) throws -> Fixture {
        let schema = WayTaskModelContainer.inactiveTargetProductStateSchema
        let configuration = ModelConfiguration(
            "WT033A-T15-\(name)-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return Fixture(
            container: container,
            context: context,
            repositories: ProductStateRepositories(modelContext: context)
        )
    }

    private func makeAuthority(
        _ fixture: Fixture,
        writeState: ProductStateProductCommandWriteState = .writableTarget
    ) -> ProductStateProductCommandAuthority {
        ProductStateProductCommandAuthority(
            repositories: fixture.repositories,
            transactionCoordinator: ProductStateTransactionCoordinator(
                modelContext: fixture.context
            ),
            writeState: writeState
        )
    }

    private func makeProduct(
        _ value: Int,
        revision: UInt64,
        lifecycle: ProductLibraryLifecycle = .active,
        name: String = "Synthetic Product",
        barcode: String? = nil,
        catalogID: String? = nil,
        removedAt: Date? = nil
    ) -> WayTaskSchemaV4.Product {
        WayTaskSchemaV4.Product(
            id: uuid(value),
            revision: revision,
            libraryLifecycleRawValue: lifecycle.rawValue,
            libraryRemovedAt: removedAt,
            name: name,
            barcode: barcode,
            sourceRawValue: ProductSource.manual.rawValue,
            catalogProductIDRawValue: catalogID,
            createdAt: instant.addingTimeInterval(-2_000),
            updatedAt: instant.addingTimeInterval(-1_000)
        )
    }

    private func manualConfirmation(
        product: Int,
        command: Int,
        name: String
    ) -> ProductAcquisitionConfirmation {
        ProductAcquisitionConfirmation(
            productID: productID(product),
            commandID: commandID(command),
            effectiveAt: instant,
            evidence: .manual(name: name, imageData: nil),
            confirmed: true
        )
    }

    private func barcodeConfirmation(
        product: Int,
        command: Int,
        candidate: Int,
        observation: Int,
        barcode: String
    ) -> ProductAcquisitionConfirmation {
        let observed = barcodeObservation(observation, value: barcode)
        return ProductAcquisitionConfirmation(
            productID: productID(product),
            commandID: commandID(command),
            effectiveAt: instant,
            evidence: .barcode(
                candidate: barcodeCandidate(
                    candidate,
                    name: "Reviewed Barcode",
                    barcode: barcode
                ),
                observation: observed,
                fallbackImageData: nil
            ),
            confirmed: true
        )
    }

    private func barcodeCandidate(
        _ value: Int,
        name: String,
        barcode: String
    ) -> ProductCandidate {
        ProductCandidate(
            id: uuid(value),
            name: name,
            brand: "Synthetic Brand",
            category: "Synthetic Category",
            source: .barcode,
            productHints: ["Synthetic hint"],
            imageData: Data([UInt8(value % 255)]),
            barcode: barcode
        )
    }

    private func barcodeObservation(
        _ value: Int,
        value barcode: String
    ) -> BarcodeResult {
        BarcodeResult(
            id: uuid(value),
            value: barcode,
            type: .ean13,
            scannedAt: instant.addingTimeInterval(-2),
            confidence: 0.99
        )
    }

    private func catalogSelection() -> AddProductCatalogSelection {
        AddProductCatalogSelection(
            result: ProductSearchResult(
                productID: ProductID("milk_3_percent"),
                displayName: "חלב 3%",
                displayLocale: "he",
                secondaryName: "חלב",
                categoryID: ProductCategoryID("dairy"),
                categoryDisplayName: "מוצרי חלב",
                iconKey: "product.dairy",
                matchedRecordAuthority: .primaryDisplayName,
                matchType: .exact,
                matchedLocale: "he"
            ),
            preselectionQuery: "חלב"
        )
    }

    private func fetchProduct(
        _ fixture: Fixture,
        id value: Int
    ) throws -> WayTaskSchemaV4.Product {
        let context = verificationContext(fixture)
        let id = uuid(value)
        return try XCTUnwrap(
            try context.fetch(
                FetchDescriptor<WayTaskSchemaV4.Product>(
                    predicate: #Predicate { $0.id == id }
                )
            ).first
        )
    }

    private func verificationContext(_ fixture: Fixture) -> ModelContext {
        let context = ModelContext(fixture.container)
        context.autosaveEnabled = false
        return context
    }

    private func countProducts(_ fixture: Fixture) throws -> Int {
        try verificationContext(fixture).fetchCount(
            FetchDescriptor<WayTaskSchemaV4.Product>()
        )
    }

    private func countLists(_ fixture: Fixture) throws -> Int {
        try verificationContext(fixture).fetchCount(
            FetchDescriptor<WayTaskSchemaV4.ShoppingList>()
        )
    }

    private func countEntries(_ fixture: Fixture) throws -> Int {
        try verificationContext(fixture).fetchCount(
            FetchDescriptor<WayTaskSchemaV4.ShoppingListEntry>()
        )
    }

    private func countHistory(_ fixture: Fixture) throws -> Int {
        try verificationContext(fixture).fetchCount(
            FetchDescriptor<WayTaskSchemaV4.ProductHistoryEvent>()
        )
    }

    private func runDeterministicFixture(
        _ name: String
    ) throws -> DeterministicResult {
        let fixture = try makeFixture(name)
        let result = consumer.confirmTargetAcquisition(
            manualConfirmation(
                product: 220,
                command: 221,
                name: "Deterministic Product"
            ),
            using: makeAuthority(fixture)
        )
        let product = try fetchProduct(fixture, id: 220)
        return DeterministicResult(
            result: result,
            productID: product.id,
            revision: product.revision,
            name: product.name,
            lifecycle: product.libraryLifecycleRawValue
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            guard Date() < deadline else {
                throw WaitTimeout()
            }
            await Task.yield()
        }
    }

    private func source(_ relativePath: String, root: URL) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func productID(_ value: Int) -> ProductStateProductID {
        ProductStateProductID(rawValue: uuid(value))
    }

    private func listID(_ value: Int) -> ProductStateListID {
        ProductStateListID(rawValue: uuid(value))
    }

    private func entryID(_ value: Int) -> ProductStateListEntryID {
        ProductStateListEntryID(rawValue: uuid(value))
    }

    private func planID(_ value: Int) -> ProductStatePlanID {
        ProductStatePlanID(rawValue: uuid(value))
    }

    private func commandID(_ value: Int) -> ProductStateCommandID {
        ProductStateCommandID(rawValue: uuid(value))
    }

    private func historyID(_ value: Int) -> ProductStateHistoryEventID {
        ProductStateHistoryEventID(rawValue: uuid(value))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }
}

private struct WaitTimeout: Error {}
