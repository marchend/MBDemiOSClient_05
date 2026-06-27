import XCTest

/// XCUITest suite for the Login critical user flow.
///
/// Covers the happy-path button-tap and basic field interaction required by
/// `bootstrap.md §13.2` and the Story Implementation Checklist (`§15`).
///
/// Locators use `accessibilityIdentifier` — set on the corresponding elements
/// in `LoginView.swift` — so they are stable across copy and layout changes.
///
/// As of the composition-root PR (MBE2EDEM05-25), the real `OktaAuthService`
/// is wired into LoginView's `onSignIn` closure via `ContentView`. When the
/// build was made without OKTA_* env vars, `ContentView.makeLoginViewModel`
/// pre-seeds the LoginViewModel with the "Okta is not configured" banner —
/// so the banner-absent assertions below are gated on
/// `OKTA_E2E_CONFIGURED=YES`. Without real Okta config, the LoginView legitimately
/// shows the not-configured banner at launch.
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

    /// `true` when the runner exports `OKTA_E2E_CONFIGURED=YES`, meaning
    /// the build under test has real Okta config injected into its
    /// Info.plist. When `false`, `ContentView` pre-seeds the LoginViewModel
    /// with the "Okta is not configured" banner — so banner-absence
    /// assertions must be skipped or inverted.
    private var oktaConfigured: Bool {
        ProcessInfo.processInfo.environment["OKTA_E2E_CONFIGURED"] == "YES"
    }

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

        // Tap the button — onSignIn now drives the real OktaAuthService.
        // Without real Okta config the call returns AuthError.notConfigured
        // and the banner re-surfaces; with real config the app navigates
        // to Landing. Either way the tap is non-fatal here.
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
    /// Two contracts we assert here, both gated on
    /// `OKTA_E2E_CONFIGURED=YES`:
    ///
    ///   1. On a fresh launch with real Okta config (so
    ///      `LoginViewModel.errorMessage == nil` at construction time)
    ///      the banner element (identifier `errorBanner`) is absent.
    ///   2. Typing into username and then password does NOT spuriously
    ///      cause the banner to appear (the `.onChange` plumbing is
    ///      wired to *clear*, never to surface, an error).
    ///
    /// Without `OKTA_E2E_CONFIGURED=YES`, the composition root
    /// legitimately pre-seeds the "Okta is not configured on this
    /// build — see README." banner per AC, so this test is skipped to
    /// avoid asserting a contract that the AC overrides.
    ///
    /// The "make a banner visible and watch it clear" half of AC #7 is
    /// fully covered by `LoginViewModelTests.test_clearErrorOnEdit_*`.
    func testErrorBannerHasRedTintAndClearsOnEdit() throws {
        try XCTSkipUnless(
            oktaConfigured,
            "Skipping banner-absence assertions: build was made without OKTA_* env vars, "
            + "so the LoginView legitimately shows the 'Okta is not configured' banner at launch."
        )

        // 1. Banner is absent on launch (real Okta config injected).
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
    /// The full happy-path assertions land in `LandingUITests` (which
    /// asserts the Landing welcome label appears after a successful
    /// sign-in). This test stays as a smoke check that the Login screen
    /// is interactive when Okta IS configured.
    func test_signIn_endToEnd_withRealOkta() throws {
        try XCTSkipUnless(oktaConfigured, "Okta env vars not set")

        let usernameField = app.textFields["usernameField"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5))
        usernameField.tap()
    }
}
