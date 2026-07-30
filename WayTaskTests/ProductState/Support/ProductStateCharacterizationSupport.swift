import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import WayTask

// This file is intentionally located in the file-system-synchronized
// WayTaskTests group. Nothing in this support layer is compiled into WayTask.

// MARK: - Privacy-safe support errors

enum ProductStateCharacterizationSupportError: Error, LocalizedError {
    case manifestResourceUnavailable
    case manifestSourceUnavailable
    case manifestDecodeFailed
    case manifestValidationFailed(code: String, caseID: String?)
    case ownedDirectoryFailure(code: String, caseID: String)
    case containerFailure(generation: String, caseID: String)
    case workingCopyFailure(code: String, caseID: String)
    case semanticSnapshotFailure(code: String, caseID: String)
    case attachmentRejected(code: String, caseID: String)
    case invalidPerformanceConfiguration

    var errorDescription: String? {
        switch self {
        case .manifestResourceUnavailable:
            return "Product State manifest resource is unavailable."
        case .manifestSourceUnavailable:
            return "Product State manifest source is unavailable."
        case .manifestDecodeFailed:
            return "Product State manifest decoding failed."
        case .manifestValidationFailed(let code, let caseID):
            return Self.message(
                prefix: "Product State manifest validation failed",
                code: code,
                caseID: caseID
            )
        case .ownedDirectoryFailure(let code, let caseID):
            return Self.message(
                prefix: "Product State owned-directory operation failed",
                code: code,
                caseID: caseID
            )
        case .containerFailure(let generation, let caseID):
            return Self.message(
                prefix: "Product State container creation failed",
                code: generation,
                caseID: caseID
            )
        case .workingCopyFailure(let code, let caseID):
            return Self.message(
                prefix: "Product State working-copy operation failed",
                code: code,
                caseID: caseID
            )
        case .semanticSnapshotFailure(let code, let caseID):
            return Self.message(
                prefix: "Product State semantic snapshot failed",
                code: code,
                caseID: caseID
            )
        case .attachmentRejected(let code, let caseID):
            return Self.message(
                prefix: "Product State attachment rejected",
                code: code,
                caseID: caseID
            )
        case .invalidPerformanceConfiguration:
            return "Product State performance sampling configuration is invalid."
        }
    }

    private static func message(
        prefix: String,
        code: String,
        caseID: String?
    ) -> String {
        let safeCode = safeToken(code) ?? "unspecified"
        guard let caseID, let safeCaseID = safeToken(caseID) else {
            return "\(prefix) [\(safeCode)]."
        }
        return "\(prefix) [\(safeCode)] for \(safeCaseID)."
    }

    static func safeToken(_ value: String) -> String? {
        guard !value.isEmpty, value.count <= 96 else {
            return nil
        }
        let allowed = CharacterSet(
            charactersIn:
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."
        )
        guard value.unicodeScalars.allSatisfy(allowed.contains) else {
            return nil
        }
        return value
    }
}

// MARK: - Strict manifest decoding

private struct ProductStateDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension Decoder {
    func rejectUnknownKeys(_ allowedKeys: Set<String>) throws {
        let container = try container(
            keyedBy: ProductStateDynamicCodingKey.self
        )
        let unknownKeys = container.allKeys
            .map(\.stringValue)
            .filter { !allowedKeys.contains($0) }
        guard unknownKeys.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: codingPath,
                    debugDescription:
                        "Unknown required manifest structure field."
                )
            )
        }
    }
}

indirect enum ProductStateManifestJSONValue: Decodable, Equatable {
    case null
    case boolean(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([ProductStateManifestJSONValue])
    case object([String: ProductStateManifestJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(
            [ProductStateManifestJSONValue].self
        ) {
            self = .array(value)
        } else if let value = try? container.decode(
            [String: ProductStateManifestJSONValue].self
        ) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported manifest value."
            )
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    var stringArrayValue: [String]? {
        guard case .array(let values) = self else {
            return nil
        }
        let strings = values.compactMap(\.stringValue)
        return strings.count == values.count ? strings : nil
    }

    func allStrings() -> [String] {
        switch self {
        case .null, .boolean, .integer, .number:
            return []
        case .string(let value):
            return [value]
        case .array(let values):
            return values.flatMap { $0.allStrings() }
        case .object(let values):
            return values.keys.sorted().flatMap {
                values[$0]?.allStrings() ?? []
            }
        }
    }
}

enum ProductStateExpectationKind: String, Decodable, Equatable {
    case currentBehavior
}

enum ProductStateOptionalPresence: String, Decodable, Equatable {
    case present
    case absent
}

struct ProductStateManifestTraceability: Decodable, Equatable {
    let currentBehaviorIDs: [String]
    let knownDefectIDs: [String]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case currentBehaviorIDs
        case knownDefectIDs
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentBehaviorIDs = try container.decode(
            [String].self,
            forKey: .currentBehaviorIDs
        )
        knownDefectIDs = try container.decode(
            [String].self,
            forKey: .knownDefectIDs
        )
    }
}

struct ProductStateManifestOptionalFieldState: Decodable, Equatable {
    let recordID: String?
    let field: String
    let presence: ProductStateOptionalPresence
    let value: ProductStateManifestJSONValue?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case recordID
        case field
        case presence
        case value
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordID = try container.decodeIfPresent(
            String.self,
            forKey: .recordID
        )
        field = try container.decode(String.self, forKey: .field)
        presence = try container.decode(
            ProductStateOptionalPresence.self,
            forKey: .presence
        )
        value = try container.decodeIfPresent(
            ProductStateManifestJSONValue.self,
            forKey: .value
        )
    }
}

struct ProductStateManifestRecord: Decodable, Equatable {
    let recordType: String
    let id: String
    let fields: [String: ProductStateManifestJSONValue]
    let optionalFieldStates: [ProductStateManifestOptionalFieldState]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case recordType
        case id
        case fields
        case optionalFieldStates
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordType = try container.decode(
            String.self,
            forKey: .recordType
        )
        id = try container.decode(String.self, forKey: .id)
        fields = try container.decode(
            [String: ProductStateManifestJSONValue].self,
            forKey: .fields
        )
        optionalFieldStates = try container.decode(
            [ProductStateManifestOptionalFieldState].self,
            forKey: .optionalFieldStates
        )
    }
}

struct ProductStateManifestFieldExpectation: Decodable, Equatable {
    let recordID: String
    let field: String
    let value: ProductStateManifestJSONValue

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case recordID
        case field
        case value
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordID = try container.decode(String.self, forKey: .recordID)
        field = try container.decode(String.self, forKey: .field)
        value = try container.decode(
            ProductStateManifestJSONValue.self,
            forKey: .value
        )
    }
}

struct ProductStateManifestRelationshipCount: Decodable, Equatable {
    let recordID: String
    let relationship: String
    let count: Int

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case recordID
        case relationship
        case count
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordID = try container.decode(String.self, forKey: .recordID)
        relationship = try container.decode(
            String.self,
            forKey: .relationship
        )
        count = try container.decode(Int.self, forKey: .count)
    }
}

struct ProductStateManifestExpectedCurrentBehavior: Decodable, Equatable {
    let expectationKind: ProductStateExpectationKind
    let counts: [String: Int]
    let fieldValues: [ProductStateManifestFieldExpectation]
    let optionalFieldStates: [ProductStateManifestOptionalFieldState]
    let relationshipCounts: [ProductStateManifestRelationshipCount]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case expectationKind
        case counts
        case fieldValues
        case optionalFieldStates
        case relationshipCounts
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expectationKind = try container.decode(
            ProductStateExpectationKind.self,
            forKey: .expectationKind
        )
        counts = try container.decode(
            [String: Int].self,
            forKey: .counts
        )
        fieldValues = try container.decode(
            [ProductStateManifestFieldExpectation].self,
            forKey: .fieldValues
        )
        optionalFieldStates = try container.decode(
            [ProductStateManifestOptionalFieldState].self,
            forKey: .optionalFieldStates
        )
        relationshipCounts = try container.decode(
            [ProductStateManifestRelationshipCount].self,
            forKey: .relationshipCounts
        )
    }
}

struct ProductStateManifestCase: Decodable, Equatable {
    let caseID: String
    let purpose: String
    let traceability: ProductStateManifestTraceability
    let operation: String
    let records: [ProductStateManifestRecord]
    let expectedCurrentBehavior:
        ProductStateManifestExpectedCurrentBehavior

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case caseID
        case purpose
        case traceability
        case operation
        case records
        case expectedCurrentBehavior
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        caseID = try container.decode(String.self, forKey: .caseID)
        purpose = try container.decode(String.self, forKey: .purpose)
        traceability = try container.decode(
            ProductStateManifestTraceability.self,
            forKey: .traceability
        )
        operation = try container.decode(String.self, forKey: .operation)
        records = try container.decode(
            [ProductStateManifestRecord].self,
            forKey: .records
        )
        expectedCurrentBehavior = try container.decode(
            ProductStateManifestExpectedCurrentBehavior.self,
            forKey: .expectedCurrentBehavior
        )
    }
}

