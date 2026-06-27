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
@main
struct AcmeBankApp: App {

    @StateObject private var coordinator = AppCoordinator(authService: OktaAuthService())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
        }
    }
}
