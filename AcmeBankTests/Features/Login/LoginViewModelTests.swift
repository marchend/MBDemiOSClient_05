import XCTest
@testable import AcmeBank

final class LoginViewModelTests: XCTestCase {

    // MARK: - isSignInEnabled

    func test_isSignInEnabled_falseWhenBothFieldsEmpty() {
        let vm = LoginViewModel()
        XCTAssertFalse(vm.isSignInEnabled,
                       "isSignInEnabled must be false when both fields are empty")
    }

    func test_isSignInEnabled_falseWhenUsernameEmpty() {
        let vm = LoginViewModel()
        vm.password = "secret"
        XCTAssertFalse(vm.isSignInEnabled,
                       "isSignInEnabled must be false when username is empty")
    }

    func test_isSignInEnabled_falseWhenPasswordEmpty() {
        let vm = LoginViewModel()
        vm.username = "user@acmebank.com"
        XCTAssertFalse(vm.isSignInEnabled,
                       "isSignInEnabled must be false when password is empty")
    }

    func test_isSignInEnabled_trueWhenBothFieldsNonEmpty() {
        let vm = LoginViewModel()
        vm.username = "user@acmebank.com"
        vm.password = "secret"
        XCTAssertTrue(vm.isSignInEnabled,
                      "isSignInEnabled must be true when both fields contain text")
    }

    func test_isSignInEnabled_falseWhileSigningIn() {
        let vm = LoginViewModel()
        vm.username = "user@acmebank.com"
        vm.password = "secret"
        vm.isSigningIn = true
        XCTAssertFalse(vm.isSignInEnabled,
                       "isSignInEnabled must be false while a sign-in is in flight, even with valid fields")
    }

    func test_isSignInEnabled_trueAfterSigningInClears() {
        let vm = LoginViewModel()
        vm.username = "user@acmebank.com"
        vm.password = "secret"
        vm.isSigningIn = true
        vm.isSigningIn = false
        XCTAssertTrue(vm.isSignInEnabled,
                      "isSignInEnabled must return to true once isSigningIn clears")
    }

    // MARK: - signIn

    func test_signIn_callsOnSignInWithCorrectArguments() {
        let vm = LoginViewModel()
        vm.username = "alice@acmebank.com"
        vm.password = "p@ssw0rd"
        vm.keepSignedIn = true

        var capturedUsername: String?
        var capturedPassword: String?
        var capturedKeepSignedIn: Bool?
        var callCount = 0

        vm.onSignIn = { username, password, keepSignedIn in
            capturedUsername = username
            capturedPassword = password
            capturedKeepSignedIn = keepSignedIn
            callCount += 1
        }

        vm.signIn()

        XCTAssertEqual(callCount, 1, "onSignIn should be called exactly once")
        XCTAssertEqual(capturedUsername, "alice@acmebank.com")
        XCTAssertEqual(capturedPassword, "p@ssw0rd")
        XCTAssertEqual(capturedKeepSignedIn, true)
    }

    func test_signIn_doesNotCallOnSignInWhenFieldsEmpty() {
        let vm = LoginViewModel()
        var callCount = 0
        vm.onSignIn = { _, _, _ in callCount += 1 }

        vm.signIn()

        XCTAssertEqual(callCount, 0,
                       "onSignIn must not be called when fields are empty")
    }

    func test_signIn_doesNotCallOnSignInWhenOnlyUsernameSet() {
        let vm = LoginViewModel()
        vm.username = "alice@acmebank.com"
        var callCount = 0
        vm.onSignIn = { _, _, _ in callCount += 1 }

        vm.signIn()

        XCTAssertEqual(callCount, 0,
                       "onSignIn must not be called when password is empty")
    }

    func test_signIn_doesNotCallOnSignInWhileAlreadySigningIn() {
        let vm = LoginViewModel()
        vm.username = "alice@acmebank.com"
        vm.password = "p@ssw0rd"
        vm.isSigningIn = true

        var callCount = 0
        vm.onSignIn = { _, _, _ in callCount += 1 }

        vm.signIn()

        XCTAssertEqual(callCount, 0,
                       "onSignIn must not re-fire while a sign-in is already in flight (rapid double-tap guard)")
    }

    // MARK: - Initial State

    func test_errorMessage_isNilOnInit() {
        let vm = LoginViewModel()
        XCTAssertNil(vm.errorMessage,
                     "errorMessage must be nil on initialisation")
    }

