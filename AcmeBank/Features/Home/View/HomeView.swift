import SwiftUI

/// The post-login Home dashboard screen.
///
/// Composes the row / card components under `View/Components/` with a
/// `HomeViewModel` state machine, following the design spec's strict
/// monochrome palette (no red/green amounts, no coloured shield, no
/// per-type icon tint — sign is communicated by U+2212, never colour).
///
/// ## Layout
///
/// ```
/// ┌─────────────────────────────────────┐
/// │ [A] Acme Bank                       │  BrandBar
/// │                                     │
/// │ Welcome back,                       │  Greeting
/// │ <FirstName>                         │
/// │                                     │
/// │ ┌─────────────────────────────────┐ │  SignedInCard
/// │ │ SIGNED IN                       │ │  (navy)
/// │ │ [BU] Bank User                  │ │
/// │ │       +1 555 010 0100           │ │
/// │ │ 🛡 Authenticated via Okta · CID │ │
/// │ └─────────────────────────────────┘ │
/// │                                     │
/// │ Accounts                            │
/// │ ┌─ AccountRow ────────────────────┐ │
/// │ │ ...                             │ │
/// │ └─────────────────────────────────┘ │
/// │                                     │
/// │ Recent transactions                 │
/// │ ┌─ TransactionRow ────────────────┐ │
/// │ │ ...                             │ │
/// │ └─────────────────────────────────┘ │
/// │                                     │
/// ├─────────────────────────────────────┤  .safeAreaInset(.bottom)
/// │           [  Log out  ]             │  LogOutButton
/// └─────────────────────────────────────┘
/// ```
///
/// The `ScrollView` scrolls the greeting / cards / lists; the
/// `LogOutButton` is pinned via `.safeAreaInset(edge: .bottom)` so it
/// stays visible regardless of scroll position (per AC — "Log out
/// button is pinned at the bottom").
///
/// ## Accessibility-identifier ordering pitfall (READ BEFORE EDITING)
///
/// SwiftUI propagates a container-level `.accessibilityIdentifier`
/// onto the top-level accessibility elements the view resolves to,
/// including content placed inside `.safeAreaInset` / `.overlay` /
/// `.toolbar`. If a screen-root `.accessibilityIdentifier("home.root")`
/// is applied AFTER `.safeAreaInset { LogOutButton(...) }` (or as the
/// outermost modifier of `body`), it silently overwrites the child
/// `home.logOut` identifier and the UI test's `app.buttons["home.logOut"]`
/// query stops matching — the button is still tappable but XCUITest
/// can't find it.
///
/// This bit us in a prior CI run of `HomeLogOutUITests`. The safe
/// pattern used here: DO NOT attach a container-level identifier at
/// the root of `body`. The interactive elements (`LogOutButton`, the
/// Retry button, etc.) carry their own stable identifiers and that is
/// what the tests query.
///
/// ## Session-expired routing
///
/// The view knows nothing about sign-out. `HomeViewModel.onSessionExpired`
/// (wired at composition time by `ContentView`) funnels 401s through
/// the same `SessionStore.signOut()` the Log out button uses, so both
/// paths converge on a single routing target.
struct HomeView: View {

    @ObservedObject var viewModel: HomeViewModel

    /// Invoked when the user taps the pinned Log out button. Wired by
    /// `ContentView` to `sessionStore.signOut()`.
    let onSignOut: () -> Void

    init(viewModel: HomeViewModel, onSignOut: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onSignOut = onSignOut
    }

    var body: some View {
        content
            .background(AcmeColors.background.ignoresSafeArea())
            .task {
                // Kick off the first load exactly once per view
                // identity. `.task` cancels automatically when the
                // view disappears, so a signOut mid-fetch aborts the
                // URLSession task cleanly (mapped to
                // `CancellationError` by `BFFHomeRepository` and
                // swallowed silently in the VM).
                await viewModel.load()
            }
            .safeAreaInset(edge: .bottom) {
                // The LogOutButton carries its own
                // `.accessibilityIdentifier("home.logOut")`. Do NOT
                // wrap this inset in a container that also sets an
                // accessibilityIdentifier — see the type-doc note on
                // the safe-area / identifier clobbering trap.
                LogOutButton(onSignOut: onSignOut)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(AcmeColors.background)
            }
    }

    // MARK: - State switching

