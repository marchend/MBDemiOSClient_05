import XCTest
import Security
@testable import AcmeBank

/// Round-trip tests against the real `SecItem*` Keychain on the
/// iOS-Simulator unit-test host.
///
/// EVERY direct `SecItem*` query in this file MUST set
/// `kSecUseDataProtectionKeychain: true`. Without it the simulator
/// returns `errSecMissingEntitlement` (-34018) because the test bundle
/// is not signed with a real provisioning profile, and the entire test
/// target goes red. (`KeychainStore` itself already sets the flag — this
/// rule only applies to ad-hoc cleanup / verification queries built
/// directly in test code.)
///
/// ## Environment gating (errSecMissingEntitlement / -34018)
///
/// On some CI images (observed on GitHub Actions macOS runners with
/// Xcode 26.3 / iOS Simulator 18.5) `SecItem*` returns
/// `errSecMissingEntitlement` (-34018) for an unsigned unit-test
/// bundle EVEN with `kSecUseDataProtectionKeychain: true` and no
/// access group — there is no way to sign the bundle on the public
/// runner. In that environment the integration suite is physically
/// unable to exercise the Keychain, so `setUpWithError()` probes the
/// data-protection keychain with the same query the canary uses and
/// `throw XCTSkip(...)` if it sees -34018. Callers of `KeychainStore`
/// remain covered by `OktaAuthServiceTests` with `FakeKeychain`, so
/// skipping here does NOT reduce behavioural coverage of the auth
/// flow — it only skips the round-trip-against-real-SecItem proof,
/// which is exactly what the runner cannot provide.
final class KeychainStoreTests: XCTestCase {

    private var store: KeychainStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try Self.skipIfKeychainUnreachable()
        store = KeychainStore()
        // Defensive cleanup: a prior failed run may have left items
        // behind. Ignore errors here.
        for key in [KeychainStore.KeychainKey.idToken,
                    .accessToken,
                    .refreshToken] {
            try? store.delete(key)
        }
    }

    override func tearDown() {
        // `store` is nil when setUpWithError threw XCTSkip before
        // constructing it; guard so tearDown is a no-op in that case.
        if let store {
            for key in [KeychainStore.KeychainKey.idToken,
                        .accessToken,
                        .refreshToken] {
                try? store.delete(key)
            }
        }
        store = nil
        super.tearDown()
    }

    /// Probe the data-protection keychain with the same query the
    /// canary test uses. If the simulator image refuses unsigned
    /// access (`errSecMissingEntitlement`, -34018), skip the suite —
    /// no production change can fix that here.
    private static func skipIfKeychainUnreachable() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "com.acmebank.mobile.test.canary",
            kSecAttrService as String: "com.acmebank.mobile.auth",
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecMissingEntitlement {
            throw XCTSkip(
                """
                Keychain unreachable from unsigned test bundle on this \
                simulator image (OSStatus -34018 errSecMissingEntitlement). \
                See KeychainStoreTests type doc — KeychainStore callers \
                remain covered by OktaAuthServiceTests with FakeKeychain.
                """
            )
        }
    }

    // MARK: - Round-trip

    func test_set_then_get_returnsTheStoredValue() throws {
        try store.set("hello-world", for: .accessToken)
        XCTAssertEqual(try store.get(.accessToken), "hello-world")
    }

    func test_set_overwritesAnExistingValue() throws {
        try store.set("v1", for: .idToken)
        try store.set("v2", for: .idToken)
        XCTAssertEqual(try store.get(.idToken), "v2")
    }

    func test_get_returnsNil_whenKeyHasNotBeenSet() throws {
        let value = try store.get(.refreshToken)
        XCTAssertNil(value)
    }

    func test_delete_removesAStoredValue() throws {
        try store.set("rt", for: .refreshToken)
        XCTAssertEqual(try store.get(.refreshToken), "rt")

        try store.delete(.refreshToken)
        XCTAssertNil(try store.get(.refreshToken))
    }

    func test_delete_isIdempotent_onNonExistentKey() {
        // Should not throw even though the key was never written.
        XCTAssertNoThrow(try store.delete(.refreshToken))
    }

    func test_keysAreIndependent() throws {
        try store.set("id", for: .idToken)
        try store.set("acc", for: .accessToken)
        try store.set("ref", for: .refreshToken)

        XCTAssertEqual(try store.get(.idToken), "id")
        XCTAssertEqual(try store.get(.accessToken), "acc")
        XCTAssertEqual(try store.get(.refreshToken), "ref")

        try store.delete(.accessToken)

        XCTAssertEqual(try store.get(.idToken), "id")
        XCTAssertNil(try store.get(.accessToken))
        XCTAssertEqual(try store.get(.refreshToken), "ref")
    }

    // MARK: - Simulator-compatibility sanity check

    /// Independent of `KeychainStore`, verify that a hand-rolled query
    /// against the data-protection keychain on the simulator returns
    /// `errSecSuccess` / `errSecItemNotFound` — NOT
    /// `errSecMissingEntitlement` (-34018). If this regresses on a new
    /// Xcode/CI image, every Keychain test in the suite would also
    /// regress; this test surfaces the environment problem explicitly
    /// (as a skip rather than a failure) so the next dev sees the
    /// reason in the test report instead of a misleading red.
    func test_dataProtectionKeychain_isReachableFromUnsignedTestBundle() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "com.acmebank.mobile.test.canary",
            kSecAttrService as String: "com.acmebank.mobile.auth",
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecMissingEntitlement {
            throw XCTSkip(
                """
                Keychain unreachable from unsigned test bundle on this \
                simulator image (OSStatus -34018 errSecMissingEntitlement). \
                The integration suite cannot run here; KeychainStore \
                callers remain covered by OktaAuthServiceTests with \
                FakeKeychain. If you see this skip on a dev machine, \
                check that the test host app is signed with a development \
                team in project.yml.
                """
            )
        }
        XCTAssertTrue(
            status == errSecSuccess || status == errSecItemNotFound,
            "expected success or itemNotFound, got OSStatus \(status)"
        )
    }
}
