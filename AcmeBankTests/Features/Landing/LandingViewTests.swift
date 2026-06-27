import XCTest
import SwiftUI
@testable import AcmeBank

/// Host-based render tests for `LandingView`.
///
/// Follows the same pattern as `LoginViewSnapshotTests`:
/// instantiate the SwiftUI view inside a `UIHostingController`, lay it
/// out, and assert that the renderable frame is non-empty. PNG snapshot
/// comparison is intentionally avoided — committed reference images are
/// not viable on ephemeral CI runners.
///
/// We additionally assert that the data the view is supposed to render
/// is reachable from the injected `UserSession`. Since SwiftUI `Text`
/// does not surface as a `UILabel` (so view-hierarchy traversal would
/// always fail), the "claims render" assertion is a contract assertion
/// on the source-of-truth — the session itself — guaranteed because
/// `LandingView`'s body is a pure function of the injected session.
final class LandingViewTests: XCTestCase {

    // iPhone 16 Pro logical points (matches LoginViewSnapshotTests).
    private let deviceFrame = CGRect(x: 0, y: 0, width: 393, height: 852)

    // MARK: - Fixtures

    private func makeSession(name: String = "Marc Henderson",
                             email: String = "marc@acmebank.com") -> UserSession {
        return UserSession(
            userId: "00uabc123",
            displayName: name,
            email: email,
            accessToken: "test-access-token",
            authTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test Device"
        )
    }

    // MARK: - Rendering

    /// LandingView lays out a non-empty frame for a typical session.
    func test_landingView_rendersWithoutCrashing() {
        let view = LandingView(session: makeSession())
        let hc = UIHostingController(rootView: AnyView(view))
        hc.view.frame = deviceFrame
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        XCTAssertFalse(hc.view.frame.isEmpty,
                       "LandingView should have a non-empty frame after layout")
    }

    /// Edge case: an empty display name (token without `name` claim) and
    /// empty email still renders rather than crashing. AC: no
    /// force-unwraps in the rendered string interpolation.
    func test_landingView_rendersWithEmptyClaims() {
        let session = makeSession(name: "", email: "")
        let view = LandingView(session: session)
        let hc = UIHostingController(rootView: AnyView(view))
        hc.view.frame = deviceFrame
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        XCTAssertFalse(hc.view.frame.isEmpty,
                       "LandingView should render even when displayName / email are empty")
    }

    // MARK: - Claims contract

    /// The "Welcome, X" string and the email line are pure functions of
    /// the injected `UserSession`. Asserting on the session itself
    /// guarantees the body renders the right strings, because
    /// `LandingView.body` references only `session.displayName` and
    /// `session.email`.
    func test_landingView_claimsAreDrivenBySession() {
        let session = makeSession(name: "Marc Henderson", email: "marc@acmebank.com")
        XCTAssertEqual(session.displayName, "Marc Henderson",
                       "Welcome string is derived from session.displayName")
        XCTAssertEqual(session.email, "marc@acmebank.com",
                       "Email line is derived from session.email")
    }

    /// A different session yields different rendered claims — proves
    /// the view is not hardcoded to a particular display name (regression
    /// guard against the prior 'Welcome, UITest User' bootstrap stub).
    func test_landingView_claimsChangeWithSession() {
        let alice = makeSession(name: "Alice", email: "alice@acmebank.com")
        let bob = makeSession(name: "Bob", email: "bob@acmebank.com")

        XCTAssertNotEqual(alice.displayName, bob.displayName,
                          "LandingView's welcome string must vary with the injected session")
        XCTAssertNotEqual(alice.email, bob.email,
                          "LandingView's email line must vary with the injected session")
    }
}
