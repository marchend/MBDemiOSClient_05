import Foundation
import Combine

/// Top-level navigation state machine for the app.
///
/// `AppCoordinator` owns exactly one piece of published state — `route` —
/// which `ContentView` switches on to decide whether to show `LoginView`
/// or `LandingView`. It deliberately has no SwiftUI imports: navigation
/// state is a pure domain concern, and keeping it framework-free lets
/// unit tests drive transitions without instantiating any view.
///
/// Cold-launch gating (per PR 4 plan, AC1 + AC2):
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
    /// (in future) to drive sign-out from inside the app.
    private let authService: AuthServicing

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
    public func didSignOut() {
        route = .login
    }
}
