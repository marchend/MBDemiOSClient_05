import Foundation

/// Presentation logic for the Home screen.
///
/// Owns the `HomeViewState` machine and orchestrates the single
/// dependency that produces it — a `HomeRepositoryProtocol`. The view
/// observes `state` and triggers `load()` / `retry()`; it knows nothing
/// about the BFF, errors, or navigation.
///
/// ### Why the class is `@MainActor`
///
/// `state` is `@Published` and is mutated from inside `load()`
/// (`.loading` before the await; `.loaded` / `.error` after). All
/// `@Published` writes must run on the main actor or SwiftUI logs a
/// "Publishing changes from background threads" warning. Marking the
/// whole class `@MainActor` is safe here because there is no
/// `@StateObject HomeViewModel = HomeViewModel()` default-arg pattern
/// at any call site (the init requires three concrete dependencies);
/// the prior `LoginViewModel` rule — *only* annotate async workers,
/// not the class — does not apply.
///
/// ### 401 routing
///
/// On `APIError.unauthorized`, `load()` invokes `onSessionExpired()`
/// and DOES NOT publish `.loaded`. The closure is wired by the root
/// coordinator to the same target the existing session-expired flow
/// already uses (dropping the keychain session and routing to Login),
/// so there is exactly one definition of "session expired" in the app.
/// We intentionally do not set `state = .error("...")` on 401: there
/// is no useful in-screen recovery (the user cannot log themselves
/// back in from the Home screen), and surfacing it as an error would
/// race the route transition.
@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: HomeViewState = .idle

    // MARK: - Dependencies

    /// The signed-in user. Stored so a future header / greeting on the
    /// Home screen can read `session.displayName` without re-plumbing
    /// it through every view. Not used by `load()` itself — the BFF
    /// derives identity from the bearer token, not from a path param.
    let session: UserSession

    private let repository: HomeRepositoryProtocol

    /// Invoked when the BFF returns 401. The root coordinator wires
    /// this to the same target the existing session-expired flow uses
    /// (drop the keychain session, route to Login). Held as a closure
    /// so the ViewModel has zero navigation knowledge.
    private let onSessionExpired: () -> Void

    // MARK: - Init

    init(
        session: UserSession,
        repository: HomeRepositoryProtocol,
        onSessionExpired: @escaping () -> Void
    ) {
        self.session = session
        self.repository = repository
        self.onSessionExpired = onSessionExpired
    }

    // MARK: - Actions

    /// Kick off a fetch. Sets `.loading`, awaits the repository, and
    /// publishes `.loaded` or `.error` — except on 401, where the
    /// expired-session closure fires and state is left non-`.loaded`.
    ///
    /// Safe to call multiple times; each call replaces the in-flight
    /// view-state. The view typically invokes this from `.task {}` on
    /// first appearance and from the Retry button.
    func load() async {
        state = .loading

        do {
            let dashboard = try await repository.fetchHome()
            state = .loaded(dashboard)
        } catch APIError.unauthorized {
            // Hand off to the coordinator's session-expired path.
            // Do NOT mutate state to `.loaded`; we revert to `.idle`
            // so a stale `.loading` spinner doesn't linger on the
            // screen during the route transition to Login.
            state = .idle
            onSessionExpired()
        } catch let apiError as APIError {
            state = .error(Self.userMessage(for: apiError))
        } catch is CancellationError {
            // `BFFHomeRepository` re-throws `URLSession`-cancellation
            // as `CancellationError` (e.g. the user navigated away
            // mid-fetch). That's not a failure to display — leave
            // state alone so we don't flash an error banner the user
            // never asked to see.
            return
        } catch {
            // Defensive: any non-`APIError` `Error` collapses to a
            // generic message. In practice the repository only ever
            // throws `APIError` or `CancellationError`, but the type
            // system can't enforce that across the protocol seam.
            state = .error(Self.genericErrorMessage)
        }
    }

    /// Retry a previously-failed load. Thin wrapper over `load()` —
    /// kept as a distinct method so the view's Retry button can call
    /// it by name and so future telemetry can distinguish "first
    /// attempt" from "user-triggered retry".
    func retry() async {
        await load()
    }

    // MARK: - Error mapping

    /// User-facing copy for each `APIError` the UI distinguishes.
    /// Kept here (vs on `APIError`) so the error type stays a pure
    /// domain enum and copy changes don't ripple through the data
    /// layer's test surface.
    private static func userMessage(for error: APIError) -> String {
        switch error {
        case .unauthorized:
            // Defensive — `load()` handles 401 above without calling
            // this, but if a future code path routes here, fall back
            // to a generic message rather than asserting.
            return genericErrorMessage
        case .network:
            return "We couldn\u{2019}t reach Acme Bank. Check your connection and try again."
        case .serverError:
            return "Acme Bank is having trouble right now. Please try again in a moment."
        case .decoding:
            return "We received an unexpected response from Acme Bank. Please try again."
        case .notConfigured:
            return "We couldn\u{2019}t reach Acme Bank. Please try again later."
        }
    }

    private static let genericErrorMessage =
        "Something went wrong. Please try again."
}
