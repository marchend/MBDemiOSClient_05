import XCTest
@testable import AcmeBank

/// Unit tests for `SessionStore.signOut()`.
///
/// The store is intentionally a thin two-hook coordinator (see the
/// type-level doc in `SessionStore.swift`), so these tests verify
/// exactly that contract:
///
///   1. `signOut()` invokes the injected `credentialClear` hook.
///   2. `signOut()` invokes the injected `onSignedOut` hook.
///   3. Calling `signOut()` twice is idempotent — both hooks fire
///      once per call, and neither invocation crashes / re-enters.
///
/// Any `SecItem*` call in test setup / teardown is a red flag here:
/// this test does NOT touch the Keychain — the whole point of the
/// `credentialClear` hook is that the store never depends on a
/// concrete keychain type. If a future change routes real
/// `SecItem*` calls through this test target, add
/// `kSecUseDataProtectionKeychain: true` to every query dictionary
/// or the calls will return `errSecMissingEntitlement` (-34018) on
/// the Simulator unit-test host and the whole suite goes red.
@MainActor
final class SessionStoreSignOutTests: XCTestCase {

    /// Test-only counter wrapped in a class so multiple closures can
    /// mutate the same box without escaping-capture warnings.
    private final class CallCounter {
        var count: Int = 0
        func bump() { count += 1 }
    }

    /// `signOut()` invokes the credential-clear hook exactly once.
    func test_signOut_invokesCredentialClearHook() {
        let credentialClearCounter = CallCounter()
        let onSignedOutCounter = CallCounter()

        let store = SessionStore(
            credentialClear: { credentialClearCounter.bump() },
            onSignedOut: { onSignedOutCounter.bump() }
        )

        store.signOut()

        XCTAssertEqual(credentialClearCounter.count, 1,
                       "signOut() must invoke the credential-clear hook exactly once")
    }

    /// `signOut()` invokes the on-signed-out hook exactly once.
    func test_signOut_invokesOnSignedOutHook() {
        let credentialClearCounter = CallCounter()
        let onSignedOutCounter = CallCounter()

        let store = SessionStore(
            credentialClear: { credentialClearCounter.bump() },
            onSignedOut: { onSignedOutCounter.bump() }
        )

        store.signOut()

        XCTAssertEqual(onSignedOutCounter.count, 1,
                       "signOut() must invoke the on-signed-out hook exactly once")
    }

    /// The credential-clear hook runs BEFORE the on-signed-out hook.
    ///
    /// This ordering matters: if the coordinator routes to `.login`
    /// first (via `onSignedOut`), a racing observer of the route
    /// change could re-read `authService.hasPersistedSession()` and
    /// briefly see the *old* refresh token still in the Keychain,
    /// producing a "cold-launch would land on Landing" false
    /// positive during the sign-out transition. Clearing the
    /// credential first closes that window.
    func test_signOut_credentialClearRunsBeforeOnSignedOut() {
        var order: [String] = []

        let store = SessionStore(
            credentialClear: { order.append("credentialClear") },
            onSignedOut: { order.append("onSignedOut") }
        )

        store.signOut()

        XCTAssertEqual(order, ["credentialClear", "onSignedOut"],
                       "credentialClear must run before onSignedOut")
    }

    /// Calling `signOut()` twice fires each hook twice — no latching,
    /// no dedup. The store leaves idempotence up to its hooks; the
    /// production wiring (`KeychainStore.delete` treats not-found as
    /// success; `AppCoordinator.didSignOut()` from `.login` is a
    /// no-op) is what makes the second call harmless. This test
    /// nails down the store's own contract.
    func test_signOut_calledTwice_invokesEachHookTwice() {
        let credentialClearCounter = CallCounter()
        let onSignedOutCounter = CallCounter()

        let store = SessionStore(
            credentialClear: { credentialClearCounter.bump() },
            onSignedOut: { onSignedOutCounter.bump() }
        )

        store.signOut()
        store.signOut()

        XCTAssertEqual(credentialClearCounter.count, 2,
                       "credentialClear must fire on every signOut() call")
        XCTAssertEqual(onSignedOutCounter.count, 2,
                       "onSignedOut must fire on every signOut() call")
    }

    /// The AppCoordinator-wired store is functionally idempotent from
    /// the caller's perspective: two `signOut()` calls in a row from
    /// the `.landing` route leave the route on `.login` (not oscillating
    /// or crashing). This is the "double-tap safe / 401-races-a-tap
    /// safe" invariant HomeView's Log out button relies on.
    func test_signOut_viaCoordinator_isIdempotentAtTheRouteLevel() {
        let auth = FakeAuthServicing()
        auth.persistedSession = true
        let session = UserSession(
            userId: "u",
            displayName: "U",
            email: "u@example.com",
            accessToken: "tok",
            authTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test"
        )
        let coordinator = AppCoordinator(authService: auth, cachedSession: { session })
        XCTAssertEqual(coordinator.route, .landing(session),
                       "precondition: coordinator should start on .landing(session)")

        coordinator.sessionStore.signOut()
        XCTAssertEqual(coordinator.route, .login,
                       "First signOut() must route to .login")

        coordinator.sessionStore.signOut()
        XCTAssertEqual(coordinator.route, .login,
                       "Second signOut() must still leave the route on .login (idempotent)")

        // credentialClear fires on BOTH calls; the underlying
        // `authService.signOut()` treats not-found as success so
        // the second call is a harmless no-op.
        XCTAssertEqual(auth.signOutCallCount, 2,
                       "credentialClear hook must invoke authService.signOut() on every signOut() call")
    }

    // MARK: - Test doubles

    /// Scriptable `AuthServicing` fake — same shape as the one in
    /// `AppCoordinatorTests`, but with a `signOut()` call counter so
    /// we can prove the coordinator-wired credential-clear hook is
    /// actually invoking it.
    private final class FakeAuthServicing: AuthServicing {
        var persistedSession: Bool = false
        var signOutCallCount: Int = 0
        var signOutError: Error?

        func signIn(username: String, password: String, keepSignedIn: Bool) async throws -> UserSession {
            XCTFail("SessionStore should never call signIn")
            throw AuthError.notConfigured("test")
        }

        func hasPersistedSession() -> Bool {
            return persistedSession
        }

        func signOut() throws {
            signOutCallCount += 1
            if let error = signOutError {
                throw error
            }
        }
    }
}