struct ProductStateCurrentBehaviorManifest: Decodable, Equatable {
    let manifestSchemaVersion: Int
    let manifestID: String
    let expectationKind: ProductStateExpectationKind
    let syntheticNamespace: String
    let fixedUTCTimestamps: [String: String]
    let optionalFieldEncoding: [String: String]
    let cases: [ProductStateManifestCase]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case manifestSchemaVersion
        case manifestID
        case expectationKind
        case syntheticNamespace
        case fixedUTCTimestamps
        case optionalFieldEncoding
        case cases
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifestSchemaVersion = try container.decode(
            Int.self,
            forKey: .manifestSchemaVersion
        )
        manifestID = try container.decode(
            String.self,
            forKey: .manifestID
        )
        expectationKind = try container.decode(
            ProductStateExpectationKind.self,
            forKey: .expectationKind
        )
        syntheticNamespace = try container.decode(
            String.self,
            forKey: .syntheticNamespace
        )
        fixedUTCTimestamps = try container.decode(
            [String: String].self,
            forKey: .fixedUTCTimestamps
        )
        optionalFieldEncoding = try container.decode(
            [String: String].self,
            forKey: .optionalFieldEncoding
        )
        cases = try container.decode(
            [ProductStateManifestCase].self,
            forKey: .cases
        )
    }
}

private final class ProductStateTestBundleToken: NSObject {}

struct ProductStateLoadedManifest {
    let manifest: ProductStateCurrentBehaviorManifest
    let bundledData: Data
}

enum ProductStateManifestLoader {
    static let resourceName = "product-state-current-behavior-v1"
    static let resourceExtension = "json"

    static func loadFromTestBundle() throws -> ProductStateLoadedManifest {
        let bundle = Bundle(for: ProductStateTestBundleToken.self)
        guard let url = bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension
        ) else {
            throw ProductStateCharacterizationSupportError
                .manifestResourceUnavailable
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ProductStateCharacterizationSupportError
                .manifestResourceUnavailable
        }
        return ProductStateLoadedManifest(
            manifest: try decodeAndValidate(data),
            bundledData: data
        )
    }

    static func sourceManifestData() throws -> Data {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(
                "\(resourceName).\(resourceExtension)",
                isDirectory: false
            )
        do {
            return try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        } catch {
            throw ProductStateCharacterizationSupportError
                .manifestSourceUnavailable
        }
    }

    static func decodeAndValidate(
        _ data: Data
    ) throws -> ProductStateCurrentBehaviorManifest {
        let manifest: ProductStateCurrentBehaviorManifest
        do {
            manifest = try JSONDecoder().decode(
                ProductStateCurrentBehaviorManifest.self,
                from: data
            )
        } catch {
            throw ProductStateCharacterizationSupportError
                .manifestDecodeFailed
        }
        try ProductStateManifestValidator.validate(manifest)
        return manifest
    }
}

// MARK: - Manifest validation

enum ProductStateManifestValidator {
    static let requiredCaseIDs: Set<String> = [
        "flags-00",
        "flags-01",
        "flags-10",
        "flags-11",
        "multi-list-shared-compatibility",
        "duplicate-entry",
        "tombstone-weekly-completed-recent",
        "tombstone-active-session",
        "orphan-existing-product-id",
        "orphan-missing-product",
        "completed-recent-only",
        "active-session-collected",
        "finished-session-no-reconcile",
        "session-missing-item",
        "location-compatibility",
        "catalog-active",
        "catalog-tombstone",
        "custom-product",
        "history-compatibility-key"
    ]

    private static let expectedCountKeys: Set<String> = [
        "GeoLocation",
        "ShoppingItem",
        "Product",
        "ShoppingList",
        "ShoppingListEntry",
        "ProductHistory",
        "ProductKnowledge",
        "ShoppingSession"
    ]

    private static let allowedOperations: Set<String> = [
        "observe",
        "runStartupRepair",
        "deleteProductFromLibrary"
    ]

    private static let allowedRecordFields: [String: Set<String>] = [
        "Product": [
            "name",
            "legacyShoppingItemID",
            "catalogProductIDRawValue",
            "catalogDisplayNameSnapshot",
            "catalogDisplayLocaleSnapshot",
            "catalogCategoryIDSnapshotRawValue",
            "catalogCategoryDisplayNameSnapshot",
            "catalogIconKeySnapshot",
            "catalogSnapshotUpdatedAt"
        ],
        "ShoppingItem": [
            "name",
            "isCompleted",
            "barcode"
        ],
        "ShoppingList": [
            "title",
            "kindRawValue"
        ],
        "ShoppingListEntry": [
            "shoppingListID",
            "productID",
            "legacyShoppingItemID",
            "isChecked"
        ],
        "ProductHistory": [
            "productKey",
            "productName",
            "barcode",
            "addCount"
        ],
        "ShoppingSession": [
            "isActive",
            "itemIDs",
            "collectedItemIDs"
        ],
        "GeoLocation": [
            "title",
            "geometryFixture",
            "shoppingItemIDs"
        ]
    ]

    private static let allowedOptionalFields: [String: Set<String>] = [
        "Product": [
            "legacyShoppingItemID",
            "deletedAt",
            "catalogProductIDRawValue",
            "catalogDisplayNameSnapshot",
            "catalogDisplayLocaleSnapshot",
            "catalogCategoryIDSnapshotRawValue",
            "catalogCategoryDisplayNameSnapshot",
            "catalogIconKeySnapshot",
            "catalogSnapshotUpdatedAt"
        ],
        "ShoppingItem": ["barcode"],
        "ShoppingList": [],
        "ShoppingListEntry": ["product"],
        "ProductHistory": ["barcode", "lastCompletedDate"],
        "ShoppingSession": ["finishedAt", "shoppingListID"],
        "GeoLocation": []
    ]

    private static let allowedExpectedFields: Set<String> = [
        "isCompleted",
        "isChecked",
        "productID",
        "isActive",
        "itemIDs",
        "collectedItemIDs",
        "remainingItemCount",
        "addCount",
        "productKey",
        "catalogSnapshotFieldCount",
        "catalogProductIDRawValue"
    ]

    private static let allowedExpectedOptionalFields: Set<String> = [
        "product",
        "deletedAt",
        "finishedAt",
        "lastCompletedDate",
        "catalogProductIDRawValue"
    ]

    private static let allowedRelationships: Set<String> = [
        "referencingShoppingListEntries",
        "entriesWithSameProductID",
        "shoppingListEntries",
        "weeklyEntries",
        "completedAndRecentEntries",
        "unavailableItemIDs",
        "shoppingItems"
    ]

    private static let UUIDFieldNames: Set<String> = [
        "legacyShoppingItemID",
        "shoppingListID",
        "productID"
    ]

    private static let UUIDArrayFieldNames: Set<String> = [
        "itemIDs",
        "collectedItemIDs",
        "shoppingItemIDs"
    ]

    private static let forbiddenDataFields: Set<String> = [
        "imageData",
        "thumbnailData",
        "credentials",
        "credential",
        "accountIdentifier",
        "accountID",
        "latitude",
        "longitude",
        "notes",
        "storeName",
        "selectedStoreName"
    ]

    private static let targetSchemaFields: Set<String> = [
        "productState",
        "availabilityState",
        "purchaseState",
        "listRevision",
        "sourceEntryIDs",
        "tombstoneReason",
        "restoredAt",
        "abandonedAt"
    ]

    static func validate(
        _ manifest: ProductStateCurrentBehaviorManifest
    ) throws {
        guard manifest.manifestSchemaVersion == 1 else {
            throw validationError("schema-version")
        }
        guard
            manifest.manifestID
                == "wt032b-product-state-current-behavior-v1",
            manifest.syntheticNamespace == "WT032B_SYNTHETIC_V1",
            manifest.expectationKind == .currentBehavior
        else {
            throw validationError("manifest-identity")
        }
        guard
            Set(manifest.fixedUTCTimestamps.keys)
                == [
                    "baseline",
                    "tombstone",
                    "sessionFinish",
                    "historyEvent"
                ],
            Set(manifest.optionalFieldEncoding.keys)
                == ["present", "absent"]
        else {
            throw validationError("manifest-contract")
        }
        for timestamp in manifest.fixedUTCTimestamps.values {
            try validateTimestamp(timestamp, caseID: nil)
        }

        let caseIDs = manifest.cases.map(\.caseID)
        guard Set(caseIDs) == requiredCaseIDs else {
            throw validationError("required-case-coverage")
        }
        guard Set(caseIDs).count == caseIDs.count else {
            throw validationError("duplicate-case-id")
        }

        var recordIDs = Set<String>()
        for fixtureCase in manifest.cases {
            try validate(fixtureCase, recordIDs: &recordIDs)
        }
    }

