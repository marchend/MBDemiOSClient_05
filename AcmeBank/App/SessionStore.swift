import Foundation

/// Single, injected routing target for "end the current session and go
/// back to Login".
///
/// ## Why this exists (the "one routing target" rule)
///
/// Two independent code paths need to terminate the signed-in session:
///
///   1. The Log out button pinned to the bottom of `HomeView`.
///   2. The 401 handler inside `HomeViewModel.load()`, which fires when
///      the BFF rejects the bearer token (expired / revoked / server
///      restart).
///
/// If those two paths clear the session independently they drift apart:
/// one clears the Keychain but forgets to flip the coordinator route;
/// the other flips the route but leaves the refresh token behind so
/// `hasPersistedSession()` still returns `true` on the next launch.
/// A single `SessionStore.signOut()` \u2014 called from *both* sites \u2014 is
/// how we guarantee they can never diverge.
///
/// ## Shape
///
/// `SessionStore` owns two injected hooks and calls them in order:
///
///   1. `credentialClear` \u2014 wipes the persisted Okta credential
///      (Keychain refresh / access / id tokens). The coordinator wires
///      this to `authService.signOut()`. Errors are logged and
///      SWALLOWED: a Keychain delete that already returned
///      `errSecItemNotFound` (or any other exotic OSStatus) must NOT
///      block the route transition, otherwise the user sees Home
///      keep rendering after a Log out tap.
///   2. `onSignedOut` \u2014 flips the coordinator's route back to
///      `.login`. Runs unconditionally after `credentialClear`.
///
/// Both hooks are captured `[weak self]` by the coordinator to avoid
/// the `coordinator \u2192 sessionStore \u2192 coordinator` retain cycle that
/// would otherwise leak the whole app graph across sign-in / sign-out
/// cycles.
///
/// ## Idempotence
///
/// `signOut()` is safe to call any number of times, from any thread
/// state. Concretely:
///
///   * `KeychainStore.delete` treats `errSecItemNotFound` as success,
///     so `authService.signOut()` on an already-signed-out session is
///     a no-op.
///   * `AppCoordinator.didSignOut()` from the `.login` route is also a
///     no-op (the route stays `.login`).
///
/// So a UI double-tap on Log out, or a 401 racing a Log out tap, can
/// only ever result in the same final state \u2014 no partial-cleanup
/// window where the user is "logged out in memory but the UI still
/// shows the old session".
@MainActor
public final class SessionStore {

    /// Clear the persisted Okta credential (Keychain). Errors thrown
    /// by this hook are logged and swallowed \u2014 see the type doc for
    /// why. Wired by the coordinator to `authService.signOut()`.
    private let credentialClear: () -> Void

    /// Route back to the Login screen. Wired by the coordinator to
    /// `AppCoordinator.didSignOut()`.
    private let onSignedOut: () -> Void

    public init(
        credentialClear: @escaping () -> Void,
        onSignedOut: @escaping () -> Void
    ) {
        self.credentialClear = credentialClear
        self.onSignedOut = onSignedOut
    }

    /// End the current session.
    ///
    /// Two-step, both steps ALWAYS run:
    ///
    ///   1. Best-effort credential wipe. Any error thrown by the hook
    ///      itself is up to the hook to handle \u2014 `SessionStore`
    ///      exposes a non-throwing `() -> Void` closure precisely so
    ///      callers of `signOut()` have zero error surface to reason
    ///      about, and a Keychain failure inside the hook cannot
    ///      derail step 2.
    ///   2. Route transition to Login.
    ///
    /// Idempotent \u2014 see the type-level doc for why calling this
    /// twice (Log out double-tap; 401 racing a tap) is safe by
    /// construction.
    public func signOut() {
        credentialClear()
        onSignedOut()
    }
}
