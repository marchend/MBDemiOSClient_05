import XCTest
@testable import AcmeBank

/// Unit tests for `AppCoordinator` route transitions.
///
/// All tests are `@MainActor` because `AppCoordinator` is itself
/// `@MainActor`-isolated — calling its init or methods from the test
/// runner's nonisolated context would otherwise produce a strict-
/// concurrency warning under Swift 5.10.
@MainActor
final class AppCoordinatorTests: XCTestCase {

    // MARK: - Test doubles

    /// Scriptable `AuthServicing` fake used to drive `hasPersistedSession`
    /// at init time. The `signIn` / `signOut` methods are not exercised
    /// by these tests (the coordinator never calls them today — sign-in
    /// is driven from `ContentView`'s `LoginViewModel.onSignIn` closure).
    final class FakeAuthServicing: AuthServicing {
        var persistedSession: Bool = false

        func signIn(username: String, password: String, keepSignedIn: Bool) async throws -> UserSession {
            XCTFail("AppCoordinator should never call signIn directly")
            throw AuthError.notConfigured("test")
        }

        func hasPersistedSession() -> Bool {
            return persistedSession
        }

        func signOut() throws {
            XCTFail("AppCoordinator should never call signOut directly")
        }
    }

    // MARK: - Fixtures

    private func makeSession(name: String = "Marc Henderson",
                             email: String = "marc@acmebank.com") -> UserSession {
        return UserSession(
            userId: "00uabc123",
            displayName: name,
            email: email,
            accessToken: "test-access-token",
            authTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test Device"
        )
    }

    // MARK: - Initial route

    /// AC1: cold launch with no Keychain refresh token → Login.
    func test_initialRoute_isLogin_whenNoPersistedSession() {
        let auth = FakeAuthServicing()
        auth.persistedSession = false

        let coordinator = AppCoordinator(authService: auth)

        XCTAssertEqual(coordinator.route, .login,
                       "With no persisted session the initial route must be .login")
    }

    /// AC2: cold launch with a Keychain refresh token AND a cached
    /// `UserSession` decodable from the keychain → Landing.
    func test_initialRoute_isLanding_whenPersistedSessionAndCachedSessionAvailable() {
        let auth = FakeAuthServicing()
        auth.persistedSession = true
        let cached = makeSession()

        let coordinator = AppCoordinator(authService: auth, cachedSession: { cached })

        XCTAssertEqual(coordinator.route, .landing(cached),
                       "With a persisted session AND a cached UserSession the initial route must be .landing(session)")
    }

    /// Refresh token present but no cached `UserSession` (silent re-auth
    /// would be required, which is deferred) → falls back to Login.
    /// This is the "session present but we cannot yet rehydrate a full
    /// UserSession" clause in the plan.
    func test_initialRoute_isLogin_whenPersistedSessionButNoCachedSession() {
        let auth = FakeAuthServicing()
        auth.persistedSession = true

        let coordinator = AppCoordinator(authService: auth, cachedSession: { nil })

        XCTAssertEqual(coordinator.route, .login,
                       "A refresh token without a decodable cached UserSession must fall back to .login")
    }

    // MARK: - didSignIn

    /// `didSignIn` transitions from `.login` to `.landing(session)` and
    /// carries the supplied session.
    func test_didSignIn_transitionsToLanding_carryingTheSession() {
        let auth = FakeAuthServicing()
        let coordinator = AppCoordinator(authService: auth)
        XCTAssertEqual(coordinator.route, .login)

        let session = makeSession(name: "Alice", email: "alice@acmebank.com")
        coordinator.didSignIn(session)

        XCTAssertEqual(coordinator.route, .landing(session),
                       "didSignIn must transition the route to .landing carrying the exact session passed in")
    }

    /// Calling `didSignIn` while already on Landing replaces the
    /// carried session (e.g. a re-auth that yields fresh claims).
    func test_didSignIn_whileLanding_replacesSession() {
        let auth = FakeAuthServicing()
        let first = makeSession(name: "Alice", email: "alice@acmebank.com")
        let coordinator = AppCoordinator(authService: auth, cachedSession: { first })
        XCTAssertEqual(coordinator.route, .landing(first))

        let second = makeSession(name: "Bob", email: "bob@acmebank.com")
        coordinator.didSignIn(second)

        XCTAssertEqual(coordinator.route, .landing(second),
                       "didSignIn from .landing must replace the carried session with the new one")
    }

    // MARK: - didSignOut

    /// `didSignOut` from Landing transitions back to Login.
    func test_didSignOut_fromLanding_transitionsToLogin() {
        let auth = FakeAuthServicing()
        let coordinator = AppCoordinator(authService: auth, cachedSession: { self.makeSession() })
        XCTAssertNotEqual(coordinator.route, .login)

        coordinator.didSignOut()

        XCTAssertEqual(coordinator.route, .login,
                       "didSignOut from .landing must transition to .login")
    }

    /// `didSignOut` while already on Login is an idempotent no-op
    /// (does not crash or change state).
    func test_didSignOut_whileLogin_isIdempotent() {
        let auth = FakeAuthServicing()
        let coordinator = AppCoordinator(authService: auth)
        XCTAssertEqual(coordinator.route, .login)

        coordinator.didSignOut()

        XCTAssertEqual(coordinator.route, .login,
                       "didSignOut from .login must remain on .login")
    }
}