    private static func validate(
        _ fixtureCase: ProductStateManifestCase,
        recordIDs: inout Set<String>
    ) throws {
        let caseID = fixtureCase.caseID
        guard
            ProductStateCharacterizationSupportError.safeToken(caseID) != nil,
            !fixtureCase.purpose
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty,
            fixtureCase.purpose.count <= 240,
            allowedOperations.contains(fixtureCase.operation)
        else {
            throw validationError("case-contract", caseID: caseID)
        }
        guard
            !fixtureCase.traceability.currentBehaviorIDs.isEmpty,
            !fixtureCase.traceability.knownDefectIDs.isEmpty,
            fixtureCase.traceability.currentBehaviorIDs.allSatisfy(
                validCurrentBehaviorID
            ),
            fixtureCase.traceability.knownDefectIDs.allSatisfy(
                validKnownDefectID
            )
        else {
            throw validationError("traceability", caseID: caseID)
        }
        guard
            fixtureCase.expectedCurrentBehavior.expectationKind
                == .currentBehavior,
            Set(
                fixtureCase.expectedCurrentBehavior.counts.keys
            ) == expectedCountKeys,
            fixtureCase.expectedCurrentBehavior.counts.values
                .allSatisfy({ $0 >= 0 })
        else {
            throw validationError("current-expectation", caseID: caseID)
        }

        for record in fixtureCase.records {
            try validate(record, caseID: caseID)
            guard recordIDs.insert(record.id).inserted else {
                throw validationError(
                    "duplicate-record-id",
                    caseID: caseID
                )
            }
        }

        for expectation in
            fixtureCase.expectedCurrentBehavior.fieldValues
        {
            try validateUUID(expectation.recordID, caseID: caseID)
            guard allowedExpectedFields.contains(expectation.field) else {
                throw validationError(
                    "unknown-expected-field",
                    caseID: caseID
                )
            }
            try validateUUIDValueIfNeeded(
                field: expectation.field,
                value: expectation.value,
                caseID: caseID
            )
            try validateSafeValue(
                expectation.value,
                field: expectation.field,
                caseID: caseID
            )
        }

        for state in
            fixtureCase.expectedCurrentBehavior.optionalFieldStates
        {
            guard let recordID = state.recordID else {
                throw validationError(
                    "expected-optional-record",
                    caseID: caseID
                )
            }
            try validateUUID(recordID, caseID: caseID)
            guard allowedExpectedOptionalFields.contains(state.field) else {
                throw validationError(
                    "unknown-expected-optional",
                    caseID: caseID
                )
            }
            try validateOptionalState(state, caseID: caseID)
        }

        for relationship in
            fixtureCase.expectedCurrentBehavior.relationshipCounts
        {
            try validateUUID(relationship.recordID, caseID: caseID)
            guard
                allowedRelationships.contains(relationship.relationship),
                relationship.count >= 0
            else {
                throw validationError(
                    "relationship-count",
                    caseID: caseID
                )
            }
        }
    }

    private static func validate(
        _ record: ProductStateManifestRecord,
        caseID: String
    ) throws {
        try validateUUID(record.id, caseID: caseID)
        guard
            let allowedFields = allowedRecordFields[record.recordType],
            let optionalFields =
                allowedOptionalFields[record.recordType],
            allowedFields.isSuperset(of: record.fields.keys),
            record.optionalFieldStates.allSatisfy({
                optionalFields.contains($0.field)
            })
        else {
            throw validationError("record-field", caseID: caseID)
        }

        for (field, value) in record.fields {
            guard
                !forbiddenDataFields.contains(field),
                !targetSchemaFields.contains(field)
            else {
                throw validationError("forbidden-field", caseID: caseID)
            }
            try validateUUIDValueIfNeeded(
                field: field,
                value: value,
                caseID: caseID
            )
            try validateSafeValue(value, field: field, caseID: caseID)
            if field.hasSuffix("At"),
               let timestamp = value.stringValue
            {
                try validateTimestamp(timestamp, caseID: caseID)
            }
        }

        for state in record.optionalFieldStates {
            guard state.recordID == nil else {
                throw validationError(
                    "record-optional-id",
                    caseID: caseID
                )
            }
            try validateOptionalState(state, caseID: caseID)
        }
    }

    private static func validateOptionalState(
        _ state: ProductStateManifestOptionalFieldState,
        caseID: String
    ) throws {
        switch state.presence {
        case .present:
            guard let value = state.value else {
                throw validationError(
                    "present-without-value",
                    caseID: caseID
                )
            }
            try validateSafeValue(
                value,
                field: state.field,
                caseID: caseID
            )
            if UUIDFieldNames.contains(state.field),
               let string = value.stringValue
            {
                try validateUUID(string, caseID: caseID)
            }
            if state.field.hasSuffix("At"),
               let timestamp = value.stringValue
            {
                try validateTimestamp(timestamp, caseID: caseID)
            }
        case .absent:
            guard state.value == nil else {
                throw validationError(
                    "absent-with-value",
                    caseID: caseID
                )
            }
        }
    }

    private static func validateUUIDValueIfNeeded(
        field: String,
        value: ProductStateManifestJSONValue,
        caseID: String
    ) throws {
        if UUIDFieldNames.contains(field) {
            guard let string = value.stringValue else {
                throw validationError("uuid-value", caseID: caseID)
            }
            try validateUUID(string, caseID: caseID)
        } else if UUIDArrayFieldNames.contains(field) {
            guard let strings = value.stringArrayValue else {
                throw validationError("uuid-array", caseID: caseID)
            }
            for string in strings {
                try validateUUID(string, caseID: caseID)
            }
        }
    }

    private static func validateUUID(
        _ value: String,
        caseID: String
    ) throws {
        guard
            value.hasPrefix("032B"),
            let uuid = UUID(uuidString: value),
            uuid.uuidString == value.uppercased()
        else {
            throw validationError("synthetic-uuid", caseID: caseID)
        }
    }

    private static func validateTimestamp(
        _ value: String,
        caseID: String?
    ) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard
            value.hasSuffix("Z"),
            formatter.date(from: value) != nil
        else {
            throw validationError("fixed-utc-date", caseID: caseID)
        }
    }

    private static func validateSafeValue(
        _ value: ProductStateManifestJSONValue,
        field: String,
        caseID: String
    ) throws {
        if field == "name" || field == "productName" ||
            field == "title"
        {
            guard
                let string = value.stringValue,
                string.hasPrefix("SYNTHETIC_")
            else {
                throw validationError(
                    "non-synthetic-label",
                    caseID: caseID
                )
            }
        }
        if field == "barcode" {
            guard
                let string = value.stringValue,
                string.hasPrefix("SYNTHETIC_BARCODE_TOKEN_")
            else {
                throw validationError(
                    "non-synthetic-barcode",
                    caseID: caseID
                )
            }
        }
        if field == "productKey" {
            guard
                let string = value.stringValue,
                string.hasPrefix("name:synthetic_") ||
                    string.hasPrefix(
                        "barcode:SYNTHETIC_BARCODE_TOKEN_"
                    )
            else {
                throw validationError(
                    "non-synthetic-history-key",
                    caseID: caseID
                )
            }
        }
        let syntheticCatalogStringFields: Set<String> = [
            "catalogProductIDRawValue",
            "catalogDisplayNameSnapshot",
            "catalogDisplayLocaleSnapshot",
            "catalogCategoryIDSnapshotRawValue",
            "catalogCategoryDisplayNameSnapshot",
            "catalogIconKeySnapshot"
        ]
        if syntheticCatalogStringFields.contains(field) {
            guard let string = value.stringValue else {
                throw validationError(
                    "non-synthetic-catalog-value",
                    caseID: caseID
                )
            }
            if field == "catalogDisplayLocaleSnapshot" {
                guard string == "synthetic-locale" else {
                    throw validationError(
                        "non-synthetic-catalog-locale",
                        caseID: caseID
                    )
                }
            } else {
                guard string.hasPrefix("SYNTHETIC_CATALOG_") else {
                    throw validationError(
                        "non-synthetic-catalog-value",
                        caseID: caseID
                    )
                }
            }
        }

        for string in value.allStrings() {
            let lowered = string.lowercased()
            guard
                !lowered.contains("http://"),
                !lowered.contains("https://"),
                !string.contains("@"),
                !lowered.contains("begin private key")
            else {
                throw validationError(
                    "private-value",
                    caseID: caseID
                )
            }
        }
    }

    nonisolated private static func validCurrentBehaviorID(
        _ value: String
    ) -> Bool {
        (1...16).contains(where: {
            value == String(format: "CB-%02d", $0)
        })
    }

    nonisolated private static func validKnownDefectID(
        _ value: String
    ) -> Bool {
        (1...12).contains(where: {
            value == String(format: "KD-%02d", $0)
        })
    }

    private static func validationError(
        _ code: String,
        caseID: String? = nil
    ) -> ProductStateCharacterizationSupportError {
        .manifestValidationFailed(code: code, caseID: caseID)
    }
}

