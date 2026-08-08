import Foundation
import Security

enum SecureAccountStorageError: Error, Equatable {
    case unavailable
    case malformedData
}

protocol SecureSessionStoring: AnyObject {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func delete() throws
}

final class KeychainSessionStore: SecureSessionStoring {
    private let service: String
    private let account: String

    init(
        service: String = "h.WayTask.staging-auth",
        account: String = "supabase-session-v1"
    ) {
        self.service = service
        self.account = account
    }

    func read() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecureAccountStorageError.unavailable
        }
        return data
    }

    func write(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecureAccountStorageError.unavailable
        }

        var insert = baseQuery
        attributes.forEach { insert[$0.key] = $0.value }
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
            throw SecureAccountStorageError.unavailable
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureAccountStorageError.unavailable
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}

private struct LocalDataOwnershipRecord: Codable {
    enum Kind: String, Codable {
        case guestOnly
        case migrationPending
        case linked
    }

    let version: Int
    let kind: Kind
    let dataSetID: UUID
    let ownerUserID: UUID?

    init(ownership: LocalDataOwnershipState) {
        version = 1
        switch ownership {
        case let .guestOnly(dataSetID):
            kind = .guestOnly
            self.dataSetID = dataSetID
            ownerUserID = nil
        case let .migrationPending(dataSetID, targetUserID):
            kind = .migrationPending
            self.dataSetID = dataSetID
            ownerUserID = targetUserID
        case let .linked(dataSetID, ownerUserID):
            kind = .linked
            self.dataSetID = dataSetID
            self.ownerUserID = ownerUserID
        }
    }

    var ownership: LocalDataOwnershipState? {
        guard version == 1 else { return nil }
        switch kind {
        case .guestOnly:
            guard ownerUserID == nil else { return nil }
            return .guestOnly(dataSetID: dataSetID)
        case .migrationPending:
            guard let ownerUserID else { return nil }
            return .migrationPending(
                dataSetID: dataSetID,
                targetUserID: ownerUserID
            )
        case .linked:
            guard let ownerUserID else { return nil }
            return .linked(dataSetID: dataSetID, ownerUserID: ownerUserID)
        }
    }
}

final class ProtectedLocalDataOwnershipStore: LocalDataOwnershipPersisting {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    static func live(fileManager: FileManager = .default) throws
        -> ProtectedLocalDataOwnershipStore {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SecureAccountStorageError.unavailable
        }
        return ProtectedLocalDataOwnershipStore(
            fileURL: applicationSupport
                .appendingPathComponent("WayTaskAccount", isDirectory: true)
                .appendingPathComponent(
                    "local-data-ownership-v1.json",
                    isDirectory: false
                ),
            fileManager: fileManager
        )
    }

    func loadOrCreate() throws -> LocalDataOwnershipState {
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            guard let ownership = try JSONDecoder()
                .decode(LocalDataOwnershipRecord.self, from: data)
                .ownership else {
                throw SecureAccountStorageError.malformedData
            }
            return ownership
        }

        let ownership = LocalDataOwnershipState.guestOnly(dataSetID: UUID())
        try save(ownership)
        return ownership
    }

    func save(_ ownership: LocalDataOwnershipState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(
            LocalDataOwnershipRecord(ownership: ownership)
        )
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
