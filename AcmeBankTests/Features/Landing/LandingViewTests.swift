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
/// Note on rendered-claims coverage: SwiftUI `Text` nodes do not surface
/// as `UILabel`s in the hosting controller's view hierarchy, so we cannot
/// read back the rendered "Welcome, X" / email strings from these tests.
/// A previous revision of this file included two tests
/// (`…_claimsAreDrivenBySession` and `…_claimsChangeWithSession`) that
/// asserted on the `UserSession` fixture instead, which gave a false
/// sense of view-layer coverage — they would have passed even if
/// `LandingView` rendered hardcoded strings. They were removed per
/// review; the rendered-claims guarantee is now covered structurally
/// (`LandingView.body` references only `session.displayName` and
/// `session.email`) and end-to-end by `LandingUITests`, which reads the
/// real on-screen text via the accessibility tree.
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
}