// MARK: - Deterministic synthetic values

enum ProductStateSyntheticValues {
    static let fixtureSeed: UInt64 = 0x032B_0001
    static let locale = Locale(identifier: "en_US_POSIX")
    static let timeZone = TimeZone(secondsFromGMT: 0)!
    static let epoch = Date(timeIntervalSinceReferenceDate: 0)

    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = locale
        value.timeZone = timeZone
        return value
    }

    static func date(secondsAfterEpoch seconds: TimeInterval) -> Date {
        epoch.addingTimeInterval(seconds)
    }

    static func uuid(
        namespace: UInt16,
        index: UInt64
    ) -> UUID {
        precondition(index <= 0xFFFF_FFFF_FFFF)
        let value = String(
            format:
                "032B%04X-0000-4000-8000-%012llX",
            namespace,
            index
        )
        return UUID(uuidString: value)!
    }

    static func sortedUUIDs(_ values: [UUID]) -> [UUID] {
        values.sorted { $0.uuidString < $1.uuidString }
    }

    static func iso8601UTC(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

// MARK: - Owned temporary directories

final class ProductStateOwnedTemporaryDirectory {
    nonisolated(unsafe) private static var nextIdentifier: UInt64 = 0
    private static let identifierLock = NSLock()
    private static let directoryPrefix = "WT032B-ProductState-"

    let caseID: String
    let rootURL: URL
    private(set) var isCleaned = false
    private let fileManager: FileManager

    init(
        caseID: String,
        fileManager: FileManager = .default
    ) throws {
        guard
            ProductStateCharacterizationSupportError.safeToken(caseID)
                != nil
        else {
            throw ProductStateCharacterizationSupportError
                .ownedDirectoryFailure(
                    code: "unsafe-case-id",
                    caseID: "unavailable"
                )
        }
        self.caseID = caseID
        self.fileManager = fileManager

        let identifier = Self.identifierLock.withLock {
            Self.nextIdentifier += 1
            return Self.nextIdentifier
        }
        let component =
            "\(Self.directoryPrefix)\(ProcessInfo.processInfo.processIdentifier)-\(identifier)"
        rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(component, isDirectory: true)
            .standardizedFileURL

        guard Self.isOwnedURL(rootURL, fileManager: fileManager) else {
            throw ProductStateCharacterizationSupportError
                .ownedDirectoryFailure(
                    code: "ownership-boundary",
                    caseID: caseID
                )
        }
        do {
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: false
            )
        } catch {
            throw ProductStateCharacterizationSupportError
                .ownedDirectoryFailure(
                    code: "create-root",
                    caseID: caseID
                )
        }
    }

    func childDirectory(named name: String) throws -> URL {
        guard Self.safeLeafName(name) else {
            throw ProductStateCharacterizationSupportError
                .ownedDirectoryFailure(
                    code: "unsafe-child-name",
                    caseID: caseID
                )
        }
        let url = rootURL
            .appendingPathComponent(name, isDirectory: true)
            .standardizedFileURL
        guard contains(url) else {
            throw ProductStateCharacterizationSupportError
                .ownedDirectoryFailure(
                    code: "child-boundary",
                    caseID: caseID
                )
        }
        do {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: false
            )
        } catch {
            throw ProductStateCharacterizationSupportError
                .ownedDirectoryFailure(
                    code: "create-child",
                    caseID: caseID
                )
        }
        return url
    }

    func storeURL(
        directory: URL? = nil,
        name: String = "ProductState.store"
    ) throws -> URL {
        guard Self.safeLeafName(name) else {
            throw ProductStateCharacterizationSupportError
                .ownedDirectoryFailure(
                    code: "unsafe-store-name",
                    caseID: caseID
                )
        }
        let parent = (directory ?? rootURL).standardizedFileURL
        guard parent == rootURL || contains(parent) else {
            throw ProductStateCharacterizationSupportError
                .ownedDirectoryFailure(
                    code: "store-parent-boundary",
                    caseID: caseID
                )
        }
        let url = parent
            .appendingPathComponent(name, isDirectory: false)
            .standardizedFileURL
        guard contains(url) else {
            throw ProductStateCharacterizationSupportError
                .ownedDirectoryFailure(
                    code: "store-boundary",
                    caseID: caseID
                )
        }
        return url
    }

    func contains(_ url: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path
        return candidatePath == rootPath ||
            candidatePath.hasPrefix(rootPath + "/")
    }

    func cleanup() throws {
        guard !isCleaned else {
            return
        }
        guard Self.isOwnedURL(rootURL, fileManager: fileManager) else {
            throw ProductStateCharacterizationSupportError
                .ownedDirectoryFailure(
                    code: "cleanup-boundary",
                    caseID: caseID
                )
        }
        do {
            if fileManager.fileExists(atPath: rootURL.path) {
                try fileManager.removeItem(at: rootURL)
            }
        } catch {
            throw ProductStateCharacterizationSupportError
                .ownedDirectoryFailure(
                    code: "cleanup-remove",
                    caseID: caseID
                )
        }
        guard !fileManager.fileExists(atPath: rootURL.path) else {
            throw ProductStateCharacterizationSupportError
                .ownedDirectoryFailure(
                    code: "cleanup-verification",
                    caseID: caseID
                )
        }
        isCleaned = true
    }

    deinit {
        try? cleanup()
    }

    private static func isOwnedURL(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        let temporaryPath = fileManager.temporaryDirectory
            .standardizedFileURL.path
        let candidate = url.standardizedFileURL
        return candidate.path.hasPrefix(temporaryPath + "/") &&
            candidate.lastPathComponent.hasPrefix(directoryPrefix)
    }

    private static func safeLeafName(_ value: String) -> Bool {
        guard
            !value.isEmpty,
            value != ".",
            value != "..",
            !value.contains("/"),
            !value.contains("\\")
        else {
            return false
        }
        return ProductStateCharacterizationSupportError.safeToken(value)
            != nil
    }
}

// MARK: - SwiftData containers

enum ProductStateSchemaGeneration: String, CaseIterable {
    case v1
    case v2
    case v3
    case current
}

@MainActor
enum ProductStateTestContainerFactory {
    static func makeInMemoryCurrent(
        caseID: String
    ) throws -> ModelContainer {
        let schema = WayTaskModelContainer.currentSchema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        do {
            return try WayTaskModelContainer.make(
                configurations: [configuration]
            )
        } catch {
            throw ProductStateCharacterizationSupportError
                .containerFailure(
                    generation: "current-memory",
                    caseID: caseID
                )
        }
    }

    static func makeFileBacked(
        generation: ProductStateSchemaGeneration,
        storeURL: URL,
        ownedBy directory: ProductStateOwnedTemporaryDirectory,
        caseID: String
    ) throws -> ModelContainer {
        guard directory.contains(storeURL) else {
            throw ProductStateCharacterizationSupportError
                .containerFailure(
                    generation: "outside-owned-directory",
                    caseID: caseID
                )
        }

        do {
            switch generation {
            case .v1:
                let schema = Schema(
                    versionedSchema: WayTaskSchemaV1.self
                )
                let configuration = configuration(
                    name: "WT032B-v1",
                    schema: schema,
                    storeURL: storeURL
                )
                return try ModelContainer(
                    for: schema,
                    configurations: [configuration]
                )
            case .v2:
                let schema = Schema(
                    versionedSchema: WayTaskSchemaV2.self
                )
                let configuration = configuration(
                    name: "WT032B-v2",
                    schema: schema,
                    storeURL: storeURL
                )
                return try ModelContainer(
                    for: schema,
                    configurations: [configuration]
                )
            case .v3:
                let schema = Schema(
                    versionedSchema: WayTaskSchemaV3.self
                )
                let configuration = configuration(
                    name: "WT032B-v3",
                    schema: schema,
                    storeURL: storeURL
                )
                return try ModelContainer(
                    for: schema,
                    configurations: [configuration]
                )
            case .current:
                let schema = WayTaskModelContainer.currentSchema
                let configuration = configuration(
                    name: "WT032B-current",
                    schema: schema,
                    storeURL: storeURL
                )
                return try WayTaskModelContainer.make(
                    configurations: [configuration]
                )
            }
        } catch let error as ProductStateCharacterizationSupportError {
            throw error
        } catch {
            throw ProductStateCharacterizationSupportError
                .containerFailure(
                    generation: generation.rawValue,
                    caseID: caseID
                )
        }
    }

    private static func configuration(
        name: String,
        schema: Schema,
        storeURL: URL
    ) -> ModelConfiguration {
        ModelConfiguration(
            name,
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
    }
}

@MainActor
final class ProductStateFileBackedContainerLease {
    let caseID: String
    let generation: ProductStateSchemaGeneration
    let ownedDirectory: ProductStateOwnedTemporaryDirectory
    let storeURL: URL
    private(set) var container: ModelContainer?

