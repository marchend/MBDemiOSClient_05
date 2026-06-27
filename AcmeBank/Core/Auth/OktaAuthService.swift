import Foundation
import OktaDirectAuth

/// Production `AuthServicing` driven by Okta's `DirectAuthenticationFlow`.
///
/// Architecture:
///   - The Okta SDK call is quarantined behind an internal protocol
///     `DirectAuthFlowDriving`. The production driver
///     (`RealDirectAuthFlow`) is the ONLY type that will ever touch
///     `OktaDirectAuth` symbols. Everything else in this file operates
///     on our own typed `FlowOutcome` enum.
///   - Tests inject a `FakeDirectAuthFlow` via the test-only initializer
///     so unit tests never link against a real Okta backend.
///
/// Error mapping is the load-bearing piece: every escape path from
/// `signIn` is an `AuthError`. Keychain writes are best-effort (logged,
/// never rethrown) so a Simulator-only `errSecMissingEntitlement` cannot
/// turn a successful Okta exchange into a misleading "couldn't reach
/// Okta" banner.
public final class OktaAuthService: AuthServicing {

    // MARK: - Driver abstraction

    /// Typed outcome of a single `DirectAuthenticationFlow.start` call,
    /// in OUR vocabulary rather than the SDK's. Lets unit tests script
    /// success / MFA / error without importing `OktaDirectAuth`.
    enum FlowOutcome {
        case success(idToken: String, accessToken: String, refreshToken: String?)
        case mfaRequired
    }

    /// Internal seam between `OktaAuthService` and whatever actually
    /// drives the IdP. Production: `RealDirectAuthFlow` (wraps the SDK).
    /// Tests: `FakeDirectAuthFlow` defined in the test target.
    protocol DirectAuthFlowDriving {
        func start(username: String, password: String) async throws -> FlowOutcome
    }

    // MARK: - Stored properties

    private let keychain: KeychainStoring
    private let loadConfig: () -> OktaConfig
    private let makeFlow: (OktaConfig) throws -> DirectAuthFlowDriving
    private let now: () -> Date
    private let log: (String) -> Void

    // MARK: - Initializers

    /// Production initializer. Uses the real Okta SDK driver and reads
    /// configuration from the main bundle's Info.plist.
    public convenience init(keychain: KeychainStoring = KeychainStore()) {
        self.init(
            keychain: keychain,
            loadConfig: { OktaConfig.load() },
            makeFlow: { config in
                guard case let .configured(issuer, clientId, redirectURI, scopes) = config else {
                    // Unreachable: signIn() checks for .configured before
                    // calling makeFlow. Defensive throw so this is loud
                    // if the contract is ever broken.
                    throw AuthError.notConfigured("internal: makeFlow called with .notConfigured")
                }
                return RealDirectAuthFlow(
                    issuer: issuer,
                    clientId: clientId,
                    redirectURI: redirectURI,
                    scopes: scopes
                )
            },
            now: { Date() },
            log: { message in
                // Print so the message lands in Console.app / xcodebuild
                // output; replace with a real logger when one lands.
                print("[OktaAuthService] \(message)")
            }
        )
    }

    /// Test-only initializer. Allows injecting a `FakeDirectAuthFlow`,
    /// a stub config loader, a fixed clock, and a log-capturing sink.
    init(
        keychain: KeychainStoring,
        loadConfig: @escaping () -> OktaConfig,
        makeFlow: @escaping (OktaConfig) throws -> DirectAuthFlowDriving,
        now: @escaping () -> Date,
        log: @escaping (String) -> Void
    ) {
        self.keychain = keychain
        self.loadConfig = loadConfig
        self.makeFlow = makeFlow
        self.now = now
        self.log = log
    }

    // MARK: - AuthServicing

