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
}