    /// Root content, one branch per `HomeViewState` case. Extracted so
    /// the outer `.background` / `.task` / `.safeAreaInset` modifier
    /// chain stays legible.
    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            loadingView
        case .error(let message):
            errorView(message: message)
        case .loaded(let dashboard):
            loadedView(dashboard: dashboard)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandBar()
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .accessibilityIdentifier("home.loading")
            }
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BrandBar()
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 12) {
                    Text(message)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AcmeColors.text)
                        .accessibilityIdentifier("home.error.message")

                    Button {
                        Task { await viewModel.retry() }
                    } label: {
                        Text("Retry")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AcmeColors.onNavy)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AcmeColors.navy900)
                            )
                    }
                    .accessibilityIdentifier("home.error.retry")
                }
                .padding(.horizontal, 20)
                .padding(.top, 40)
            }
        }
    }

    // MARK: - Loaded

    private func loadedView(dashboard: HomeDashboard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandBar()
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                greeting(firstName: dashboard.customer.firstName)
                    .padding(.horizontal, 20)

                SignedInCard(
                    fullName: fullName(from: dashboard.customer),
                    phoneNumber: dashboard.customer.phoneNumber,
                    customerId: dashboard.customer.id
                )
                .padding(.horizontal, 20)

                accountsSection(dashboard: dashboard)
                transactionsSection(dashboard: dashboard)

                // Bottom padding so the last row isn't hugging the
                // pinned Log out button.
                Spacer(minLength: 12)
            }
        }
    }

    private func greeting(firstName: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Welcome back,")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AcmeColors.subtext)
                .accessibilityIdentifier("home.greeting.prefix")
            Text(firstName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AcmeColors.text)
                .accessibilityIdentifier("home.greeting.firstName")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountsSection(dashboard: HomeDashboard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Accounts", identifier: "home.section.accounts")
                .padding(.horizontal, 20)

            VStack(spacing: 10) {
                ForEach(dashboard.accounts, id: \.id) { account in
                    AccountRow(account: account)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func transactionsSection(dashboard: HomeDashboard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Recent transactions", identifier: "home.section.transactions")
                .padding(.horizontal, 20)

            if dashboard.recentTransactions.isEmpty {
                emptyTransactionsView
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dashboard.recentTransactions.enumerated()), id: \.element.id) { index, txn in
                        TransactionRow(
                            transaction: txn,
                            currencyCode: currencyCode(for: txn, in: dashboard)
                        )
                        if index < dashboard.recentTransactions.count - 1 {
                            Divider()
                                .overlay(AcmeColors.divider)
                                .padding(.leading, 66)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AcmeColors.surface)
                )
                .padding(.horizontal, 20)
            }
        }
    }

    private var emptyTransactionsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No recent activity")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AcmeColors.text)
            Text("Transactions will appear here once posted.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AcmeColors.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AcmeColors.surface)
        )
        .accessibilityIdentifier("home.transactions.empty")
    }

    private func sectionHeader(_ title: String, identifier: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(AcmeColors.subtext)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(identifier)
    }

    // MARK: - Helpers

    private func fullName(from customer: Customer) -> String {
        let joined = [customer.firstName, customer.lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? customer.email : joined
    }

    /// Best-effort resolution of a transaction's currency code by
    /// looking up its owning account. Falls back to "USD" if the
    /// account isn't in the dashboard (shouldn't happen — the BFF's
    /// contract is that `recent_transactions[*].account_id` always
    /// refers to a returned account — but we don't crash on wire
    /// weirdness).
    private func currencyCode(for transaction: Transaction, in dashboard: HomeDashboard) -> String {
        return dashboard.accounts.first(where: { $0.id == transaction.accountId })?.currencyCode
            ?? "USD"
    }
}

// MARK: - Previews

#Preview("Loaded — bankuser.one") {
    HomeView(
        viewModel: HomeViewModel(
            session: UserSession(
                userId: "preview-sub",
                displayName: "Bank User",
                email: "bankuser.one@example.com",
                accessToken: "preview-access",
                authTimestamp: Date(),
                deviceName: "Preview"
            ),
            repository: StubHomeRepository(),
            onSessionExpired: {}
        ),
        onSignOut: {}
    )
}

#Preview("Error") {
    HomeView(
        viewModel: HomeViewModel(
            session: UserSession(
                userId: "preview-sub",
                displayName: "Bank User",
                email: "bankuser.one@example.com",
                accessToken: "preview-access",
                authTimestamp: Date(),
                deviceName: "Preview"
            ),
            repository: StubHomeRepository(behaviour: .failure(.network)),
            onSessionExpired: {}
        ),
        onSignOut: {}
    )
}
