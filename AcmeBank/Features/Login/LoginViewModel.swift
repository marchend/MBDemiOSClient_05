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

    // MARK: - Computed State

    /// `true` when both username and password contain at least one character.
    var isSignInEnabled: Bool {
        !username.isEmpty && !password.isEmpty
    }

    // MARK: - Callbacks

    /// Called by `signIn()` with the collected credentials.
    ///
    /// Defaults to a no-op so LoginView can be instantiated without wiring
    /// any navigation logic (useful in previews and unit tests).
    var onSignIn: (String, String, Bool) -> Void = { _, _, _ in }

    // MARK: - Actions

    /// Validates fields and calls `onSignIn` when both are non-empty.
    func signIn() {
        guard isSignInEnabled else { return }
        onSignIn(username, password, keepSignedIn)
    }
}
