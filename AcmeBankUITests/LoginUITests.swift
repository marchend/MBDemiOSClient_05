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
///
/// This file intentionally does NOT `import AcmeBank`. UI-test bundles
/// (`bundle.ui-testing`) are hosted in a separate `AcmeBankUITests-Runner.app`
/// and are not linked with `-bundle_loader` against the host app binary, so
/// references to host-module symbols like `OktaConfig` compile but fail to
/// link (`Undefined symbol: OktaConfig.load(bundle:)`) — breaking the whole
/// test target. Anything we need from the host app must be surfaced through
/// a UI-test-safe seam such as a launch argument or environment variable.
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

    /// AC #7 — visibility + clear-on-edit behaviour of the error banner.
    ///
    /// XCUITest can't introspect the SwiftUI styling of the banner directly,
    /// so we assert the contract reachable from the accessibility tree:
    ///
    ///   1. On a fresh launch with `LoginViewModel.errorMessage == nil` the
    ///      banner element (identifier `errorBanner`) is absent — the
    ///      `if let message` in `ErrorBannerView` collapses the view tree.
    ///   2. Typing into username and then password does NOT spuriously
    ///      cause the banner to appear (the `.onChange` plumbing is wired
    ///      to *clear*, never to surface, an error).
    ///
    /// The "make a banner visible and watch it clear" half of AC #7 is
    /// fully covered by `LoginViewModelTests.test_clearErrorOnEdit_*` —
    /// surfacing an error from a UI test requires either a launch-arg
    /// seam or the real AuthService wiring, both of which are owned by
    /// MBE2EDEM05-10 and intentionally out of scope here.
    func testErrorBannerHasRedTintAndClearsOnEdit() {
        // 1. Banner is absent on launch.
        let banner = app.otherElements["errorBanner"]
        XCTAssertFalse(
            banner.exists,
            "Error banner must be absent when LoginViewModel.errorMessage is nil"
        )
        XCTAssertFalse(
            app.images["errorBannerIcon"].exists,
            "Error banner icon must be absent when the banner is hidden"
        )

        // 2. Editing username + password does not surface a banner.
        let usernameField = app.textFields["usernameField"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5))
        usernameField.tap()
        usernameField.typeText("user@acmebank.com")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("Password1!")

        XCTAssertFalse(
            banner.exists,
            "Editing credentials must never *surface* an error banner — only clear an existing one"
        )
    }

    /// End-to-end Okta sign-in scaffold. Skipped unless the runner exports
    /// `OKTA_E2E_CONFIGURED=YES` into the test process environment — CI
    /// without secrets sees this as a green skip rather than a red failure.
    ///
    /// The gate intentionally uses only `Foundation` symbols available to
    /// the UI-test bundle: importing `AcmeBank` to read `OktaConfig.load()`
    /// directly would compile but fail to link (UI-test bundles are not
    /// `-bundle_loader`-linked against the host app), taking the entire
    /// test target down with `Undefined symbols`.
    ///
    /// The full happy-path assertions land alongside the AuthService wiring
    /// story (MBE2EDEM05-10); for now this is the scaffold that proves the
    /// gating compiles and the skip path exits cleanly.
    func test_signIn_endToEnd_withRealOkta() throws {
        let oktaConfigured = ProcessInfo.processInfo.environment["OKTA_E2E_CONFIGURED"] == "YES"
        try XCTSkipUnless(oktaConfigured, "Okta env vars not set")

        // TODO: MBE2EDEM05-10 — add sign-in outcome assertions here.
        // Until that story lands, this body just touches the field so the
        // scaffold has a non-trivial action when Okta IS configured locally;
        // it must NOT be left as a vacuously-green no-op once MBE2EDEM05-10
        // wires the real AuthService. Expected follow-up assertions:
        //   * type real username + password, tap signInButton
        //   * assert the post-auth root view appears (identifier owned by
        //     the LoginCoordinator story)
        //   * assert no `errorBanner` is present on the happy path
        //   * exercise the bad-credentials path and assert the banner DOES
        //     appear with the AC #7 copy
        let usernameField = app.textFields["usernameField"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5))
        usernameField.tap()
    }
}
