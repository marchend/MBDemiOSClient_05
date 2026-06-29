import Foundation

/// Repository seam for the Home dashboard.
///
/// ViewModels depend on this protocol — never on the concrete
/// `BFFHomeRepository` — so previews + tests can inject
/// `StubHomeRepository` and a future offline-cache implementation can
/// slot in without touching call-sites.
public protocol HomeRepositoryProtocol {
    /// Fetch the dashboard for the currently signed-in user. The user
    /// identity is carried by the bearer access token; the path/query
    /// MUST NOT contain a CIF / customerId — the BFF derives the user
    /// from the validated token.
    ///
    /// - Throws: `APIError` for every failure mode the UI needs to
    ///   distinguish (`.unauthorized` → kick to login; `.network` →
    ///   retry banner; `.serverError` → generic "couldn't reach Acme
    ///   Bank"; `.decoding` → "we received an unexpected response").
    func fetchHome() async throws -> HomeDashboard
}

/// Typed errors thrown by the Home (and future) repositories. Lives here
/// for now alongside its first consumer; will graduate to a shared
/// `Core/Networking/APIError.swift` when a second repository lands.
///
/// The cases are deliberately coarse: the UI only needs to distinguish
/// "you need to sign in again", "we couldn't reach the server", "the
/// server itself broke", and "we got a response but couldn't read it".
/// Anything finer-grained is a logging concern, not a UI concern.
public enum APIError: Error, Equatable {
    /// HTTP 401. The access token is missing, expired, or rejected.
    /// The coordinator should drop the session and route to login.
    case unauthorized

    /// HTTP 5xx. The server reached us with an error response.
    case serverError(status: Int)

    /// Transport-layer failure (offline, DNS, TLS, timeout). Distinct
    /// from `.serverError` because the remediation is different
    /// (retry / check connection vs "we're sorry, try again later").
    case network

    /// 2xx response whose body did not decode against the contract.
    /// Carries a short reason for logging / diagnostics.
    case decoding(String)

    /// Build-time configuration is missing (e.g. `API_BASE_URL` was not
    /// wired into the bundle). Surfaces as a "couldn't reach Acme Bank"
    /// banner; engineers see the wrapped reason in the logs.
    case notConfigured(String)
}
