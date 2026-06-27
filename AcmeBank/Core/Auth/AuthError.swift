import Foundation

/// Typed errors thrown by `AuthServicing.signIn`.
///
/// This enum is the ONLY error type a caller's `catch let e as AuthError`
/// block needs to handle. The implementation maps every failure mode of
/// the underlying SDK + post-success plumbing into one of these cases,
/// so the UI never has to fall through to a generic `catch` that displays
/// a misleading network-error banner.
///
/// Copy strings (`userMessage`) are user-facing and intentionally use a
/// LITERAL em-dash character (—). Do NOT switch back to `\u{2014}`
/// escapes — both render identically but the literal is what the AC7
/// design copy specifies, and a `\uXXXX` (unbraced) escape is a hard
/// Swift compile error.
public enum AuthError: Error, Equatable {
    /// Username or password rejected by Okta. SDK mapping: `invalid_grant`.
    case invalidCredentials

    /// Transport-layer failure (offline, DNS, TLS, timeout, etc.).
    /// SDK mapping: `URLError`.
    case network

    /// Okta returned an MFA challenge. Not handled by this flow; the user
    /// must use the web sign-in path. SDK mapping: a non-success
    /// `DirectAuthenticationFlow.Status` (e.g. `mfaRequired`).
    case mfaRequired

    /// Build-time Okta configuration is missing or invalid. Carries a
    /// human-readable diagnostic (e.g. "missing OKTA_CLIENT_ID").
    case notConfigured(String)

    /// The Okta SDK returned success but the response was unparseable
    /// (e.g. an ID token that isn't a well-formed JWT, or missing claims).
    /// Carries a short reason for logging / diagnostics.
    ///
    /// Distinct from `.network` so the UI can show "Sign-in succeeded but
    /// the server response was unreadable" rather than the misleading
    /// "couldn't reach Okta" copy.
    case invalidServerResponse(String)

    /// User-facing copy for each case. AC7 specifies the exact strings.
    public var userMessage: String {
        switch self {
        case .invalidCredentials:
            return "We couldn't sign you in — check your username and password and try again."
        case .network:
            return "Couldn't reach Okta — check your connection and try again."
        case .mfaRequired:
            return "Extra verification is required — please sign in on the web first."
        case .notConfigured(let reason):
            return "Sign-in isn't configured — \(reason)."
        case .invalidServerResponse(let reason):
            return "Sign-in succeeded but the server response was unreadable — \(reason)."
        }
    }
}