    init(
        caseID: String,
        generation: ProductStateSchemaGeneration
    ) throws {
        self.caseID = caseID
        self.generation = generation
        ownedDirectory = try ProductStateOwnedTemporaryDirectory(
            caseID: caseID
        )
        storeURL = try ownedDirectory.storeURL()
        do {
            container = try ProductStateTestContainerFactory
                .makeFileBacked(
                    generation: generation,
                    storeURL: storeURL,
                    ownedBy: ownedDirectory,
                    caseID: caseID
                )
        } catch {
            try? ownedDirectory.cleanup()
            throw error
        }
    }

    func releasePersistentReferences() {
        container = nil
    }

    func cleanup() throws {
        guard container == nil else {
            throw ProductStateCharacterizationSupportError
                .ownedDirectoryFailure(
                    code: "container-reference-active",
                    caseID: caseID
                )
        }
        try ownedDirectory.cleanup()
    }
}

// MARK: - Store fingerprints and working copies

struct ProductStateStoreComponentFingerprint: Equatable {
    let role: String
    let byteCount: Int
    let sha256: String
    let modificationTime: TimeInterval
}

struct ProductStateStoreFingerprint: Equatable {
    let components: [ProductStateStoreComponentFingerprint]

    var semanticDigest: String {
        let lines = components.map {
            "\($0.role):\($0.byteCount):\($0.sha256)"
        }.joined(separator: "\n")
        return ProductStateSHA256.hexDigest(
            Data(lines.utf8)
        )
    }
}

enum ProductStateStoreFingerprinting {
    private static let componentSuffixes: [(role: String, suffix: String)] = [
        ("store", ""),
        ("wal", "-wal"),
        ("shm", "-shm"),
        ("journal", "-journal")
    ]

    static func fingerprint(
        storeURL: URL,
        caseID: String,
        fileManager: FileManager = .default
    ) throws -> ProductStateStoreFingerprint {
        var components: [ProductStateStoreComponentFingerprint] = []
        for component in componentURLs(for: storeURL) {
            guard fileManager.fileExists(atPath: component.url.path) else {
                continue
            }
            do {
                let data = try Data(
                    contentsOf: component.url,
                    options: .mappedIfSafe
                )
                let values = try component.url.resourceValues(
                    forKeys: [.contentModificationDateKey]
                )
                components.append(
                    ProductStateStoreComponentFingerprint(
                        role: component.role,
                        byteCount: data.count,
                        sha256: ProductStateSHA256.hexDigest(data),
                        modificationTime:
                            values.contentModificationDate?
                                .timeIntervalSinceReferenceDate ?? 0
                    )
                )
            } catch {
                throw ProductStateCharacterizationSupportError
                    .workingCopyFailure(
                        code: "source-fingerprint",
                        caseID: caseID
                    )
            }
        }
        guard components.contains(where: { $0.role == "store" }) else {
            throw ProductStateCharacterizationSupportError
                .workingCopyFailure(
                    code: "source-store-missing",
                    caseID: caseID
                )
        }
        return ProductStateStoreFingerprint(
            components: components.sorted { $0.role < $1.role }
        )
    }

    static func componentURLs(
        for storeURL: URL
    ) -> [(role: String, url: URL)] {
        componentSuffixes.map { component in
            (
                role: component.role,
                url: URL(
                    fileURLWithPath:
                        storeURL.path + component.suffix,
                    isDirectory: false
                )
            )
        }
    }
}

@MainActor
final class ProductStateWorkingCopy {
    let caseID: String
    let sourceStoreURL: URL
    let sourceFingerprint: ProductStateStoreFingerprint
    let ownedDirectory: ProductStateOwnedTemporaryDirectory
    let workingStoreURL: URL

    init(
        sourceStoreURL: URL,
        caseID: String,
        fileManager: FileManager = .default
    ) throws {
        self.caseID = caseID
        self.sourceStoreURL = sourceStoreURL
        sourceFingerprint = try ProductStateStoreFingerprinting
            .fingerprint(
                storeURL: sourceStoreURL,
                caseID: caseID,
                fileManager: fileManager
            )
        ownedDirectory = try ProductStateOwnedTemporaryDirectory(
            caseID: caseID,
            fileManager: fileManager
        )
        workingStoreURL = try ownedDirectory.storeURL(
            name: "WorkingCopy.store"
        )

        do {
            let sourceComponents =
                ProductStateStoreFingerprinting.componentURLs(
                    for: sourceStoreURL
                )
            let destinationComponents =
                ProductStateStoreFingerprinting.componentURLs(
                    for: workingStoreURL
                )
            for (index, source) in sourceComponents.enumerated()
                where fileManager.fileExists(atPath: source.url.path)
            {
                try fileManager.copyItem(
                    at: source.url,
                    to: destinationComponents[index].url
                )
            }
        } catch {
            try? ownedDirectory.cleanup()
            throw ProductStateCharacterizationSupportError
                .workingCopyFailure(
                    code: "copy-store-components",
                    caseID: caseID
                )
        }
    }

    func makeContainer(
        generation: ProductStateSchemaGeneration
    ) throws -> ModelContainer {
        try ProductStateTestContainerFactory.makeFileBacked(
            generation: generation,
            storeURL: workingStoreURL,
            ownedBy: ownedDirectory,
            caseID: caseID
        )
    }

    func verifySourceUnchanged() throws {
        let current = try ProductStateStoreFingerprinting.fingerprint(
            storeURL: sourceStoreURL,
            caseID: caseID
        )
        guard current == sourceFingerprint else {
            throw ProductStateCharacterizationSupportError
                .workingCopyFailure(
                    code: "source-mutated",
                    caseID: caseID
                )
        }
    }

    func cleanup() throws {
        try ownedDirectory.cleanup()
    }
}

// MARK: - Canonical semantic snapshots

enum ProductStateSHA256 {
    static func hexDigest(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

indirect enum ProductStateSemanticValue: Encodable, Equatable {
    case boolean(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case uuid(UUID)
    case date(Date)
    case optional(ProductStateSemanticValue?)
    case orderedUUIDs([UUID])
    case bytes(byteCount: Int, syntheticSHA256: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case presence
        case values
        case byteCount
        case syntheticSHA256
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .boolean(let value):
            try container.encode("boolean", forKey: .kind)
            try container.encode(value, forKey: .value)
        case .integer(let value):
            try container.encode("integer", forKey: .kind)
            try container.encode(value, forKey: .value)
        case .number(let value):
            try container.encode("number", forKey: .kind)
            try container.encode(value, forKey: .value)
        case .string(let value):
            try container.encode("string", forKey: .kind)
            try container.encode(value, forKey: .value)
        case .uuid(let value):
            try container.encode("uuid", forKey: .kind)
            try container.encode(value.uuidString, forKey: .value)
        case .date(let value):
            try container.encode("date", forKey: .kind)
            try container.encode(
                ProductStateSyntheticValues.iso8601UTC(value),
                forKey: .value
            )
        case .optional(let value):
            try container.encode("optional", forKey: .kind)
            if let value {
                try container.encode("present", forKey: .presence)
                try container.encode(value, forKey: .value)
            } else {
                try container.encode("absent", forKey: .presence)
            }
        case .orderedUUIDs(let values):
            try container.encode("orderedUUIDs", forKey: .kind)
            try container.encode(
                ProductStateSyntheticValues.sortedUUIDs(values)
                    .map(\.uuidString),
                forKey: .values
            )
        case .bytes(let byteCount, let syntheticSHA256):
            try container.encode("syntheticBytes", forKey: .kind)
            try container.encode(byteCount, forKey: .byteCount)
            try container.encode(
                syntheticSHA256,
                forKey: .syntheticSHA256
            )
        }
    }

    nonisolated func isAttachmentSafe() -> Bool {
        switch self {
        case .boolean, .integer, .number, .uuid, .date,
                .orderedUUIDs, .bytes:
            return true
        case .optional(let value):
            return value?.isAttachmentSafe() ?? true
        case .string(let value):
            guard !value.isEmpty, value.count <= 128 else {
                return false
            }
            let allowed = CharacterSet(
                charactersIn:
                    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:"
            )
            return value.unicodeScalars.allSatisfy(allowed.contains)
        }
    }
}

struct ProductStateSemanticRecord: Encodable, Equatable {
    let entityKind: String
    let stableID: UUID
    let fields: [String: ProductStateSemanticValue]
    let relationships: [String: [UUID]]
}

struct ProductStateSemanticRelationshipCount: Encodable, Equatable {
    let entityKind: String
    let stableID: UUID
    let relationship: String
    let count: Int
}

struct ProductStateSafeRecordTypeSummary: Encodable, Equatable {
    let entityKind: String
    let count: Int
}

struct ProductStateCanonicalSemanticSnapshot: Encodable, Equatable {
    let formatVersion: Int
    let caseID: String
    let syntheticData: Bool
    let records: [ProductStateSemanticRecord]
    let entityCounts: [String: Int]
    let relationshipCounts: [ProductStateSemanticRelationshipCount]
    let recordTypeSummaries: [ProductStateSafeRecordTypeSummary]

    func canonicalJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(self)
        } catch {
            throw ProductStateCharacterizationSupportError
                .semanticSnapshotFailure(
                    code: "json-encoding",
                    caseID: caseID
                )
        }
    }

