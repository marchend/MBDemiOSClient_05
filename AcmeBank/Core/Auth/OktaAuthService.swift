import Foundation
// Import is intentional even though no SDK symbols are referenced in
// this PR: it forces SwiftPM to resolve the `OktaDirectAuth` product
// added in `project.yml` so PR 4 (composition wiring) can land the
// concrete `DirectAuthenticationFlow.start(_:with:)` call without a
// separate dependency-graph change. See the long doc comment on
// `RealDirectAuthFlow` below for why we don't reference SDK symbols yet.
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
    /// TODO(MBE2EDEM05-25 / PR 4): once the composition root lands and
    /// the real SDK symbol surface is pinned, replace this string-match
    /// fallback with real `OAuth2Error` / `DirectAuthenticationFlow.Error`
    /// pattern matching. The narrow heuristics below are intentionally
    /// conservative — see the `urlerror`/`offline` note.
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

// MARK: - Real SDK driver (composition pending — PR 4)

/// Production `DirectAuthFlowDriving` that will wrap Okta's
/// `DirectAuthenticationFlow` once the composition root lands in PR 4
/// (MBE2EDEM05-25). Today this is intentionally a stub.
///
/// WHY THE STUB: this PR's scope is the *typed contract* — `AuthError`,
/// `UserSession`, `KeychainStore`, `AuthServicing` and the `signIn`
/// orchestration / error-mapping flow. The plan explicitly forbids
/// referencing any of these types from the UI in this PR ("composition
/// wiring is PR 4"), so no production caller exercises this driver yet.
/// The fake driver in `OktaAuthServiceTests` covers every code path in
/// `signIn`.
///
/// The okta-mobile-swift 2.x API surface for `DirectAuthenticationFlow`
/// (exact initializer label set, exact `Status` cases, exact `Token`
/// property names) shifted between the 1.x and 2.x branches, and
/// `Package.resolved` is not committed yet on this branch — so the
/// safe move is to defer the SDK symbol lookups to PR 4 where the
/// composition root and a working build with a resolved package graph
/// will validate them in the same PR. Stubbing here lets this PR ship a
/// compiling, fully-tested typed contract; PR 4 replaces the stub body
/// with the real `flow.start(...)` call.
///
/// At runtime today this driver throws `.notConfigured("…")`, which the
/// caller turns into a typed `AuthError` — the UI would receive a
/// clean, actionable message even if it WERE wired up (it isn't),
/// never a crash and never a misleading network error.
private final class RealDirectAuthFlow: OktaAuthService.DirectAuthFlowDriving {

    init(issuer: URL, clientId: String, redirectURI: URL, scopes: [String]) {
        // No-op: stored config is unused until PR 4 lands the real
        // SDK call. Listed in the signature so the production
        // initializer's `makeFlow` closure already passes everything
        // the SDK will need.
        _ = (issuer, clientId, redirectURI, scopes)
    }

    func start(username: String, password: String) async throws -> OktaAuthService.FlowOutcome {
        _ = (username, password)
        throw AuthError.notConfigured("Okta SDK driver wiring lands in PR 4 (MBE2EDEM05-25)")
    }
}
