import Foundation
import Security

enum CredentialStoreError: Error, Equatable, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            "Keychain operation failed with status \(status)."
        case .invalidEncoding:
            "The saved credential could not be decoded."
        }
    }
}

protocol CredentialStoring: Sendable {
    func set(_ value: String, for key: String) async throws
    func value(for key: String) async throws -> String?
    func removeValue(for key: String) async throws
}

actor KeychainCredentialStore: CredentialStoring {
    /// Shared Keychain service for all WhatFun credentials. The synchronous
    /// metadata-key reader uses the same service so saved keys resolve at request time.
    nonisolated static let defaultService = "com.yjsoon.whatfun.private-feeds"

    private let service: String

    init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    func set(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw CredentialStoreError.invalidEncoding
        }

        let query = baseQuery(for: key)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw CredentialStoreError.unexpectedStatus(insertStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CredentialStoreError.unexpectedStatus(updateStatus)
        }
    }

    func value(for key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidEncoding
        }
        return value
    }

    func removeValue(for key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

actor InMemoryCredentialStore: CredentialStoring {
    private var values: [String: String] = [:]

    func set(_ value: String, for key: String) {
        values[key] = value
    }

    func value(for key: String) -> String? {
        values[key]
    }

    func removeValue(for key: String) {
        values[key] = nil
    }
}

