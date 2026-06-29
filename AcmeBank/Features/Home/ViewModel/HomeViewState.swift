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
public enum HomeViewState: Equatable {
    case idle
    case loading
    case loaded(HomeDashboard)
    case error(String)
}
