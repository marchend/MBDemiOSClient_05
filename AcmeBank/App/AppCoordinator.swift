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
/// — funnel through it. The store's two injected hooks are
/// `[weak self]` closures that call `authService.signOut()` (best
/// effort, errors swallowed) and `self.didSignOut()`. See
/// `SessionStore.swift` for the "one routing target" rationale and
/// idempotence proof.
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
    /// Constructed once at coordinator init time and reused for the
    /// lifetime of the coordinator; the hooks capture `self` weakly
    /// to avoid a `coordinator ↔ sessionStore` retain cycle.
    public private(set) var sessionStore: SessionStore!

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

        // Two-phase init: `SessionStore`'s hooks need to reference
        // `self`, so we cannot construct the store in the property's
        // default expression. Building it here with `[weak self]`
        // captures avoids the retain cycle `AppCoordinator →
        // SessionStore → AppCoordinator` that would otherwise leak
        // the entire root graph across a sign-out / sign-in cycle.
        self.sessionStore = SessionStore(
            credentialClear: { [weak self] in
                guard let self else { return }
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
            onSignedOut: { [weak self] in
                self?.didSignOut()
            }
        )
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
