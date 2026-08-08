import Foundation
import Security
import XCTest
@testable import WayTask

final class SecureAccountStorageTests: XCTestCase {
    func testKeychainSessionRoundTripsAsDeviceOnlyNonSynchronizableData()
        throws {
        let service = "h.WayTask.tests.\(UUID().uuidString)"
        let account = "session-v1"
        let store = KeychainSessionStore(service: service, account: account)
        defer { try? store.delete() }

        XCTAssertNil(try store.read())
        let original = Data("opaque-session-material".utf8)
        try store.write(original)
        XCTAssertEqual(try store.read(), original)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        query[kSecAttrSynchronizable as String] = kCFBooleanFalse
        var result: CFTypeRef?
        XCTAssertEqual(
            SecItemCopyMatching(query as CFDictionary, &result),
            errSecSuccess
        )
        let attributes = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        let synchronizableQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var synchronizableResult: CFTypeRef?
        XCTAssertEqual(
            SecItemCopyMatching(
                synchronizableQuery as CFDictionary,
                &synchronizableResult
            ),
            errSecItemNotFound
        )

        let replacement = Data("replacement-session-material".utf8)
        try store.write(replacement)
        XCTAssertEqual(try store.read(), replacement)
        try store.delete()
        XCTAssertNil(try store.read())
    }

    func testOwnershipBindingSurvivesStoreRecreationWithoutProductData()
        throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WayTaskSecureAccountStorageTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ownership.json")
        let store = ProtectedLocalDataOwnershipStore(fileURL: url)

        let original = try store.loadOrCreate()
        guard case let .guestOnly(dataSetID) = original else {
            return XCTFail("New ownership storage must begin guest-only")
        }
        let userID = UUID()
        let pending = LocalDataOwnershipState.migrationPending(
            dataSetID: dataSetID,
            targetUserID: userID
        )
        try store.save(pending)

        let relaunched = ProtectedLocalDataOwnershipStore(fileURL: url)
        XCTAssertEqual(try relaunched.loadOrCreate(), pending)
        let persistedText = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(persistedText.contains("accessToken"))
        XCTAssertFalse(persistedText.contains("refreshToken"))
        XCTAssertFalse(persistedText.contains("ProductState"))
    }
}
