import XCTest

/// End-to-end UI test of the Login → Landing happy path.
///
/// This test is GUARDED by an `XCTSkipUnless` on the presence of real
/// Okta credentials in the test process environment. Without them, the
/// app launches into the "Okta is not configured" Login state and there
/// is no way to reach the Landing screen — the test would be vacuously
/// red. CI without secrets sees this as a green skip.
///
/// The env-var contract:
///   - `OKTA_E2E_CONFIGURED=YES` — proves the build was made with real
///     OKTA_* env vars injected into the Info.plist (so the runtime
///     `OktaConfig.load()` returns `.configured`). This is the same
///     gate used by `LoginUITests.test_signIn_endToEnd_withRealOkta`.
///   - `OKTA_TEST_USERNAME` / `OKTA_TEST_PASSWORD` — credentials to
///     type into the Login screen.
///   - `OKTA_TEST_DISPLAY_NAME` — the expected display name from the
///     ID token's `name` claim, used to assert the Landing welcome line.
///     Optional: if absent, we only assert the welcome label is present
///     and non-empty.
///
/// This file intentionally does NOT `import AcmeBank`. See the
/// `LoginUITests` header comment for why: UI-test bundles
/// (`bundle.ui-testing`) are hosted in a separate runner app and are
/// not `-bundle_loader`-linked against the host module, so any
/// `OktaConfig.load()` reference compiles but fails to link. The
/// `OKTA_E2E_CONFIGURED` env-var gate is the UI-test-safe equivalent.
final class LandingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Forward credential env vars from the runner process into the
        // app under test so the test can read them back in the same
        // shape it set them.
        let env = ProcessInfo.processInfo.environment
        for key in ["OKTA_E2E_CONFIGURED", "OKTA_TEST_USERNAME", "OKTA_TEST_PASSWORD", "OKTA_TEST_DISPLAY_NAME"] {
            if let value = env[key] {
                app.launchEnvironment[key] = value
            }
        }
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Happy-path end-to-end:
    ///   1. Launch the app with real Okta config injected at build time.
    ///   2. Type the configured credentials.
    ///   3. Tap Sign In.
    ///   4. Assert the Landing welcome line appears, and (if the
    ///      expected display name was provided) that it contains that
    ///      name.
    ///
    /// Skipped unless `OKTA_E2E_CONFIGURED=YES` AND both credentials
    /// are set, so CI without secrets is green.
    func test_signIn_navigatesToLanding_withRealOkta() throws {
        let env = ProcessInfo.processInfo.environment
        let configured = env["OKTA_E2E_CONFIGURED"] == "YES"
        let username = env["OKTA_TEST_USERNAME"]
        let password = env["OKTA_TEST_PASSWORD"]

        try XCTSkipUnless(
            configured && username?.isEmpty == false && password?.isEmpty == false,
            "Okta e2e env vars not set (need OKTA_E2E_CONFIGURED=YES, OKTA_TEST_USERNAME, OKTA_TEST_PASSWORD)"
        )

        guard let username = username, let password = password else {
            XCTFail("Unreachable: XCTSkipUnless guarantees both are non-empty")
            return
        }

        // 1. Enter credentials.
        let usernameField = app.textFields["usernameField"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5),
                      "Username field should exist on Login")
        usernameField.tap()
        usernameField.typeText(username)

        let passwordField = app.secureTextFields["passwordField"]
        XCTAssertTrue(passwordField.exists,
                      "Password field should exist on Login")
        passwordField.tap()
        passwordField.typeText(password)

        // 2. Tap Sign In.
        let signInButton = app.buttons["signInButton"]
        XCTAssertTrue(signInButton.isEnabled,
                      "Sign In button should be enabled once both fields are filled")
        signInButton.tap()

        // 3. Wait for the Landing welcome label. Generous timeout: real
        //    Okta round-trip + Keychain write can take several seconds
        //    on a cold simulator.
        let welcomeLabel = app.staticTexts["landing.welcome"]
        XCTAssertTrue(welcomeLabel.waitForExistence(timeout: 15),
                      "Landing welcome label should appear after a successful sign-in")

        // 4. If the expected display name was supplied, assert the
        //    label contains it. The welcome string is "Welcome, <name>"
        //    so a `contains` check is robust to small copy changes.
        if let expectedName = env["OKTA_TEST_DISPLAY_NAME"], !expectedName.isEmpty {
            let labelValue = welcomeLabel.label
            XCTAssertTrue(
                labelValue.contains(expectedName),
                "Landing welcome label \"\(labelValue)\" should contain the configured display name \"\(expectedName)\""
            )
        } else {
            // No expected name supplied: assert the label is non-empty
            // (i.e. the ID token actually carried a `name` claim that
            // the view rendered into the Welcome string).
            XCTAssertFalse(welcomeLabel.label.isEmpty,
                           "Landing welcome label must render the user's display name from the ID token")
        }

        // 5. Bonus: the email line should also be present.
        let emailLabel = app.staticTexts["landing.email"]
        XCTAssertTrue(emailLabel.exists,
                      "Landing email label should appear after sign-in")
    }
}