    public func signIn(
        username: String,
        password: String,
        keepSignedIn: Bool
    ) async throws -> UserSession {
        // 1. Config gate. If the Info.plist sentinels survived (no env
        //    vars set), fail FAST with .notConfigured rather than calling
        //    the SDK with bogus values.
        let config = loadConfig()
        if case let .notConfigured(reason) = config {
            throw AuthError.notConfigured(reason)
        }

        // 2. Drive the IdP. Any error here is mapped to AuthError so the
        //    UI's typed catch sees it.
        let outcome: FlowOutcome
        do {
            let flow = try makeFlow(config)
            outcome = try await flow.start(username: username, password: password)
        } catch let authError as AuthError {
            throw authError
        } catch let urlError as URLError {
            log("network error from SDK: \(urlError)")
            throw AuthError.network
        } catch {
            // Catch-all: map by string match on the SDK's error
            // description so unmodelled SDK errors still surface as a
            // typed AuthError instead of leaking through the UI's
            // generic catch.
            throw Self.mapSDKError(error)
        }

        switch outcome {
        case .mfaRequired:
            throw AuthError.mfaRequired

        case let .success(idToken, accessToken, refreshToken):
            // 3. JWT decode. Failures here are real bugs but MUST become
            //    a typed AuthError, not a network error.
            let session: UserSession
            do {
                session = try UserSession.make(
                    idTokenJWT: idToken,
                    accessToken: accessToken,
                    now: now()
                )
            } catch let decodeError as UserSession.DecodeError {
                throw AuthError.invalidServerResponse(String(describing: decodeError))
            } catch {
                throw AuthError.invalidServerResponse(String(describing: error))
            }

            // 4. Persist tokens to the Keychain. EACH write is wrapped
            //    in its own do/catch so a failure on one (or all) of
            //    them does NOT fail signIn — see the
            //    "post-SDK-success" rule. The session is returned
            //    regardless.
            persistBestEffort(idToken: idToken,
                              accessToken: accessToken,
                              refreshToken: keepSignedIn ? refreshToken : nil)

            return session
        }
    }

    public func hasPersistedSession() -> Bool {
        return (try? keychain.get(.refreshToken)) != nil
    }

