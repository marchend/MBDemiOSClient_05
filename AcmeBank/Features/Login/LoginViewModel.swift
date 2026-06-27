import Foundation

/// ViewModel for the Login screen.
///
/// Holds all published state consumed by `LoginView`.
/// The `onSignIn` closure is injected by the caller (e.g. `ContentView` or a
/// future `LoginCoordinator`) so this ViewModel has zero navigation knowledge.
///
/// **Do not mark the whole class `@MainActor`** — the default initialiser is called
/// from a `@StateObject` property default-arg which runs in a non-isolated context
/// (Swift 5.10 strict concurrency). Only async worker methods are annotated.
final class LoginViewModel: ObservableObject {

    // MARK: - Published State

    @Published var username: String = ""
    @Published var password: String = ""
    @Published var isPasswordVisible: Bool = false
    @Published var keepSignedIn: Bool = false
    @Published var errorMessage: String?

    /// `true` while an authentication call is in flight.
    ///
    /// `LoginView` observes this to:
    /// 1. Disable the Sign In button (via `isSignInEnabled`) so a rapid
    ///    double-tap can't dispatch two concurrent auth requests.
    /// 2. Show an inline spinner / disable input fields while we wait for
    ///    the `AuthService` response (wiring lands in MBE2EDEM05-10).
    ///
    /// Owned here (not on `AuthService`) so the View can read it as plain
    /// published state without subscribing to a service publisher.
    @Published var isSigningIn: Bool = false

    // MARK: - Computed State

    /// `true` when both username and password contain at least one character
    /// AND no sign-in is currently in flight. The in-flight check guarantees
    /// the Sign In button is disabled the instant `signIn()` flips
    /// `isSigningIn` to `true`, preventing duplicate auth requests.
    var isSignInEnabled: Bool {
        !username.isEmpty && !password.isEmpty && !isSigningIn
    }

    // MARK: - Callbacks

    /// Called by `signIn()` with the collected credentials.
    ///
    /// Defaults to a no-op so LoginView can be instantiated without wiring
    /// any navigation logic (useful in previews and unit tests).
    var onSignIn: (String, String, Bool) -> Void = { _, _, _ in }

    // MARK: - Actions

    /// Validates fields and calls `onSignIn` when both are non-empty and no
    /// sign-in is already in flight. `isSigningIn` gates re-entry: a second
    /// tap that arrives before the caller flips `isSigningIn` back to false
    /// is dropped on the floor.
    func signIn() {
        guard isSignInEnabled else { return }
        onSignIn(username, password, keepSignedIn)
    }

    /// Clears any visible auth-error banner.
    ///
    /// `LoginView` calls this from `.onChange(of: username)` and
    /// `.onChange(of: password)` so the moment the user starts correcting
    /// their input, the stale "Incorrect username or password" banner
    /// disappears — per MBE2EDEM05-9 AC #7. Idempotent and cheap to call
    /// on every keystroke; if `errorMessage` is already `nil` this is a
    /// no-op and SwiftUI will skip the redraw.
    func clearErrorOnEdit() {
        if errorMessage != nil {
            errorMessage = nil
        }
    }
}
