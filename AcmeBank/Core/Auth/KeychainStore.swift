import Foundation
import Security

/// Behaviour the `OktaAuthService` needs from a keychain. Extracted as
/// a protocol so unit tests can inject a deterministic write-failure
/// double to verify the "post-SDK-success keychain failure must not
/// fail signIn" rule, without depending on the OS returning a specific
/// `OSStatus` under specific simulator conditions.
public protocol KeychainStoring: AnyObject {
    func set(_ value: String, for key: KeychainStore.KeychainKey) throws
    func get(_ key: KeychainStore.KeychainKey) throws -> String?
    func delete(_ key: KeychainStore.KeychainKey) throws
}

/// Thin wrapper around the `SecItem*` Keychain APIs, scoped to the small
/// set of strings the auth layer needs to persist (the OIDC token trio).
///
/// All `SecItem*` queries built by this type include
/// `kSecUseDataProtectionKeychain: true`. This is REQUIRED for the
/// iOS-Simulator unit-test host: without it, every call returns
/// `errSecMissingEntitlement` (-34018) because the simulator's
/// unit-test bundle is not signed with a real provisioning profile.
/// The flag opts into the data-protection keychain which the simulator
/// supports even without entitlements.
///
/// On signed-device builds the `keychain-access-groups` entitlement in
/// `AcmeBank.entitlements` is what actually controls cross-app sharing;
/// the data-protection flag is harmless there.
public final class KeychainStore: KeychainStoring {

    /// The fixed set of keys this app stores. Using an enum (vs free-form
    /// strings) keeps the call sites grep-able and prevents typos that
    /// would silently miss a previously-stored value.
    public enum KeychainKey: String {
        case idToken      = "com.acmebank.mobile.idToken"
        case accessToken  = "com.acmebank.mobile.accessToken"
        case refreshToken = "com.acmebank.mobile.refreshToken"
    }

    /// Errors thrown by `KeychainStore`. The `OSStatus` is preserved so a
    /// caller can log it; callers MUST NOT collapse a keychain error into
    /// `AuthError.network` — see the post-SDK-success rule.
    public enum KeychainError: Error, Equatable {
        /// `SecItemCopyMatching` / `SecItemAdd` etc. returned a non-success
        /// status. `status` is the raw `OSStatus` (e.g. -34018 missing
        /// entitlement on an unsigned simulator).
        case unhandledStatus(OSStatus)
        /// `SecItemCopyMatching` succeeded but the returned value was not
        /// a UTF-8 string.
        case unexpectedDataFormat
    }

    /// Optional access group from the app's entitlements. Defaults to
    /// `nil` because tests run in an unsigned bundle that has no access
    /// group; production code can pass the resolved
    /// `$(AppIdentifierPrefix)com.acmebank.mobile` string from
    /// `Bundle.main`. Setting `kSecAttrAccessGroup` in an unsigned
    /// process produces `errSecMissingEntitlement` (-34018), which is
    /// why this is optional.
    private let accessGroup: String?

    public init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
    }

    // MARK: - Public API

    /// Store `value` under `key`, overwriting any prior value.
    public func set(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unexpectedDataFormat
        }

        // SecItemUpdate only works if the item already exists; for a
        // brand-new key it returns errSecItemNotFound. So we try update
        // first, and fall back to SecItemAdd when nothing was there.
        let updateQuery = baseQuery(for: key)
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery(for: key)
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(addStatus)
            }
        default:
            throw KeychainError.unhandledStatus(updateStatus)
        }
    }

    /// Read the value previously stored under `key`. Returns `nil` if no
    /// value has been stored (i.e. `errSecItemNotFound`); throws for any
    /// other unexpected status.
    public func get(_ key: KeychainKey) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let string = String(data: data, encoding: .utf8)
            else { throw KeychainError.unexpectedDataFormat }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    /// Delete the value stored under `key`. A non-existent key is NOT an
    /// error (`errSecItemNotFound` is treated as success), so the call
    /// is idempotent and safe to make from sign-out.
    public func delete(_ key: KeychainKey) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    // MARK: - Internals

    /// Build the common query dictionary every `SecItem*` call uses for
    /// `key`. ALWAYS includes `kSecUseDataProtectionKeychain: true` —
    /// see the type-level doc comment for why.
    private func baseQuery(for key: KeychainKey) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrService as String: "com.acmebank.mobile.auth",
            kSecUseDataProtectionKeychain as String: true
        ]
        if let accessGroup = accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
