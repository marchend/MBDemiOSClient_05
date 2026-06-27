import SwiftUI

/// Root view of the AcmeBank app.
///
/// `ContentView` is the composition root for the post-app-launch screen
/// graph. It does ONE job: switch on `AppCoordinator.route` and present
/// either `LoginView` or `LandingView`. Every dependency the destination
/// view needs (the `LoginViewModel` with a fully-wired `onSignIn`
/// closure, the `UserSession` for landing) is constructed here.
///
/// The `LoginViewModel` is built fresh each time the coordinator routes
/// back to `.login` so a previous sign-in attempt's transient state
/// (typed credentials, error banner, in-flight spinner) cannot leak
/// across a sign-out / sign-in cycle. The view's own `@StateObject`
/// keeps the lifecycle anchored to that single `.login` presentation.
struct ContentView: View {

    @EnvironmentObject private var coordinator: AppCoordinator

    /// Production `AuthServicing` used by the `onSignIn` closure.
    /// Defaulted so previews and tests can substitute a fake without
    /// touching the real Okta SDK.
    let authService: AuthServicing

    /// Pre-load Okta config once so the not-configured banner can be
    /// surfaced before the user types anything. Equivalent to calling
    /// `OktaConfig.load()` directly; injected so previews / tests can
    /// inject a `.notConfigured(...)` value to exercise that path.
    let configProvider: () -> OktaConfig

    init(
        authService: AuthServicing = OktaAuthService(),
        configProvider: @escaping () -> OktaConfig = { OktaConfig.load() }
    ) {
        self.authService = authService
        self.configProvider = configProvider
    }

    var body: some View {
        switch coordinator.route {
        case .login:
            LoginView(viewModel: makeLoginViewModel())
        case .landing(let session):
            LandingView(session: session)
        }
    }

    // MARK: - Composition

    /// Build a `LoginViewModel` with the real `onSignIn` wiring.
    ///
    /// Behaviour:
    ///   1. Flips `isSigningIn = true` immediately so the Sign In button
    ///      disables and the spinner appears, preventing rapid double-taps.
    ///   2. Awaits `authService.signIn(...)` on the MainActor.
    ///   3. On success, hands the resulting `UserSession` to the
    ///      coordinator which switches the root view to `LandingView`.
    ///   4. On `AuthError`, surfaces the AC7 user-facing copy via
    ///      `error.userMessage`. Any non-`AuthError` is logged and shown
    ///      with `.network`'s copy (belt-and-braces — `OktaAuthService`
    ///      already coerces every escape path to `AuthError`, so this
    ///      arm should be unreachable in production).
    ///   5. Always flips `isSigningIn = false` in a `defer` so a thrown
    ///      error or unexpected return path never leaves the UI stuck
    ///      in the spinner state.
    ///
    /// If Okta is not configured at build time we pre-populate
    /// `errorMessage` with the not-configured copy so the user sees
    /// what's wrong without having to tap Sign In to discover it.
    private func makeLoginViewModel() -> LoginViewModel {
        let viewModel = LoginViewModel()

        // AC: with no OKTA_* env vars, launch to Login with the
        // "Okta is not configured" banner pre-set.
        if case let .notConfigured(reason) = configProvider() {
            viewModel.errorMessage =
                "Okta is not configured on this build — see README. (\(reason))"
        }

        viewModel.onSignIn = { [authService] username, password, keepSignedIn in
            Task { @MainActor in
                viewModel.isSigningIn = true
                viewModel.errorMessage = nil
                defer { viewModel.isSigningIn = false }

                do {
                    let session = try await authService.signIn(
                        username: username,
                        password: password,
                        keepSignedIn: keepSignedIn
                    )
                    coordinator.didSignIn(session)
                } catch let authError as AuthError {
                    viewModel.errorMessage = authError.userMessage
                } catch {
                    // Belt-and-braces: OktaAuthService maps every error
                    // path to AuthError, so this arm should never fire.
                    // If it does, surface the network copy rather than
                    // a raw Swift error and log for diagnostics.
                    print("[ContentView] unexpected non-AuthError from signIn: \(error)")
                    viewModel.errorMessage = AuthError.network.userMessage
                }
            }
        }

        return viewModel
    }
}

#Preview("Login route") {
    ContentView()
        .environmentObject(AppCoordinator(authService: PreviewAuthService()))
}

#Preview("Landing route") {
    let coordinator = AppCoordinator(authService: PreviewAuthService())
    coordinator.didSignIn(
        UserSession(
            userId: "preview-sub",
            displayName: "Preview User",
            email: "preview@acmebank.com",
            accessToken: "preview-access",
            authTimestamp: Date(),
            deviceName: "Preview"
        )
    )
    return ContentView().environmentObject(coordinator)
}

/// Preview-only `AuthServicing` stub. Never reaches the real network.
private final class PreviewAuthService: AuthServicing {
    func signIn(username: String, password: String, keepSignedIn: Bool) async throws -> UserSession {
        throw AuthError.notConfigured("preview")
    }
    func hasPersistedSession() -> Bool { false }
    func signOut() throws {}
}
