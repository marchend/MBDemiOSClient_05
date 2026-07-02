import SwiftUI

/// Application entry point.
///
/// Owns the single `AppCoordinator` instance for the process lifetime
/// as a `@StateObject` so SwiftUI anchors its identity to the `App` and
/// guarantees it survives across `body` re-evaluations. Injects it into
/// `ContentView` (and the whole view tree) via `.environmentObject`.
///
/// `OktaAuthService` is the production `AuthServicing` conformer. If
/// `OktaConfig.load()` returns `.notConfigured`, `signIn` will fail
/// fast with `AuthError.notConfigured(reason)` and the Login view
/// surfaces the "Okta is not configured on this build — see README."
/// banner that `ContentView.makeLoginViewModel()` pre-seeds.
///
/// ## UI-test stub seam (`UITEST_STUB_HOME=1`)
///
/// When launched with the `UITEST_STUB_HOME=1` launch argument, the
/// app substitutes:
///
///   * `authService` → `UITestStubAuthService` — signIn accepts any
///     credentials and returns a fixture `UserSession` keyed by
///     username so the test can drive the "sign in as user A → sign
///     out → sign in as user B" flow without a real Okta round-trip.
///   * `homeRepositoryFactory` → returns `StubHomeRepository` fixtures
///     keyed by session, so the two fixture users render *distinct*
///     account counts (the assertion the UI test relies on).
///
/// This is the ONLY code path in the production target that references
/// `StubHomeRepository` at runtime; every other reference sits inside
/// `#Preview` blocks. The launch-argument gate ensures a shipping build
/// launched without the flag can never fall into the stub branch.
@main
struct AcmeBankApp: App {

    @StateObject private var coordinator: AppCoordinator

    /// Factory the composition root uses to build a `HomeRepositoryProtocol`
    /// for a freshly-signed-in `UserSession`. Production: constructs a
    /// `BFFHomeRepository` bound to the session's access token.
    /// UI-test stub path: returns a `StubHomeRepository` keyed by
    /// `session.userId` so distinct users see distinct data.
    private let homeRepositoryFactory: (UserSession) -> HomeRepositoryProtocol

    init() {
        let stubMode = ProcessInfo.processInfo.arguments.contains("UITEST_STUB_HOME=1")
        if stubMode {
            let auth: AuthServicing = UITestStubAuthService()
            _coordinator = StateObject(wrappedValue: AppCoordinator(authService: auth))
            self.homeRepositoryFactory = { session in
                StubHomeRepository(behaviour: .success(UITestHomeFixtures.dashboard(for: session)))
            }
        } else {
            let auth: AuthServicing = OktaAuthService()
            _coordinator = StateObject(wrappedValue: AppCoordinator(authService: auth))
            self.homeRepositoryFactory = { session in
                BFFHomeRepository(accessTokenProvider: { session.accessToken })
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(homeRepositoryFactory: homeRepositoryFactory)
                .environmentObject(coordinator)
        }
    }
}