    func sha256Digest() throws -> String {
        ProductStateSHA256.hexDigest(try canonicalJSONData())
    }
}

@MainActor
enum ProductStateCanonicalSnapshotBuilder {
    static func makeCurrentSnapshot(
        caseID: String,
        in context: ModelContext
    ) throws -> ProductStateCanonicalSemanticSnapshot {
        guard
            ProductStateCharacterizationSupportError.safeToken(caseID)
                != nil
        else {
            throw ProductStateCharacterizationSupportError
                .semanticSnapshotFailure(
                    code: "unsafe-case-id",
                    caseID: "unavailable"
                )
        }

        let locations = try context.fetch(
            FetchDescriptor<GeoLocation>()
        )
        let items = try context.fetch(
            FetchDescriptor<ShoppingItem>()
        )
        let products = try context.fetch(
            FetchDescriptor<Product>()
        )
        let lists = try context.fetch(
            FetchDescriptor<ShoppingList>()
        )
        let entries = try context.fetch(
            FetchDescriptor<ShoppingListEntry>()
        )
        let histories = try context.fetch(
            FetchDescriptor<ProductHistory>()
        )
        let knowledge = try context.fetch(
            FetchDescriptor<ProductKnowledge>()
        )
        let sessions = try context.fetch(
            FetchDescriptor<ShoppingSession>()
        )

        var records: [ProductStateSemanticRecord] = []
        var relationshipCounts:
            [ProductStateSemanticRelationshipCount] = []

        for location in locations {
            let relatedIDs = ProductStateSyntheticValues.sortedUUIDs(
                location.shoppingItems.map(\.id)
            )
            records.append(
                ProductStateSemanticRecord(
                    entityKind: "GeoLocation",
                    stableID: location.id,
                    fields: [
                        "sourceTypeRawValue":
                            .optional(
                                location.sourceTypeRawValue.map {
                                    .string($0)
                                }
                            )
                    ],
                    relationships: ["shoppingItems": relatedIDs]
                )
            )
            relationshipCounts.append(
                ProductStateSemanticRelationshipCount(
                    entityKind: "GeoLocation",
                    stableID: location.id,
                    relationship: "shoppingItems",
                    count: relatedIDs.count
                )
            )
        }

        for item in items {
            records.append(
                ProductStateSemanticRecord(
                    entityKind: "ShoppingItem",
                    stableID: item.id,
                    fields: [
                        "dateAdded": .date(item.dateAdded),
                        "imageData": byteSummary(item.imageData),
                        "isCompleted": .boolean(item.isCompleted),
                        "sourceRawValue": .string(item.sourceRawValue)
                    ],
                    relationships: [:]
                )
            )
        }

        for product in products {
            let catalogFieldCount = [
                product.catalogProductIDRawValue,
                product.catalogDisplayNameSnapshot,
                product.catalogDisplayLocaleSnapshot,
                product.catalogCategoryIDSnapshotRawValue,
                product.catalogCategoryDisplayNameSnapshot,
                product.catalogIconKeySnapshot
            ].compactMap { $0 }.count +
                (product.catalogSnapshotUpdatedAt == nil ? 0 : 1)
            records.append(
                ProductStateSemanticRecord(
                    entityKind: "Product",
                    stableID: product.id,
                    fields: [
                        "catalogSnapshotFieldCount":
                            .integer(catalogFieldCount),
                        "dateAdded": .date(product.dateAdded),
                        "deletedAt":
                            .optional(product.deletedAt.map { .date($0) }),
                        "imageData": byteSummary(product.imageData),
                        "legacyShoppingItemID":
                            .optional(
                                product.legacyShoppingItemID.map {
                                    .uuid($0)
                                }
                            ),
                        "sourceRawValue": .string(product.sourceRawValue),
                        "updatedAt": .date(product.updatedAt)
                    ],
                    relationships: [:]
                )
            )
        }

        for list in lists {
            records.append(
                ProductStateSemanticRecord(
                    entityKind: "ShoppingList",
                    stableID: list.id,
                    fields: [
                        "createdAt": .date(list.createdAt),
                        "isDefault": .boolean(list.isDefault),
                        "kindRawValue": .string(list.kindRawValue),
                        "updatedAt": .date(list.updatedAt)
                    ],
                    relationships: [:]
                )
            )
        }

        for entry in entries {
            let productIDs = entry.product.map { [$0.id] } ?? []
            records.append(
                ProductStateSemanticRecord(
                    entityKind: "ShoppingListEntry",
                    stableID: entry.id,
                    fields: [
                        "createdAt": .date(entry.createdAt),
                        "isChecked": .boolean(entry.isChecked),
                        "legacyShoppingItemID":
                            .optional(
                                entry.legacyShoppingItemID.map {
                                    .uuid($0)
                                }
                            ),
                        "productID": .uuid(entry.productID),
                        "quantity": .number(entry.quantity),
                        "shoppingListID": .uuid(entry.shoppingListID),
                        "sortOrder": .number(entry.sortOrder)
                    ],
                    relationships: ["product": productIDs]
                )
            )
            relationshipCounts.append(
                ProductStateSemanticRelationshipCount(
                    entityKind: "ShoppingListEntry",
                    stableID: entry.id,
                    relationship: "product",
                    count: productIDs.count
                )
            )
        }

        for history in histories {
            let keyKind: String
            if history.productKey.hasPrefix("barcode:") {
                keyKind = "barcode"
            } else if history.productKey.hasPrefix("name:") {
                keyKind = "name"
            } else {
                keyKind = "other"
            }
            records.append(
                ProductStateSemanticRecord(
                    entityKind: "ProductHistory",
                    stableID: history.id,
                    fields: [
                        "addCount": .integer(history.addCount),
                        "averageInterval":
                            .optional(
                                history.averageInterval.map { .number($0) }
                            ),
                        "firstAddedDate":
                            .date(history.firstAddedDate),
                        "keyKind": .string(keyKind),
                        "lastAddedDate": .date(history.lastAddedDate),
                        "lastCompletedDate":
                            .optional(
                                history.lastCompletedDate.map {
                                    .date($0)
                                }
                            ),
                        "lastSourceRawValue":
                            .string(history.lastSourceRawValue)
                    ],
                    relationships: [:]
                )
            )
        }

        for item in knowledge {
            records.append(
                ProductStateSemanticRecord(
                    entityKind: "ProductKnowledge",
                    stableID: item.id,
                    fields: [
                        "dateLearned": .date(item.dateLearned),
                        "lastUsed":
                            .optional(item.lastUsed.map { .date($0) }),
                        "thumbnailData":
                            byteSummary(item.thumbnailData),
                        "timesUsed": .integer(item.timesUsed),
                        "updatedAt": .date(item.updatedAt)
                    ],
                    relationships: [:]
                )
            )
        }

        for session in sessions {
            let itemIDs = ProductStateSyntheticValues.sortedUUIDs(
                session.itemIDs
            )
            let collectedIDs = ProductStateSyntheticValues.sortedUUIDs(
                session.collectedItemIDs
            )
            records.append(
                ProductStateSemanticRecord(
                    entityKind: "ShoppingSession",
                    stableID: session.id,
                    fields: [
                        "finishedAt":
                            .optional(
                                session.finishedAt.map { .date($0) }
                            ),
                        "isActive": .boolean(session.isActive),
                        "shoppingListID":
                            .optional(
                                session.shoppingListID.map { .uuid($0) }
                            ),
                        "startedAt": .date(session.startedAt)
                    ],
                    relationships: [
                        "collectedItemIDs": collectedIDs,
                        "itemIDs": itemIDs
                    ]
                )
            )
            relationshipCounts.append(
                ProductStateSemanticRelationshipCount(
                    entityKind: "ShoppingSession",
                    stableID: session.id,
                    relationship: "collectedItemIDs",
                    count: collectedIDs.count
                )
            )
            relationshipCounts.append(
                ProductStateSemanticRelationshipCount(
                    entityKind: "ShoppingSession",
                    stableID: session.id,
                    relationship: "itemIDs",
                    count: itemIDs.count
                )
            )
        }

        records.sort {
            if $0.entityKind != $1.entityKind {
                return $0.entityKind < $1.entityKind
            }
            return $0.stableID.uuidString < $1.stableID.uuidString
        }
        relationshipCounts.sort {
            if $0.entityKind != $1.entityKind {
                return $0.entityKind < $1.entityKind
            }
            if $0.stableID != $1.stableID {
                return $0.stableID.uuidString < $1.stableID.uuidString
            }
            return $0.relationship < $1.relationship
        }

        let grouped = Dictionary(grouping: records, by: \.entityKind)
        let entityCounts = grouped.mapValues(\.count)
        let summaries = grouped.keys.sorted().map {
            ProductStateSafeRecordTypeSummary(
                entityKind: $0,
                count: grouped[$0]?.count ?? 0
            )
        }
        return ProductStateCanonicalSemanticSnapshot(
            formatVersion: 1,
            caseID: caseID,
            syntheticData: true,
            records: records,
            entityCounts: entityCounts,
            relationshipCounts: relationshipCounts,
            recordTypeSummaries: summaries
        )
    }

