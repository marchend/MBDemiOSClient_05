import SwiftUI

/// Post-authentication landing screen.
///
/// This view is the FIRST thing the user sees after a successful Okta
/// sign-in. It is intentionally minimal: a welcome line and the user's
/// email, both driven entirely from the injected `UserSession`. Nothing
/// here is hardcoded — the "Welcome, X" string MUST be derived from the
/// real ID-token claims so a misconfigured composition root (e.g. a
/// placeholder session left in `ContentView`) is visible to QA, not
/// silently masked.
///
/// Styling is deliberately monochrome per the project's design system
/// (see AGENT.md §"Design System"): no semantic colours, no per-brand
/// tints. The dark-navy accent is reserved for the hex logo + Sign In
/// button on the Login screen.
///
/// Accessibility identifiers `landing.welcome` / `landing.email` are
/// the stable XCUITest locators for `LandingUITests`.
struct LandingView: View {

    /// The signed-in user's session, captured at sign-in time and
    /// handed to this view by `AppCoordinator.didSignIn(_:)`.
    let session: UserSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome, \(session.displayName)")
                .font(.title)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("landing.welcome")

            Text(session.email)
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("landing.email")

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color(.systemBackground))
    }
}

#Preview("Landing — typical session") {
    LandingView(
        session: UserSession(
            userId: "00uabc123",
            displayName: "Marc Henderson",
            email: "marc@acmebank.com",
            accessToken: "preview-access-token",
            authTimestamp: Date(),
            deviceName: "Preview Device"
        )
    )
}
