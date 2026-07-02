#if DEBUG
import Foundation

// MARK: - Release-build exclusion
//
// The entire contents of this file are wrapped in `#if DEBUG` so the
// stub auth service and fixture bank are **stripped from Release
// builds**. This is the fix for the review concern that
// `UITestStubAuthService` and `UITestHomeFixtures` were being compiled
// into the App Store binary as dead code.
//
// The seam that reaches this file (`AcmeBankApp.init`'s launch-arg
// branch) is also wrapped in `#if DEBUG`, so a Release build has NO
// reference to any symbol declared below — the linker doesn't see
// them, the binary doesn't ship them, and there is no attack surface
// or size overhead in the store binary.
//
// Xcode / xcodegen sets the `DEBUG` compilation condition
// automatically for the Debug configuration; UI tests run against a
// Debug build of the app target, so the stubs remain available for
// `HomeLogOutUITests`. Anyone flipping the UI tests to run against a
// Release build MUST reintroduce a Debug-configured stub host — see
// the "test-only target" pattern mentioned in the review — because
// this file will no longer compile in Release.

/// UI-test-only auth stub. Never linked into the sign-in code path
/// unless `AcmeBankApp` sees `UITEST_STUB_HOME=1` in the process
/// launch arguments AND the build is Debug.
///
/// `signIn` accepts ANY credentials and returns a fixture
/// `UserSession` keyed by `username` \(see `UITestHomeFixtures`\), so
/// XCUITest can drive the "sign in as user A → Log out → sign in as
/// user B" flow with two distinct sessions and NO Okta round-trip.
///
/// `hasPersistedSession()` always returns `false` so the app cold-
/// launches to the Login screen — the UI test drives the sign-in
/// step explicitly rather than starting from a rehydrated session.
///
/// `signOut()` is a best-effort no-op: the stub keeps no state, so
/// "wiping tokens" is meaningless. It exists only so
/// `SessionStore.signOut()`'s credential-clear hook has something to
/// call.
final class UITestStubAuthService: AuthServicing {

    func signIn(username: String, password: String, keepSignedIn: Bool) async throws -> UserSession {
        return UITestHomeFixtures.session(for: username)
    }

    func hasPersistedSession() -> Bool {
        return false
    }

    func signOut() throws {
        // No-op; the stub is stateless.
    }

    /// The stub is only reachable via the `UITEST_STUB_HOME=1` launch
    /// flag; when active, the Login banner check is irrelevant. Opting
    /// out here removes the need for `ContentView` to type-check
    /// `authService is UITestStubAuthService` (see review feedback on
    /// `ContentView.swift`).
    var suppressesNotConfiguredBanner: Bool { true }
}

/// Fixture bank of `UserSession`s and matching `HomeDashboard` payloads
/// used by the UI-test stub seam. Two distinct users with DIFFERENT
/// account counts so the "second user renders different data" assertion
/// in `HomeLogOutUITests` is genuine.
///
/// - `bankuser.one` → 4 accounts \(the `StubHomeRepository.bankuserOne`
///   fixture: Checking + Savings + Credit + Loan\).
/// - `demo.user` → 3 accounts \(a distinct payload defined below:
///   Checking + Savings + Credit; no Loan\).
///
/// Any other username falls through to `bankuser.one` so a typo in the
/// test does not fail-open silently — but the second-user test uses an
/// exact-match "demo.user" so this only affects future ad-hoc runs.
enum UITestHomeFixtures {

    /// Match a typed username to a fixture session. The comparison is
    /// case-insensitive and ignores leading/trailing whitespace so the
    /// test suite doesn't have to babysit `typeText` quirks.
    static func session(for username: String) -> UserSession {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("demo.user") || normalized.hasPrefix("demo") {
            return UserSession(
                userId: "cust_demo_user",
                displayName: "Demo User",
                email: "demo.user@example.com",
                accessToken: "uitest-token-demo",
                authTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
                deviceName: "UITest"
            )
        }
        return UserSession(
            userId: "cust_bankuser_one",
            displayName: "Bank User",
            email: "bankuser.one@example.com",
            accessToken: "uitest-token-bankuser-one",
            authTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "UITest"
        )
    }

    /// The `HomeDashboard` fixture matching the session. Keyed on
    /// `session.userId` (set by `session(for:)` above) so a typo can
    /// never cross the wires — the two payloads have DIFFERENT account
    /// counts on purpose.
    static func dashboard(for session: UserSession) -> HomeDashboard {
        switch session.userId {
        case "cust_demo_user":
            return demoUser
        default:
            return StubHomeRepository.bankuserOne
        }
    }

    /// Second-user fixture: THREE accounts (Checking, Savings, Credit
    /// — no Loan), which the UI test asserts by counting
    /// `home.account.*` rows.
    static let demoUser: HomeDashboard = HomeDashboard(
        customer: Customer(
            id: "cust_demo_user",
            firstName: "Demo",
            lastName: "User",
            email: "demo.user@example.com",
            phoneNumber: "+1-555-0200"
        ),
        accounts: [
            Account(
                id: "acct_demo_chk",
                name: "Demo Checking",
                maskedNumber: "\u{2022}\u{2022}2222",
                balance: Decimal(string: "812.40")!,
                availableBalance: Decimal(string: "812.40")!,
                type: .checking,
                currencyCode: "USD"
            ),
            Account(
                id: "acct_demo_sav",
                name: "Demo Savings",
                maskedNumber: "\u{2022}\u{2022}3333",
                balance: Decimal(string: "5000.00")!,
                availableBalance: Decimal(string: "5000.00")!,
                type: .savings,
                currencyCode: "USD"
            ),
            Account(
                id: "acct_demo_crd",
                name: "Demo Card",
                maskedNumber: "\u{2022}\u{2022}4444",
                balance: Decimal(string: "-125.00")!,
                availableBalance: Decimal(string: "4875.00")!,
                type: .credit,
                currencyCode: "USD"
            )
        ],
        recentTransactions: [
            Transaction(
                id: "txn_demo_1",
                accountId: "acct_demo_chk",
                description: "COFFEE SHOP",
                amount: Decimal(string: "-4.50")!,
                postedDate: ISO8601DateFormatter().date(from: "2025-03-14T10:00:00Z")!,
                category: "DINING",
                merchantName: "Coffee Shop"
            )
        ]
    )
}
#endif