    func test_username_isEmptyOnInit() {
        let vm = LoginViewModel()
        XCTAssertEqual(vm.username, "",
                       "username must be empty on initialisation")
    }

    func test_password_isEmptyOnInit() {
        let vm = LoginViewModel()
        XCTAssertEqual(vm.password, "",
                       "password must be empty on initialisation")
    }

    func test_keepSignedIn_isFalseOnInit() {
        let vm = LoginViewModel()
        XCTAssertFalse(vm.keepSignedIn,
                       "keepSignedIn must be false on initialisation")
    }

    func test_isSigningIn_isFalseOnInit() {
        let vm = LoginViewModel()
        XCTAssertFalse(vm.isSigningIn,
                       "isSigningIn must be false on initialisation")
    }

    // MARK: - isPasswordVisible

    func test_isPasswordVisible_startsFalse() {
        let vm = LoginViewModel()
        XCTAssertFalse(vm.isPasswordVisible,
                       "isPasswordVisible must start false")
    }

    func test_isPasswordVisible_togglesToTrue() {
        let vm = LoginViewModel()
        vm.isPasswordVisible.toggle()
        XCTAssertTrue(vm.isPasswordVisible,
                      "isPasswordVisible must be true after one toggle")
    }

    func test_isPasswordVisible_togglesBackToFalse() {
        let vm = LoginViewModel()
        vm.isPasswordVisible.toggle()
        vm.isPasswordVisible.toggle()
        XCTAssertFalse(vm.isPasswordVisible,
                       "isPasswordVisible must return to false after two toggles")
    }

    // MARK: - clearErrorOnEdit (AC #7)

    /// Setting `errorMessage` to a string and calling `clearErrorOnEdit`
    /// resets it to `nil` — this is what `LoginView` calls from
    /// `.onChange(of: username)` / `.onChange(of: password)` so a stale
    /// "Incorrect username or password" banner disappears the moment the
    /// user starts correcting their input.
    func test_clearErrorOnEdit_resetsErrorMessageToNil() {
        let vm = LoginViewModel()
        vm.errorMessage = "Incorrect username or password. Please try again."

        vm.clearErrorOnEdit()

        XCTAssertNil(vm.errorMessage,
                     "clearErrorOnEdit must reset errorMessage to nil")
    }

    /// Calling `clearErrorOnEdit` when no error is shown is a safe no-op.
    /// `.onChange(of: username)` fires on every keystroke, so this method
    /// must be cheap and idempotent.
    func test_clearErrorOnEdit_isNoOpWhenErrorMessageAlreadyNil() {
        let vm = LoginViewModel()
        XCTAssertNil(vm.errorMessage)

        vm.clearErrorOnEdit()

        XCTAssertNil(vm.errorMessage,
                     "clearErrorOnEdit must leave a nil errorMessage as nil")
    }

    /// Repeated invocations must remain idempotent — verifies the second
    /// call doesn't somehow re-populate or trip an assertion.
    func test_clearErrorOnEdit_isIdempotent() {
        let vm = LoginViewModel()
        vm.errorMessage = "Some error"

        vm.clearErrorOnEdit()
        vm.clearErrorOnEdit()
        vm.clearErrorOnEdit()

        XCTAssertNil(vm.errorMessage,
                     "Repeated clearErrorOnEdit calls must leave errorMessage nil")
    }

    /// `clearErrorOnEdit` only touches `errorMessage` — it must not reset
    /// the user's typed credentials, the password-visibility toggle, or
    /// the keep-signed-in preference.
    func test_clearErrorOnEdit_doesNotMutateOtherState() {
        let vm = LoginViewModel()
        vm.username = "alice@acmebank.com"
        vm.password = "p@ssw0rd"
        vm.keepSignedIn = true
        vm.isPasswordVisible = true
        vm.errorMessage = "Incorrect username or password."

        vm.clearErrorOnEdit()

        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.username, "alice@acmebank.com",
                       "username must not be cleared by clearErrorOnEdit")
        XCTAssertEqual(vm.password, "p@ssw0rd",
                       "password must not be cleared by clearErrorOnEdit")
        XCTAssertTrue(vm.keepSignedIn,
                      "keepSignedIn must not be flipped by clearErrorOnEdit")
        XCTAssertTrue(vm.isPasswordVisible,
                      "isPasswordVisible must not be flipped by clearErrorOnEdit")
    }
}
