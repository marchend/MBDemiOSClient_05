import Foundation

/// Behaviour the UI / coordinator layers depend on, abstracted from any
/// specific identity provider. Concrete implementations:
///   - `OktaAuthService` — production, drives Okta's
///     `DirectAuthenticationFlow`.
///   - Test fakes — supply scripted `signIn` responses for ViewModel
///     unit tests.
///
/// Every method that can fail throws `AuthError` (the typed error enum
/// in this folder) and ONLY `AuthError`. Any post-success plumbing
/// failure inside `signIn` (JWT decode, Keychain write) MUST be either
/// mapped to an `AuthError` case or swallowed — it must never propagate
/// as a bare `KeychainError` / `UserSession.DecodeError`, or the UI's
/// `catch let e as AuthError` will miss it and fall through to a
/// misleading generic-error banner.
public protocol AuthServicing {
    /// Authenticate `username` + `password` with the IdP. On success,
    /// returns a fully-populated `UserSession`. The implementation may
    /// (and `OktaAuthService` does) persist tokens to the Keychain as a
    /// side-effect, but a Keychain-write failure does NOT fail this
    /// call: the in-memory session is still valid for this app launch,
    /// the user simply has to log in again next launch.
    ///
    /// - Parameters:
    ///   - username: Okta sign-in identifier (typically email).
    ///   - password: Plain-text password.
    ///   - keepSignedIn: When `true`, additionally persists the
    ///     refresh token so the app can silently restore the session
    ///     on the next launch.
    /// - Throws: `AuthError` only.
    func signIn(username: String, password: String, keepSignedIn: Bool) async throws -> UserSession

    /// `true` iff a refresh token is currently persisted in the
    /// Keychain. Used at app launch to decide whether to attempt a
    /// silent session restore.
    func hasPersistedSession() -> Bool

    /// Wipe persisted tokens. Idempotent: deleting a non-existent item
    /// is treated as success.
    func signOut() throws

    /// When `true`, `ContentView`'s Login route MUST NOT pre-seed the
    /// "Okta is not configured" error banner even if `OktaConfig.load()`
    /// returned `.notConfigured`.
    ///
    /// This exists so alternative auth conformers that don't consult
    /// `OktaConfig` at all — e.g. the UI-test stub, which returns a
    /// canned `UserSession` regardless of build-time config — can opt
    /// out of the banner without `ContentView` type-checking the
    /// concrete class. The default value is `false` (produced by the
    /// protocol extension below), so `OktaAuthService` and every other
    /// production/test conformer inherits the banner-shown behaviour
    /// without needing to declare the property.
    ///
    /// See the review feedback on `ContentView.makeLoginViewModel`:
    /// the previous version used `authService is UITestStubAuthService`,
    /// which coupled production code to a test-stub type name. This
    /// protocol requirement replaces that coupling with an intent-named
    /// boolean each conformer can override.
    var suppressesNotConfiguredBanner: Bool { get }
}

extension AuthServicing {
    /// Default: production conformers show the banner. Only the
    /// UI-test stub overrides this to `true`.
    public var suppressesNotConfiguredBanner: Bool { false }
}
