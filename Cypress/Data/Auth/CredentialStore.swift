//
//  CredentialStore.swift
//  Cypress — Data/Auth
//
//  Where a token lives, and why it is not in the database.
//
//  Spec §5.8: "A credential inside the SQLite file is a credential inside every backup of it, and
//  `AccountDeletion` reasons about rows and files rather than about copies elsewhere." So tokens go
//  to the Keychain, which is not the database and therefore needs **no migration** — the sentence
//  the spec makes explicitly, because a session landing in `app_state` is the version of this that
//  would have wanted one.
//

import Foundation
import Security

/// The small door the session layer needs onto persistent secret storage.
///
/// A protocol rather than a direct `SecItem*` call so a test can hold the credentials in memory: a
/// unit suite that exercised the real Keychain for every assertion would be measuring the
/// simulator's keychain daemon on every run, and a failure there reads exactly like a failure in
/// the code under test. `KeychainCredentialStore` is exercised on its own, once, by
/// `SessionKeychainTests` — the instrument is calibrated separately from the things it measures.
public protocol CredentialStore: Sendable {
    func data(forKey key: String) throws -> Data?
    func setData(_ data: Data, forKey key: String) throws
    func removeData(forKey key: String) throws
}

/// The keys this app stores. Enumerated rather than spelled at call sites so that a rename cannot
/// silently orphan a live credential on somebody's phone.
public enum CredentialKey {
    /// The account session: access token, refresh token, and both expiries.
    public static let session = "session"
    /// The device credential of §5.8's `POST /devices/register` — the one that lets an anonymous
    /// queue drain before there is an account.
    public static let device = "device"
}

/// `kSecClassGenericPassword` items under one service, accessible **after first unlock**.
///
/// `kSecAttrAccessibleAfterFirstUnlock` and not `WhenUnlocked`, and that is spec §5.8 rather than a
/// default: a background drain runs on a locked phone, so a credential the phone cannot read while
/// locked is a queue that only drains while somebody is looking at it. It is not
/// `…ThisDeviceOnly`, deliberately-not: `ThisDeviceOnly` is about backup and migration, and the
/// thing that must not be in the backup is a credential in the *SQLite file*, which is what putting
/// it here already solves.
public struct KeychainCredentialStore: CredentialStore {

    /// `kSecAttrService`. Defaults to the bundle identifier so two installs cannot collide, with a
    /// literal fallback for a host bundle that has none (a test runner).
    public let service: String

    public init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    public static var defaultService: String {
        Bundle.main.bundleIdentifier ?? "app.cypress.Cypress"
    }

    /// Errors carry the OSStatus, because "the Keychain refused" without the number is a report
    /// nobody can act on — `-34018` (missing entitlement) and `-25300` (no such item) are different
    /// problems with the same sentence.
    public enum KeychainError: Error, Equatable, CustomStringConvertible {
        case unexpectedStatus(OSStatus)

        public var description: String {
            switch self {
            case let .unexpectedStatus(status):
                return "the keychain returned OSStatus \(status)"
            }
        }
    }

    private func query(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    public func data(forKey key: String) throws -> Data? {
        var lookup = query(forKey: key)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Add, or update in place.
    ///
    /// `SecItemUpdate` after a `duplicateItem` rather than delete-then-add: a delete that succeeded
    /// and an add that failed would leave the phone with no credential at all, which is a signed-in
    /// person signed out by a write.
    public func setData(_ data: Data, forKey key: String) throws {
        var attributes = query(forKey: key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let update: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]
            let updateStatus = SecItemUpdate(query(forKey: key) as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removing something that is not there is a success: a sign-out on a device that never signed
    /// in must not throw, and "it is not there" is the state the caller asked for.
    public func removeData(forKey key: String) throws {
        let status = SecItemDelete(query(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// A `CredentialStore` held in memory, for tests and for previews.
///
/// Not behind `#if DEBUG`: `SessionKeychainTests` needs it from the test target, and the test target
/// links the app's release-configured sources too.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data]

    public init(_ storage: [String: Data] = [:]) {
        self.storage = storage
    }

    public func data(forKey key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func setData(_ data: Data, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = data
    }

    public func removeData(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}
