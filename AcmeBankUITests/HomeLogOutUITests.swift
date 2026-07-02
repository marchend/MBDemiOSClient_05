import XCTest

/// End-to-end XCUITest for the Home → Log out → Login → re-sign-in
/// flow required by MBE2EDEM05-36.
///
/// ## Stub seam
///
/// This test launches the app with `UITEST_STUB_HOME=1` in the process
/// arguments. That is the ONLY entry point that swaps in
/// `UITestStubAuthService` + `StubHomeRepository` (see
/// `AcmeBank/App/UITestStubs.swift`); every non-UI-test launch runs
/// against the real Okta + BFF stack.
///
/// Two fixture users with DIFFERENT account counts:
///   - `bankuser.one` → 4 accounts (Checking, Savings, Credit, Loan)
///   - `demo.user`    → 3 accounts (Checking, Savings, Credit)
///
/// So the "second user renders different data" assertion is a real
/// signal, not a superficial name check.
///
/// ## Accessibility-identifier ordering trap (this is why a prior
/// run of this test failed — read before editing HomeView)
///
/// SwiftUI propagates a container `.accessibilityIdentifier` down
/// onto child accessibility elements. If `HomeView` grew a screen-root
/// `.accessibilityIdentifier("home.root")` applied AFTER
/// `.safeAreaInset { LogOutButton(...) }` (or as the outermost
/// modifier of `body`), it would silently overwrite the
/// `home.logOut` identifier the button sets internally, and the
/// `app.buttons["home.logOut"]` lookup below would stop matching
/// while the button still rendered and was tappable. If this test
/// ever starts failing on the "Log out button should be pinned" line,
/// re-check `HomeView`'s modifier order before assuming the button
/// disappeared.
///
/// ## `SecItem*` caveat
///
/// This UI-test file itself does not touch the Keychain — the stub
/// auth service is stateless. If a future revision does drive
/// Keychain reads/writes from a UI-test hook, every `SecItemAdd` /
/// `SecItemCopyMatching` / `SecItemDelete` / `SecItemUpdate` query
/// dictionary MUST include `kSecUseDataProtectionKeychain: true`
/// exactly as `KeychainStore.baseQuery(for:)` does, or the calls
/// will return `errSecMissingEntitlement` (-34018) on the Simulator
/// unit-test host and the entire suite goes red.
final class HomeLogOutUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // The load-bearing launch argument: `AcmeBankApp` sees this
        // and substitutes the stub auth service + stub home
        // repository factory. Without it the app tries to reach
        // real Okta / the real BFF and the test cannot possibly
        // pass on a hermetic CI runner.
        app.launchArguments += ["UITEST_STUB_HOME=1"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Drive the Login screen's sign-in step with the given username.
    /// The stub auth accepts any password; we pass a non-empty one so
    /// the Sign In button enables.
    private func signIn(username: String, password: String = "any-password") {
        let usernameField = app.textFields["usernameField"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5),
                      "Username field should exist on the Login screen")
        usernameField.tap()
        usernameField.typeText(username)

        let passwordField = app.secureTextFields["passwordField"]
        XCTAssertTrue(passwordField.exists,
                      "Password field should exist on the Login screen")
        passwordField.tap()
        passwordField.typeText(password)

        // Dismiss the keyboard before tapping Sign In — on iPhone 16
        // the button sits under the keyboard once the SecureField is
        // focused, and XCUITest reports "Not hittable" with hit point
        // {-1, -1} otherwise.
        dismissKeyboard()

        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(signInButton.isEnabled,
                      "Sign In button should be enabled once both fields are filled")
        signInButton.tap()
    }

    /// Same keyboard-dismiss trick used by `LoginUITests`. Swipe down
    /// on the ScrollView to trigger `.scrollDismissesKeyboard(.immediately)`,
    /// then wait for `app.keyboards` to report empty.
    private func dismissKeyboard() {
        guard app.keyboards.element.exists else { return }
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeDown()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        }
        let keyboardGone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(
            predicate: keyboardGone,
            object: app.keyboards.element
        )
        _ = XCTWaiter().wait(for: [expectation], timeout: 3.0)
    }

    /// Count `home.account.*` rows visible in the accessibility
    /// hierarchy. Uses `otherElements` (matches `AccountRow`'s combined
    /// element) with a predicate on the identifier prefix.
    private func visibleAccountRowCount() -> Int {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "home.account.")
        let matches = app.descendants(matching: .any).matching(predicate)
        return matches.count
    }

    /// Wait until at least one `home.account.*` row is present, so
    /// assertions on account count aren't racing the initial load.
    @discardableResult
    private func waitForAnyAccountRow(timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "home.account.")
        let anyRow = app.descendants(matching: .any).matching(predicate).firstMatch
        return anyRow.waitForExistence(timeout: timeout)
    }

    // MARK: - Test

    /// The single end-to-end assertion required by the ticket:
    ///
    ///   1. Launch with the stub seam active — cold state, Login screen.
    ///   2. Sign in as `bankuser.one` → Home renders 4 accounts.
    ///   3. Tap the pinned Log out button → Login screen reappears.
    ///   4. Sign in as `demo.user` → Home renders a DIFFERENT set of
    ///      accounts (3 rows, not 4).
    ///
    /// This exercises the full "one routing target for sign-out"
    /// wiring: `LogOutButton.onSignOut` → `sessionStore.signOut()` →
    /// `credentialClear` + `onSignedOut` hooks → `coordinator.route
    /// = .login`. If any link in that chain broke — e.g. the button
    /// lost its `home.logOut` identifier because a container-level
    /// modifier clobbered it — this test would flip red.
    func test_signIn_logOut_reSignIn_rendersEachUsersData() {
        // 1. Cold launch → Login.
        XCTAssertTrue(app.textFields["usernameField"].waitForExistence(timeout: 5),
                      "Cold launch should land on the Login screen")

        // 2. Sign in as bankuser.one.
        signIn(username: "bankuser.one")

        XCTAssertTrue(waitForAnyAccountRow(),
                      "Home should render at least one account row for bankuser.one")
        let firstUserAccountCount = visibleAccountRowCount()
        XCTAssertEqual(firstUserAccountCount, 4,
                       "bankuser.one fixture defines 4 accounts (Checking, Savings, Credit, Loan)")

        // 3. Tap the pinned Log out button.
        let logOutButton = app.buttons["home.logOut"]
        XCTAssertTrue(logOutButton.waitForExistence(timeout: 5),
                      "Log out button should be pinned at the bottom of Home")
        XCTAssertTrue(logOutButton.isHittable,
                      "Log out button should be hittable (not occluded)")
        logOutButton.tap()

        // 4. Login screen reappears.
        XCTAssertTrue(app.textFields["usernameField"].waitForExistence(timeout: 5),
                      "After Log out the Login screen should reappear")

        // 5. Sign in as demo.user.
        signIn(username: "demo.user")

        XCTAssertTrue(waitForAnyAccountRow(),
                      "Home should render at least one account row for demo.user")
        let secondUserAccountCount = visibleAccountRowCount()
        XCTAssertEqual(secondUserAccountCount, 3,
                       "demo.user fixture defines 3 accounts (Checking, Savings, Credit)")
        XCTAssertNotEqual(firstUserAccountCount, secondUserAccountCount,
                          "The two fixture users must render DIFFERENT data — the whole point of the test")
    }
}
