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
final class KeychainStoreTests: XCTestCase {

    private var store: KeychainStore!

    override func setUp() {
        super.setUp()
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
        for key in [KeychainStore.KeychainKey.idToken,
                    .accessToken,
                    .refreshToken] {
            try? store.delete(key)
        }
        store = nil
        super.tearDown()
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
    /// regress; failing this one isolates the root cause.
    func test_dataProtectionKeychain_isReachableFromUnsignedTestBundle() {
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
        XCTAssertTrue(
            status == errSecSuccess || status == errSecItemNotFound,
            "expected success or itemNotFound, got OSStatus \(status)"
        )
    }
}
