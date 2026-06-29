import Foundation

/// The view-state machine for the Home screen.
///
/// `HomeView` observes a single `@Published var state: HomeViewState`
/// on `HomeViewModel` and renders exactly one branch per case — there
/// is no separate `isLoading` / `errorMessage` / `dashboard` triple of
/// flags that could disagree with each other (e.g. "loading AND showing
/// stale data AND an error banner"). All UI permutations are encoded
/// as states here.
///
/// ### Cases
/// - `.idle` — the screen has been instantiated but `load()` has not
///   yet been invoked. The initial state on construction. In practice
///   the view fires `.task { await vm.load() }` on first appearance, so
///   users only ever see `.idle` for the single render before the task
///   schedules.
/// - `.loading` — a fetch is in flight. The view renders a spinner /
///   skeleton; the Retry button is disabled (no concurrent retries).
/// - `.loaded(HomeDashboard)` — the BFF returned a decoded payload.
///   The associated value is the only data the view binds to; there is
///   no separate "last successful response" cache.
/// - `.error(String)` — a non-401 failure (network, 5xx, decoding,
///   missing config). The associated value is the user-facing message
///   the view shows on the error banner. 401 is NOT modelled here:
///   `HomeViewModel` invokes `onSessionExpired()` on 401 and never
///   surfaces it as an in-screen error, because there is no useful
///   recovery the user can perform on the Home screen for an expired
///   session — they must re-authenticate.
///
/// ### Contract-conformance decision record (re: `.loaded(HomeDashboard)`)
///
/// The `HomeDashboard` carried by `.loaded` is the hand-written
/// `AcmeBank/Features/Home/Model/HomeDashboard.swift`, NOT the
/// generated `Generated/acmebank-bff-home-v1/...HomeDashboard.swift`.
/// This is a deliberate, project-wide accepted deviation from the
/// usual "consumer code imports the generated DTO" rule, recorded
/// here so it isn't changed silently later:
///
///   * **Why hand-rolled.** The generated `AccountDto` uses `Double`
///     for `balance` / `available_balance` (loses cent precision on
///     subtraction) and `String?` for account `type` (no exhaustive
///     `switch`, unknown values sail through). The hand-rolled model
///     uses `Decimal` for money and an unknown-tolerant
///     `AccountType` enum. See the long comment at the top of
///     `HomeDashboard.swift` for the full rationale.
///
///   * **How drift is gated.** The codegen boundary cannot catch a
///     shadow type, so the conformance gate is
///     `HomeDashboardDecodingTests` (in
///     `AcmeBankTests/Features/Home/`). Those tests assert every
///     wire field by name against the `bankuser.one` fixture; a
///     rename on the contract side flips the relevant test red
///     before the app ships. Treat that test file as the gate, not
///     a secondary check.
///
///   * **What this means for reviewers.** When the
///     `acmebank-bff-home-v1` contract changes, the lockstep update
///     is THREE files: the contract, `HomeDashboard.swift`, and
///     `HomeDashboardDecodingTests`. A PR that touches only two of
///     the three is incomplete. Conversely, do NOT replace the
///     hand-written `HomeDashboard` with the generated DTO without
///     re-opening the precision / exhaustive-enum trade-offs above.
public enum HomeViewState: Equatable {
    case idle
    case loading
    case loaded(HomeDashboard)
    case error(String)
}
