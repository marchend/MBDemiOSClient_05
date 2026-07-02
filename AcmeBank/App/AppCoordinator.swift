import Foundation
import Combine

/// Top-level navigation state machine for the app.
///
/// `AppCoordinator` owns exactly one piece of published state — `route` —
/// which `ContentView` switches on to decide whether to show `LoginView`
/// or the post-login `HomeView`. It deliberately has no SwiftUI
/// imports: navigation state is a pure domain concern, and keeping it
/// framework-free lets unit tests drive transitions without
/// instantiating any view.
///
/// Cold-launch gating:
///   - No persisted refresh token in Keychain          → `.login`
///   - Refresh token present BUT no cached `UserSession`
///     (silent re-auth would be needed)                → `.login`
///   - Refresh token present AND a minimal `UserSession`
///     can be reconstructed from the cached id-token   → `.landing(session)`
///
/// "Silent re-auth" — calling Okta with the refresh token to mint a fresh
/// access token at cold launch — is intentionally deferred to a follow-up
/// PR. Until then, a Keychain refresh-token without a decodable id-token
/// falls back to `.login` so the user re-enters credentials rather than
/// landing on a screen backed by a stale or unreadable session.
///
/// ## Sign-out (Log out button + 401)
///
/// The coordinator owns a single `SessionStore` whose `signOut()` is
/// the ONE routing target for terminating a session. Both callers —
/// the Log out button on `HomeView`, and `HomeViewModel`'s 401 handler
/// — funnel through it. The store's two injected hooks close over
/// `self` `unowned` (the coordinator owns the store and therefore
/// always outlives it) and call `authService.signOut()` (best effort,
/// errors swallowed) and `didSignOut()`. See `SessionStore.swift` for
/// the "one routing target" rationale and idempotence proof.
@MainActor
public final class AppCoordinator: ObservableObject {

    /// The two top-level destinations the app can be in. `.landing`
    /// carries the session so the destination view can render the
    /// signed-in user's claims without re-reading the Keychain.
    public enum AppRoute: Equatable {
        case login
        case landing(UserSession)
    }

    /// Currently-displayed top-level screen. SwiftUI observes this via
    /// `@EnvironmentObject` and re-renders `ContentView` when it changes.
    @Published public private(set) var route: AppRoute

    /// Auth service used to probe for a persisted session at launch and
    /// to drive sign-out from inside the app.
    ///
    /// Exposed (read-only) so `ContentView` can thread the *same*
    /// instance into the `LoginView`'s `onSignIn` wiring, rather than
    /// constructing a second `OktaAuthService` at composition time —
    /// otherwise two parallel owners would touch the Keychain and a
    /// later sign-out wired to the coordinator's copy would diverge
    /// from the one that actually performed the sign-in.
    public let authService: AuthServicing

    /// Single routing target for "end this session" \(shared between
    /// the Log out button and every 401 handler\). See the type doc
    /// on `SessionStore` for the "one routing target" invariant.
    ///
    /// Lazily constructed on first access so the initializer's
    /// "closures can't reference `self` before all stored properties
    /// are set" problem goes away without an implicitly-unwrapped
    /// optional. The previous version declared this as
    /// `public private(set) var sessionStore: SessionStore!` and
    /// assigned it inside `init` — which worked, but reviewers flagged
    /// (correctly) that a `public` IUO is a runtime-crash trap: any
    /// future `init` overload that forgets the assignment compiles
    /// cleanly and crashes at first sign-out.
    ///
    /// A `lazy var` with `[unowned self]` captures inside the store's
    /// hook closures is the fix the reviewer recommended:
    ///
    ///   * `lazy` means the property is initialised on first access
    ///     (in practice: the first `sessionStore.signOut()` call, or
    ///     `ContentView` reading it to wire up the Log out button —
    ///     both happen well after `AppCoordinator.init` returns), so
    ///     the DI-order problem inside `init` disappears entirely.
    ///   * `[unowned self]` in the hook closures is safe by
    ///     construction: `AppCoordinator` owns `SessionStore`, so the
    ///     store cannot outlive its owner and the hook cannot fire
    ///     against a deallocated `self`. `[unowned]` (vs `[weak]`)
    ///     removes the optional gymnastics inside each hook.
    ///   * The property is no longer an IUO — it's a non-optional
    ///     `SessionStore`, so calling code never sees `sessionStore?`
    ///     / `sessionStore!` at any use site.
    ///
    /// `lazy var` is not settable from outside (the property has no
    /// public setter), so callers cannot reassign the store; the
    /// invariant "exactly one `SessionStore` per coordinator" is
    /// preserved.
    public private(set) lazy var sessionStore: SessionStore = SessionStore(
        credentialClear: { [unowned self] in
            // Best-effort: a Keychain failure MUST NOT block the
            // route transition, otherwise the user could tap
            // Log out and see Home stay on-screen. Errors are
            // logged; `KeychainStore.delete` already treats
            // "not found" as success so idempotence is safe by
            // construction.
            do {
                try self.authService.signOut()
            } catch {
                print("[AppCoordinator] authService.signOut() failed: \(error) — continuing")
            }
        },
        onSignedOut: { [unowned self] in
            self.didSignOut()
        }
    )

    // MARK: - Initializers

    /// Production initializer. Inspects `authService.hasPersistedSession()`
    /// and the cached session (via the supplied `cachedSession` closure)
    /// to compute the initial route exactly once at launch.
    ///
    /// `cachedSession` is a closure rather than a stored value so tests
    /// can inject scripted return values without depending on the real
    /// Keychain. The production wiring (in `AcmeBankApp`) currently
    /// returns `nil` — silent re-auth lands in a follow-up PR — so the
    /// "refresh token present, no cached session" arm always falls to
    /// `.login` in production today.
    public init(
        authService: AuthServicing,
        cachedSession: () -> UserSession? = { nil }
    ) {
        self.authService = authService
        if authService.hasPersistedSession(), let session = cachedSession() {
            self.route = .landing(session)
        } else {
            self.route = .login
        }
        // `sessionStore` is declared `lazy var` above — its
        // initializer runs on first access, not here. Contrast the
        // previous IUO-based approach that had to construct the store
        // inside this initializer to satisfy the non-nil invariant.
    }

    // MARK: - Transitions

    /// Called by `LoginView`'s `onSignIn` closure on a successful Okta
    /// exchange. Hands the freshly-built `UserSession` to the landing
    /// destination.
    public func didSignIn(_ session: UserSession) {
        route = .landing(session)
    }

    /// Called when the signed-in user signs out (or the session is
    /// invalidated by the server). Returns the app to the Login screen.
    ///
    /// Idempotent from `.login` (the route stays `.login`), so a
    /// double invocation from `SessionStore.signOut()` — e.g. a UI
    /// double-tap racing a 401 — cannot corrupt state.
    public func didSignOut() {
        route = .login
    }
}