    private static func byteSummary(
        _ data: Data?
    ) -> ProductStateSemanticValue {
        guard let data else {
            return .optional(nil)
        }
        return .optional(
            .bytes(
                byteCount: data.count,
                syntheticSHA256:
                    ProductStateSHA256.hexDigest(data)
            )
        )
    }
}

// MARK: - Privacy-safe XCTest attachments

enum ProductStateAttachmentFactory {
    static func makeJSONAttachment(
        snapshot: ProductStateCanonicalSemanticSnapshot,
        lifetime: XCTAttachment.Lifetime = .deleteOnSuccess
    ) throws -> XCTAttachment {
        guard
            snapshot.syntheticData,
            ProductStateCharacterizationSupportError.safeToken(
                snapshot.caseID
            ) != nil,
            snapshot.records.allSatisfy(recordIsSafe)
        else {
            throw ProductStateCharacterizationSupportError
                .attachmentRejected(
                    code: "privacy-allowlist",
                    caseID: snapshot.caseID
                )
        }
        let attachment = XCTAttachment(
            data: try snapshot.canonicalJSONData(),
            uniformTypeIdentifier: UTType.json.identifier
        )
        attachment.name =
            "SYNTHETIC_ProductState_\(snapshot.caseID)"
        attachment.lifetime = lifetime
        return attachment
    }

    nonisolated private static func recordIsSafe(
        _ record: ProductStateSemanticRecord
    ) -> Bool {
        let allowedEntities: Set<String> = [
            "GeoLocation",
            "ShoppingItem",
            "Product",
            "ShoppingList",
            "ShoppingListEntry",
            "ProductHistory",
            "ProductKnowledge",
            "ShoppingSession"
        ]
        let forbiddenFieldFragments = [
            "name",
            "title",
            "barcode",
            "coordinate",
            "latitude",
            "longitude",
            "notes",
            "path"
        ]
        guard
            allowedEntities.contains(record.entityKind),
            record.fields.keys.allSatisfy({ field in
                let lowered = field.lowercased()
                return !forbiddenFieldFragments.contains(where: {
                    lowered.contains($0)
                })
            }),
            record.fields.values.allSatisfy({
                $0.isAttachmentSafe()
            })
        else {
            return false
        }
        return true
    }
}

// MARK: - Monotonic performance sampling

struct ProductStateTimingStatistics: Equatable {
    let minimumSeconds: Double
    let maximumSeconds: Double
    let p50Seconds: Double
    let p95Seconds: Double
    let sampleCount: Int
    let warmUpCount: Int
}

enum ProductStatePerformanceSampler {
    static func measure(
        warmUpCount: Int,
        sampleCount: Int,
        operation: () throws -> Void
    ) throws -> ProductStateTimingStatistics {
        guard warmUpCount >= 0, sampleCount > 0 else {
            throw ProductStateCharacterizationSupportError
                .invalidPerformanceConfiguration
        }

        for _ in 0..<warmUpCount {
            try operation()
        }

        let clock = ContinuousClock()
        var samples: [Double] = []
        samples.reserveCapacity(sampleCount)
        for _ in 0..<sampleCount {
            let start = clock.now
            try operation()
            let duration = start.duration(to: clock.now)
            let components = duration.components
            let seconds =
                Double(components.seconds) +
                Double(components.attoseconds) / 1_000_000_000_000_000_000
            samples.append(seconds)
        }
        samples.sort()
        return ProductStateTimingStatistics(
            minimumSeconds: samples[0],
            maximumSeconds: samples[samples.count - 1],
            p50Seconds: percentile(0.50, samples: samples),
            p95Seconds: percentile(0.95, samples: samples),
            sampleCount: sampleCount,
            warmUpCount: warmUpCount
        )
    }

    private static func percentile(
        _ percentile: Double,
        samples: [Double]
    ) -> Double {
        let rank = max(
            Int(ceil(percentile * Double(samples.count))) - 1,
            0
        )
        return samples[min(rank, samples.count - 1)]
    }
}

// MARK: - Deterministic fixture profiles

struct ProductStateFixtureProfile: Equatable {
    let identifier: String
    let seed: UInt64
    let productCount: Int
    let namedListCount: Int
    let entryCount: Int
    let compatibilityItemCount: Int
    let historyRecordCount: Int
    let sessionCount: Int
    let sessionLineCount: Int?
    let savedLocationCount: Int
    let savedLocationRelationshipCount: Int

    static let functional = ProductStateFixtureProfile(
        identifier: "functional",
        seed: 0x032B_1001,
        productCount: 25,
        namedListCount: 3,
        entryCount: 20,
        compatibilityItemCount: 25,
        historyRecordCount: 10,
        sessionCount: 1,
        sessionLineCount: nil,
        savedLocationCount: 0,
        savedLocationRelationshipCount: 0
    )

    static let reference = ProductStateFixtureProfile(
        identifier: "reference",
        seed: 0x032B_2001,
        productCount: 2_000,
        namedListCount: 20,
        entryCount: 10_000,
        compatibilityItemCount: 2_000,
        historyRecordCount: 5_000,
        sessionCount: 1,
        sessionLineCount: 500,
        savedLocationCount: 20,
        savedLocationRelationshipCount: 50
    )

