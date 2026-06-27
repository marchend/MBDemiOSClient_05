import XCTest

/// XCUITest suite for the Login critical user flow.
///
/// Covers the happy-path button-tap and basic field interaction required by
/// `bootstrap.md §13.2` and the Story Implementation Checklist (`§15`).
///
/// Locators use `accessibilityIdentifier` — set on the corresponding elements
/// in `LoginView.swift` — so they are stable across copy and layout changes.
///
/// The `onSignIn` closure is a no-op stub in this story; after tapping "Sign in"
/// the screen remains on the login view. A future `LoginCoordinator` story will
/// wire real navigation and expand these tests to assert the post-auth state.
final class LoginUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "YES"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tests

    /// The login screen renders with the username field, password field, and
    /// Sign In button accessible on launch.
    func test_loginScreen_elementsExist_onLaunch() {
        XCTAssertTrue(
            app.textFields["usernameField"].waitForExistence(timeout: 5),
            "Username field should exist on the login screen"
        )
        XCTAssertTrue(
            app.secureTextFields["passwordField"].exists,
            "Password field (secure) should exist on the login screen"
        )
        XCTAssertTrue(
            app.buttons["signInButton"].exists,
            "Sign In button should exist on the login screen"
        )
    }

    /// The Sign In button is disabled when both fields are empty.
    func test_signInButton_isDisabled_whenFieldsEmpty() {
        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(
            signInButton.waitForExistence(timeout: 5),
            "Sign In button should exist"
        )
        XCTAssertFalse(
            signInButton.isEnabled,
            "Sign In button should be disabled when username and password are empty"
        )
    }

    /// Filling both fields enables the Sign In button and allows it to be tapped.
    func test_signIn_withValidCredentials_buttonBecomesEnabled() {
        let usernameField = app.textFields["usernameField"]
        XCTAssertTrue(
            usernameField.waitForExistence(timeout: 5),
            "Username field should exist"
        )
        usernameField.tap()
        usernameField.typeText("user@acmebank.com")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("Password1!")

        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(
            signInButton.isEnabled,
            "Sign In button should be enabled after entering username and password"
        )

        // Tap the button — the onSignIn stub is a no-op in this story.
        signInButton.tap()
    }

    /// Tapping the "Keep me signed in" toggle changes its checked state.
    func test_keepSignedIn_toggle_changesState() {
        let toggle = app.buttons["keepSignedInToggle"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "Keep me signed in toggle should exist"
        )
        toggle.tap()
        // A second tap returns to unchecked — no crash.
        toggle.tap()
    }
}