    public func signOut() throws {
        // Best-effort exhaustive sign-out: attempt EVERY delete even if
        // an earlier one throws, so a single bad `OSStatus` on
        // `.idToken` cannot leave `.accessToken` and `.refreshToken`
        // behind — which would cause `hasPersistedSession()` (which
        // probes `.refreshToken`) to report a live session after a
        // "failed" sign-out and let the caller silently restore it.
        // We still surface the first error to the caller so the UI can
        // decide whether to retry or surface a banner.
        //
        // Note: `KeychainStore.delete` already treats
        // `errSecItemNotFound` as success, so this loop is idempotent
        // when no tokens are stored.
        var firstError: Error?
        for key in [KeychainStore.KeychainKey.idToken, .accessToken, .refreshToken] {
            do {
                try keychain.delete(key)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError {
            throw firstError
        }
    }

    // MARK: - Internals

    /// Try to persist each token, swallow + log any error. Never throws.
    private func persistBestEffort(
        idToken: String,
        accessToken: String,
        refreshToken: String?
    ) {
        do {
            try keychain.set(idToken, for: .idToken)
        } catch {
            log("keychain write failed for idToken: \(error) — continuing")
        }
        do {
            try keychain.set(accessToken, for: .accessToken)
        } catch {
            log("keychain write failed for accessToken: \(error) — continuing")
        }
        if let refreshToken = refreshToken {
            do {
                try keychain.set(refreshToken, for: .refreshToken)
            } catch {
                log("keychain write failed for refreshToken: \(error) — continuing")
            }
        }
    }

    /// Last-resort error mapping for SDK errors whose concrete Swift
    /// type we don't pattern-match on. The Okta SDK's
    /// `OAuth2Error.server(message:)` etc. surface their `error` code
    /// string ("invalid_grant", "mfa_required", …) in their
    /// description, so a substring match is a reasonable fallback that
    /// keeps the call site decoupled from the SDK's exact type names.
    ///
    /// The narrow heuristics below are intentionally conservative — see
    /// the `urlerror`/`offline` note. Finer-grained `OAuth2Error` /
    /// `DirectAuthenticationFlow.Error` pattern-matching can be layered
    /// on as a follow-up if the SDK ever exposes stable typed cases for
    /// the failure modes we care about.
    static func mapSDKError(_ error: Error) -> AuthError {
        let description = String(describing: error).lowercased()
        if description.contains("invalid_grant") || description.contains("invalidgrant") {
            return .invalidCredentials
        }
        if description.contains("mfa_required") || description.contains("mfarequired") {
            return .mfaRequired
        }
        // Narrow network-ish fallback. `URLError` itself is already
        // caught and mapped one level up in `signIn`, so this arm only
        // exists to catch wrapped `URLError`s that the SDK surfaces via
        // their `NSURLErrorDomain` description (e.g. "nsurlerror …" or
        // "the internet connection appears to be offline").
        //
        // We deliberately do NOT match the bare substring "network"
        // here: it is far too broad — Okta's own policy/server
        // descriptions and any future SDK error case mentioning the
        // word "network" (e.g. "network policy violation") would
        // silently map to `.network` and surface the misleading
        // "Couldn't reach Okta — check your connection" copy.
        if description.contains("nsurlerror")
            || description.contains("urlerror")
            || description.contains("offline") {
            return .network
        }
        return .invalidServerResponse(String(describing: error))
    }
}

// MARK: - Real SDK driver

/// Production `DirectAuthFlowDriving` that wraps Okta's
/// `DirectAuthenticationFlow` from `okta-mobile-swift` 2.x.
///
/// This is the ONLY type in the module that imports or references
/// `OktaDirectAuth` symbols — every other call site operates on the
/// neutral `FlowOutcome` enum so unit tests can script every code path
/// without pulling the SDK's network stack into the test target.
///
/// Concretely, `start(username:password:)`:
///   1. Constructs a `DirectAuthenticationFlow` from the config captured
///      at init time (issuer URL, client id, redirect URI, scopes).
///   2. Awaits `flow.start(username, with: .password(password))` to
///      perform the resource-owner password-credentials exchange.
///   3. Translates the resulting `DirectAuthenticationFlow.Status`:
///        - `.success(token)` → `.success(idToken:accessToken:refreshToken:)`
///          by reading `token.idToken?.rawValue`, `token.accessToken`,
///          and `token.refreshToken`.
///        - any other status (MFA challenge, secondary factor required,
///          continuation, …) → `.mfaRequired`. The caller surfaces this
///          as `AuthError.mfaRequired` so the user is told to complete
///          sign-in on the web.
///
/// Initializer / SDK errors escape as-is and are mapped to `AuthError`
/// by `OktaAuthService.signIn`'s catch ladder (`URLError` →
/// `.network`; string-match `invalid_grant` → `.invalidCredentials`;
/// otherwise → `.invalidServerResponse`).
private final class RealDirectAuthFlow: OktaAuthService.DirectAuthFlowDriving {

    private let issuer: URL
    private let clientId: String
    private let redirectURI: URL
    private let scopes: [String]

    init(issuer: URL, clientId: String, redirectURI: URL, scopes: [String]) {
        self.issuer = issuer
        self.clientId = clientId
        self.redirectURI = redirectURI
        self.scopes = scopes
    }

    func start(username: String, password: String) async throws -> OktaAuthService.FlowOutcome {
        // okta-mobile-swift 2.x: scopes are passed as a single
        // space-separated string, NOT as `[String]`. The redirect URI
        // label is `redirectUri` (lowercase `i`), and the issuer label
        // is `issuerURL`.
        let flow = try DirectAuthenticationFlow(
            issuerURL: issuer,
            clientId: clientId,
            scopes: scopes.joined(separator: " "),
            redirectUri: redirectURI
        )

        let status = try await flow.start(username, with: .password(password))

        switch status {
        case .success(let token):
            // `Token.idToken` is an optional `JWT` whose `.rawValue` is
            // the raw compact-serialization string we need to feed into
            // `UserSession.make`. If the IdP omitted the id_token (no
            // `openid` scope, or a misconfigured app), surface an empty
            // string and let the JWT decoder turn it into
            // `AuthError.invalidServerResponse` upstream — that's a
            // more honest signal than a fake success.
            return .success(
                idToken: token.idToken?.rawValue ?? "",
                accessToken: token.accessToken,
                refreshToken: token.refreshToken
            )

        default:
            // Any non-success status (MFA challenge, secondary factor
            // continuation, …) is collapsed to `.mfaRequired` so the
            // caller can surface the "extra verification required"
            // copy. A future PR can break these out into distinct
            // `FlowOutcome` cases if we ever support in-app MFA.
            return .mfaRequired
        }
    }
}