    func stableUUID(
        entityNamespace: UInt16,
        index: Int
    ) -> UUID {
        precondition(index >= 0)
        return ProductStateSyntheticValues.uuid(
            namespace: entityNamespace,
            index: UInt64(index) + seed
        )
    }
}

// MARK: - Minimal synthetic current-schema fixture

@MainActor
enum ProductStateSyntheticCurrentFixture {
    static func seed(
        in context: ModelContext
    ) throws {
        let base = ProductStateSyntheticValues.epoch
        let itemID = ProductStateSyntheticValues.uuid(
            namespace: 0x0303,
            index: 1
        )
        let productID = ProductStateSyntheticValues.uuid(
            namespace: 0x0303,
            index: 2
        )
        let listID = ProductStateSyntheticValues.uuid(
            namespace: 0x0303,
            index: 3
        )

        let item = ShoppingItem(
            id: itemID,
            name: "SYNTHETIC_PRODUCT_SUPPORT",
            isCompleted: false,
            imageData: Data([0x03, 0x2B, 0x01]),
            dateAdded: base,
            source: .manual
        )
        let product = Product(
            id: productID,
            legacyShoppingItemID: itemID,
            name: "SYNTHETIC_PRODUCT_SUPPORT",
            imageData: Data([0x03, 0x2B, 0x02]),
            dateAdded: base,
            updatedAt: base,
            source: .manual
        )
        let list = ShoppingList(
            id: listID,
            title: "SYNTHETIC_LIST_SUPPORT",
            kind: .weekly,
            createdAt: base,
            updatedAt: base,
            isDefault: true
        )
        let entry = ShoppingListEntry(
            id: ProductStateSyntheticValues.uuid(
                namespace: 0x0303,
                index: 4
            ),
            shoppingListID: listID,
            product: product,
            legacyShoppingItemID: itemID,
            quantity: 1,
            isChecked: false,
            createdAt: base,
            sortOrder: 0
        )
        let history = ProductHistory(
            id: ProductStateSyntheticValues.uuid(
                namespace: 0x0303,
                index: 5
            ),
            productKey: "name:synthetic_product_support",
            productName: "SYNTHETIC_PRODUCT_SUPPORT",
            firstAddedDate: base,
            lastAddedDate: base,
            addCount: 1,
            lastSource: .manual
        )
        let knowledge = ProductKnowledge(
            id: ProductStateSyntheticValues.uuid(
                namespace: 0x0303,
                index: 6
            ),
            knowledgeKey: "synthetic:product:support",
            productName: "SYNTHETIC_PRODUCT_SUPPORT",
            thumbnailData: Data([0x03, 0x2B, 0x03]),
            dateLearned: base,
            timesUsed: 1,
            updatedAt: base
        )
        let session = ShoppingSession(
            id: ProductStateSyntheticValues.uuid(
                namespace: 0x0303,
                index: 7
            ),
            startedAt: base,
            isActive: true,
            itemIDs: [itemID],
            collectedItemIDs: [],
            shoppingListID: listID
        )
        let location = GeoLocation(
            id: ProductStateSyntheticValues.uuid(
                namespace: 0x0303,
                index: 8
            ),
            title: "SYNTHETIC_LOCATION_SUPPORT",
            latitude: 0,
            longitude: 0,
            radius: 100,
            shoppingItems: [item]
        )

        context.insert(item)
        context.insert(product)
        context.insert(list)
        context.insert(entry)
        context.insert(history)
        context.insert(knowledge)
        context.insert(session)
        context.insert(location)
        try context.save()
    }
}

// MARK: - E-03 support self-validation

@MainActor
final class ProductStateCharacterizationSupportSelfTests: XCTestCase {
    func testManifestSupportLoadsStrictCurrentBehaviorContract()
        throws
    {
        let loaded = try ProductStateManifestLoader.loadFromTestBundle()
        let sourceData = try ProductStateManifestLoader
            .sourceManifestData()

        XCTAssertEqual(loaded.manifest.manifestSchemaVersion, 1)
        XCTAssertEqual(loaded.manifest.expectationKind, .currentBehavior)
        XCTAssertEqual(loaded.manifest.cases.count, 19)
        XCTAssertEqual(
            Set(loaded.manifest.cases.map(\.caseID)),
            ProductStateManifestValidator.requiredCaseIDs
        )
        XCTAssertEqual(loaded.bundledData, sourceData)
        XCTAssertEqual(
            ProductStateSHA256.hexDigest(loaded.bundledData),
            ProductStateSHA256.hexDigest(sourceData)
        )

        var root = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: loaded.bundledData
            ) as? [String: Any]
        )
        root["unknownRequiredField"] = "SYNTHETIC_REJECTED"
        let unknownFieldData = try JSONSerialization.data(
            withJSONObject: root,
            options: [.sortedKeys]
        )
        XCTAssertThrowsError(
            try ProductStateManifestLoader.decodeAndValidate(
                unknownFieldData
            )
        ) { error in
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "Product State manifest decoding failed."
            )
        }
    }

    func testDeterministicFactoriesProfilesAndTimingStatistics()
        throws
    {
        let firstUUID = ProductStateSyntheticValues.uuid(
            namespace: 0x0303,
            index: 42
        )
        let secondUUID = ProductStateSyntheticValues.uuid(
            namespace: 0x0303,
            index: 42
        )
        XCTAssertEqual(firstUUID, secondUUID)
        XCTAssertEqual(
            ProductStateSyntheticValues.iso8601UTC(
                ProductStateSyntheticValues.epoch
            ),
            "2001-01-01T00:00:00.000Z"
        )
        XCTAssertEqual(
            ProductStateSyntheticValues.calendar.identifier,
            .gregorian
        )
        XCTAssertEqual(
            ProductStateSyntheticValues.calendar.timeZone
                .secondsFromGMT(),
            0
        )
        XCTAssertEqual(
            ProductStateSyntheticValues.locale.identifier,
            "en_US_POSIX"
        )

        XCTAssertEqual(
            ProductStateFixtureProfile.functional.productCount,
            25
        )
        XCTAssertEqual(
            ProductStateFixtureProfile.functional.namedListCount,
            3
        )
        XCTAssertEqual(
            ProductStateFixtureProfile.functional.entryCount,
            20
        )
        XCTAssertEqual(
            ProductStateFixtureProfile.functional
                .compatibilityItemCount,
            25
        )
        XCTAssertEqual(
            ProductStateFixtureProfile.functional.historyRecordCount,
            10
        )
        XCTAssertEqual(
            ProductStateFixtureProfile.functional.sessionCount,
            1
        )
        XCTAssertEqual(
            ProductStateFixtureProfile.reference.productCount,
            2_000
        )
        XCTAssertEqual(
            ProductStateFixtureProfile.reference.namedListCount,
            20
        )
        XCTAssertEqual(
            ProductStateFixtureProfile.reference.entryCount,
            10_000
        )
        XCTAssertEqual(
            ProductStateFixtureProfile.reference
                .compatibilityItemCount,
            2_000
        )
        XCTAssertEqual(
            ProductStateFixtureProfile.reference.historyRecordCount,
            5_000
        )
        XCTAssertEqual(
            ProductStateFixtureProfile.reference.sessionLineCount,
            500
        )
        XCTAssertEqual(
            ProductStateFixtureProfile.reference
                .savedLocationCount,
            20
        )
        XCTAssertEqual(
            ProductStateFixtureProfile.reference
                .savedLocationRelationshipCount,
            50
        )

        var invocationCount = 0
        let statistics = try ProductStatePerformanceSampler.measure(
            warmUpCount: 1,
            sampleCount: 5
        ) {
            invocationCount += 1
        }
        XCTAssertEqual(invocationCount, 6)
        XCTAssertEqual(statistics.sampleCount, 5)
        XCTAssertEqual(statistics.warmUpCount, 1)
        XCTAssertLessThanOrEqual(
            statistics.minimumSeconds,
            statistics.p50Seconds
        )
        XCTAssertLessThanOrEqual(
            statistics.p50Seconds,
            statistics.p95Seconds
        )
        XCTAssertLessThanOrEqual(
            statistics.p95Seconds,
            statistics.maximumSeconds
        )
    }

    func testCurrentSchemaInMemoryContainerCanBeCreated()
        throws
    {
        var container: ModelContainer? =
            try ProductStateTestContainerFactory.makeInMemoryCurrent(
                caseID: "e03-in-memory"
            )
        var context: ModelContext? = try XCTUnwrap(container).mainContext
        XCTAssertEqual(
            try XCTUnwrap(context).fetchCount(
                FetchDescriptor<Product>()
            ),
            0
        )
        context = nil
        container = nil
        XCTAssertNil(context)
        XCTAssertNil(container)
    }

    func testCurrentWorkingCopySnapshotDigestAndCleanup()
        throws
    {
        var sourceLease: ProductStateFileBackedContainerLease? =
            try ProductStateFileBackedContainerLease(
                caseID: "e03-source-current",
                generation: .current
            )
        let sourceRoot = try XCTUnwrap(sourceLease)
            .ownedDirectory.rootURL

        var sourceContext: ModelContext? = ModelContext(
            try XCTUnwrap(try XCTUnwrap(sourceLease).container)
        )
        try ProductStateSyntheticCurrentFixture.seed(
            in: try XCTUnwrap(sourceContext)
        )
        sourceContext = nil
        sourceLease?.releasePersistentReferences()

        var workingCopy: ProductStateWorkingCopy? =
            try ProductStateWorkingCopy(
                sourceStoreURL: try XCTUnwrap(sourceLease).storeURL,
                caseID: "e03-working-current"
            )
        let workingRoot = try XCTUnwrap(workingCopy)
            .ownedDirectory.rootURL
        let sourceDigest = try XCTUnwrap(workingCopy)
            .sourceFingerprint.semanticDigest

        var workingContainer: ModelContainer? =
            try XCTUnwrap(workingCopy).makeContainer(
                generation: .current
            )
        var workingContext: ModelContext? = ModelContext(
            try XCTUnwrap(workingContainer)
        )
        let firstSnapshot =
            try ProductStateCanonicalSnapshotBuilder
                .makeCurrentSnapshot(
                    caseID: "e03-working-current",
                    in: try XCTUnwrap(workingContext)
                )
        let secondSnapshot =
            try ProductStateCanonicalSnapshotBuilder
                .makeCurrentSnapshot(
                    caseID: "e03-working-current",
                    in: try XCTUnwrap(workingContext)
                )

        XCTAssertEqual(firstSnapshot, secondSnapshot)
        XCTAssertEqual(
            try firstSnapshot.canonicalJSONData(),
            try secondSnapshot.canonicalJSONData()
        )
        XCTAssertEqual(
            try firstSnapshot.sha256Digest(),
            try secondSnapshot.sha256Digest()
        )
        XCTAssertEqual(firstSnapshot.entityCounts["Product"], 1)
        XCTAssertEqual(
            firstSnapshot.entityCounts["ShoppingListEntry"],
            1
        )
        XCTAssertEqual(
            firstSnapshot.entityCounts["ShoppingSession"],
            1
        )
        XCTAssertEqual(
            firstSnapshot.entityCounts["GeoLocation"],
            1
        )
        XCTAssertNoThrow(
            try ProductStateAttachmentFactory.makeJSONAttachment(
                snapshot: firstSnapshot
            )
        )

        workingContext = nil
        workingContainer = nil
        try workingCopy?.verifySourceUnchanged()
        XCTAssertEqual(
            try XCTUnwrap(workingCopy)
                .sourceFingerprint.semanticDigest,
            sourceDigest
        )
        try workingCopy?.cleanup()
        workingCopy = nil
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: workingRoot.path)
        )

        try sourceLease?.cleanup()
        sourceLease = nil
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sourceRoot.path)
        )
    }
}
