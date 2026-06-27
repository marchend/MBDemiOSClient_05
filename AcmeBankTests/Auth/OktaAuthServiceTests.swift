import XCTest
@testable import AcmeBank

/// Unit tests for the `OktaAuthService.signIn` orchestration. Uses the
/// internal `DirectAuthFlowDriving` seam, the injected `loadConfig`
/// closure, and a `KeychainStoring`-conforming fake to script every
/// IdP-response shape (success, MFA, invalid credentials, network,
/// `.notConfigured`) and every Keychain outcome (success, failure)
/// without touching the real Okta SDK or relying on the simulator's
/// keychain to return a specific `OSStatus` under specific conditions.
///
/// These tests own three invariants the rest of the auth stack
/// depends on:
///   1. SDK success → a fully-populated `UserSession` with the IdP
///      tokens persisted to the Keychain.
///   2. SDK failures map to typed `AuthError` cases — no untyped
///      `Error` ever escapes `signIn`.
///   3. A keychain write that throws on the success path does NOT
///      fail `signIn` (the session is returned anyway). This is the
///      "post-SDK-success failures must not propagate" rule.
final class OktaAuthServiceTests: XCTestCase {

    // MARK: - Test doubles

    /// In-process driver; scripts a single outcome per test and records
    /// the credentials it was called with.
    final class FakeDirectAuthFlow: OktaAuthService.DirectAuthFlowDriving {
        enum Scripted {
            case success(idToken: String, accessToken: String, refreshToken: String?)
            case mfaRequired
            case error(Error)
        }
        var scripted: Scripted
        private(set) var startCallCount = 0
        private(set) var lastUsername: String?
        private(set) var lastPassword: String?

        init(_ scripted: Scripted) { self.scripted = scripted }

        func start(username: String, password: String) async throws -> OktaAuthService.FlowOutcome {
            startCallCount += 1
            lastUsername = username
            lastPassword = password
            switch scripted {
            case let .success(idToken, accessToken, refreshToken):
                return .success(idToken: idToken,
                                accessToken: accessToken,
                                refreshToken: refreshToken)
            case .mfaRequired:
                return .mfaRequired
            case .error(let e):
                throw e
            }
        }
    }

    /// In-memory `KeychainStoring` for unit tests. Each call may be
    /// scripted to throw via the `*FailureForAnyKey` switches; otherwise
    /// behaves like a dictionary. Avoids depending on the real Keychain
    /// (which keeps state across tests in the simulator's shared
    /// keychain) and lets us deterministically prove the
    /// "keychain failure on signIn success does not throw" rule.
    final class FakeKeychain: KeychainStoring {
        private(set) var storage: [KeychainStore.KeychainKey: String] = [:]
        var setFailureForAnyKey: Error?
        var getFailureForAnyKey: Error?
        var deleteFailureForAnyKey: Error?
        /// Optional queue of per-call delete errors. If non-empty, each
        /// `delete(_:)` consumes the head and throws it (skipping any
        /// `nil` entries). Lets a test script "first delete throws,
        /// subsequent ones succeed" — exercises the `signOut` exhaustive
        /// iteration rule.
        var deleteFailureQueue: [Error?] = []
        private(set) var setCallCount = 0
        private(set) var deleteCallCount = 0
        private(set) var deletedKeysInOrder: [KeychainStore.KeychainKey] = []

        func set(_ value: String, for key: KeychainStore.KeychainKey) throws {
            setCallCount += 1
            if let error = setFailureForAnyKey { throw error }
            storage[key] = value
        }
        func get(_ key: KeychainStore.KeychainKey) throws -> String? {
            if let error = getFailureForAnyKey { throw error }
            return storage[key]
        }
        func delete(_ key: KeychainStore.KeychainKey) throws {
            deleteCallCount += 1
            deletedKeysInOrder.append(key)
            if !deleteFailureQueue.isEmpty {
                let next = deleteFailureQueue.removeFirst()
                if let error = next { throw error }
            }
            if let error = deleteFailureForAnyKey { throw error }
            storage.removeValue(forKey: key)
        }
    }

    // MARK: - Fixtures

    /// A well-formed JWT with payload {"sub":"u1","name":"User One","email":"u1@example.com"}.
    private let validIDToken: String = {
        let payload = #"{"sub":"u1","name":"User One","email":"u1@example.com"}"#
        let data = payload.data(using: .utf8)!
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(b64).sig"
    }()

    /// A JWT whose middle segment is not valid base64URL — exercises
    /// the `invalidServerResponse` mapping path.
    private let malformedIDToken: String = "header.!!!.sig"

    private let validConfig: OktaConfig = .configured(
        issuer: URL(string: "https://example.okta.com/oauth2/default")!,
        clientId: "abc",
        redirectURI: URL(string: "com.acmebank.mobile://callback")!,
        scopes: ["openid", "profile", "offline_access"]
    )

    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Helpers

    /// Build a service wired to `flow`, with config injected directly
    /// (default = the valid `OktaConfig` fixture above so tests don't
    /// have to repeat themselves).
    private func makeService(
        flow: FakeDirectAuthFlow,
        keychain: KeychainStoring = FakeKeychain(),
        config: OktaConfig? = nil,
        logCapture: ((String) -> Void)? = nil
    ) -> OktaAuthService {
        let cfg = config ?? validConfig
        return OktaAuthService(
            keychain: keychain,
            loadConfig: { cfg },
            makeFlow: { _ in flow },
            now: { self.fixedNow },
            log: logCapture ?? { _ in }
        )
    }

    // MARK: - Configuration gate

    func test_signIn_throwsNotConfigured_whenConfigLoaderReturnsNotConfigured() async {
        let flow = FakeDirectAuthFlow(.success(idToken: validIDToken,
                                               accessToken: "a",
                                               refreshToken: "r"))
        let service = makeService(
            flow: flow,
            config: .notConfigured(reason: "missing OKTA_ISSUER")
        )

        do {
            _ = try await service.signIn(username: "u", password: "p", keepSignedIn: false)
            XCTFail("expected .notConfigured")
        } catch let error as AuthError {
            switch error {
            case .notConfigured(let reason):
                XCTAssertEqual(reason, "missing OKTA_ISSUER")
            default:
                XCTFail("expected .notConfigured, got \(error)")
            }
        } catch {
            XCTFail("expected AuthError, got \(error)")
        }

        XCTAssertEqual(flow.startCallCount, 0,
                       "driver MUST NOT be called when config is missing")
    }

    // MARK: - Success path

    func test_signIn_success_returnsUserSessionWithDecodedClaims() async throws {
        let keychain = FakeKeychain()
        let flow = FakeDirectAuthFlow(.success(
            idToken: validIDToken,
            accessToken: "access-xyz",
            refreshToken: "refresh-xyz"
        ))
        let service = makeService(flow: flow, keychain: keychain)

        let session = try await service.signIn(
            username: "u@example.com",
            password: "p455word",
            keepSignedIn: true
        )

        XCTAssertEqual(session.userId, "u1")
        XCTAssertEqual(session.displayName, "User One")
        XCTAssertEqual(session.email, "u1@example.com")
        XCTAssertEqual(session.accessToken, "access-xyz")
        XCTAssertEqual(session.authTimestamp, fixedNow)
        XCTAssertEqual(flow.lastUsername, "u@example.com")
        XCTAssertEqual(flow.lastPassword, "p455word")
    }

    func test_signIn_success_withKeepSignedIn_persistsAllThreeTokens() async throws {
        let keychain = FakeKeychain()
        let flow = FakeDirectAuthFlow(.success(
            idToken: validIDToken,
            accessToken: "acc",
            refreshToken: "ref"
        ))
        let service = makeService(flow: flow, keychain: keychain)

        _ = try await service.signIn(username: "u", password: "p", keepSignedIn: true)

        XCTAssertEqual(try keychain.get(.idToken), validIDToken)
        XCTAssertEqual(try keychain.get(.accessToken), "acc")
        XCTAssertEqual(try keychain.get(.refreshToken), "ref")
    }

    func test_signIn_success_withoutKeepSignedIn_omitsRefreshToken() async throws {
        let keychain = FakeKeychain()
        let flow = FakeDirectAuthFlow(.success(
            idToken: validIDToken,
            accessToken: "acc",
            refreshToken: "ref"
        ))
        let service = makeService(flow: flow, keychain: keychain)

        _ = try await service.signIn(username: "u", password: "p", keepSignedIn: false)

        XCTAssertEqual(try keychain.get(.idToken), validIDToken)
        XCTAssertEqual(try keychain.get(.accessToken), "acc")
        XCTAssertNil(try keychain.get(.refreshToken),
                     "refresh token MUST NOT be persisted when keepSignedIn is false")
    }

    // MARK: - Error mapping

    func test_signIn_invalidGrantFromSDK_mapsToInvalidCredentials() async {
        struct FakeOAuthError: Error, CustomStringConvertible {
            var description: String { #"OAuth2Error.server(error: "invalid_grant")"# }
        }
        let flow = FakeDirectAuthFlow(.error(FakeOAuthError()))
        let service = makeService(flow: flow)

        await assertSignInThrows(service, equal: .invalidCredentials)
    }

    func test_signIn_urlErrorFromSDK_mapsToNetwork() async {
        let flow = FakeDirectAuthFlow(.error(URLError(.notConnectedToInternet)))
        let service = makeService(flow: flow)

        await assertSignInThrows(service, equal: .network)
    }

    func test_signIn_mfaRequiredOutcome_mapsToMFARequired() async {
        let flow = FakeDirectAuthFlow(.mfaRequired)
        let service = makeService(flow: flow)

        await assertSignInThrows(service, equal: .mfaRequired)
    }

    func test_signIn_unknownSDKError_mapsToInvalidServerResponse() async {
        struct WeirdError: Error, CustomStringConvertible {
            var description: String { "something-unmodelled" }
        }
        let flow = FakeDirectAuthFlow(.error(WeirdError()))
        let service = makeService(flow: flow)

        do {
            _ = try await service.signIn(username: "u", password: "p", keepSignedIn: false)
            XCTFail("expected throw")
        } catch let error as AuthError {
            if case .invalidServerResponse = error { /* ok */ } else {
                XCTFail("expected .invalidServerResponse, got \(error)")
            }
        } catch {
            XCTFail("expected AuthError, got \(error)")
        }
    }

    /// Guard against the previous over-broad `.contains("network")`
    /// arm in `mapSDKError`: a server-side policy rejection whose
    /// description merely contains the substring "network" (e.g. an
    /// Okta "network policy violation" message) must NOT collapse to
    /// `.network` and surface "Couldn't reach Okta — check your
    /// connection". It should fall through to `.invalidServerResponse`
    /// so the UI can show the real server message.
    func test_signIn_policyErrorMentioningNetwork_doesNotMapToNetwork() async {
        struct PolicyError: Error, CustomStringConvertible {
            var description: String { "Server policy rejected sign-in: network policy violation" }
        }
        let flow = FakeDirectAuthFlow(.error(PolicyError()))
        let service = makeService(flow: flow)

        do {
            _ = try await service.signIn(username: "u", password: "p", keepSignedIn: false)
            XCTFail("expected throw")
        } catch let error as AuthError {
            switch error {
            case .network:
                XCTFail("`network` policy text MUST NOT be mapped to AuthError.network")
            case .invalidServerResponse:
                /* expected */ break
            default:
                XCTFail("expected .invalidServerResponse, got \(error)")
            }
        } catch {
            XCTFail("expected AuthError, got \(error)")
        }
    }

    /// Conversely, a wrapped `URLError` whose description surfaces an
    /// `NSURLErrorDomain` code (the shape the SDK actually uses when
    /// it re-wraps connection failures) still maps to `.network`.
    func test_signIn_nsurlErrorDescription_mapsToNetwork() async {
        struct WrappedURLError: Error, CustomStringConvertible {
            var description: String { "SDKError.wrapped(NSURLErrorDomain Code=-1009)" }
        }
        let flow = FakeDirectAuthFlow(.error(WrappedURLError()))
        let service = makeService(flow: flow)

        await assertSignInThrows(service, equal: .network)
    }

    // MARK: - JWT decode failure on success path

    /// SDK reported success, but the returned id-token isn't a valid
    /// JWT. The implementation MUST translate this into a typed
    /// `AuthError.invalidServerResponse(...)` so the UI never sees a
    /// bare `UserSession.DecodeError`. This is the post-SDK-success
    /// "must not collapse to .network" rule.
    func test_signIn_malformedIDToken_mapsToInvalidServerResponse_notNetwork() async {
        let flow = FakeDirectAuthFlow(.success(
            idToken: malformedIDToken,
            accessToken: "acc",
            refreshToken: nil
        ))
        let service = makeService(flow: flow)

        do {
            _ = try await service.signIn(username: "u", password: "p", keepSignedIn: false)
            XCTFail("expected throw")
        } catch let error as AuthError {
            if case .invalidServerResponse = error { /* ok */ } else {
                XCTFail("expected .invalidServerResponse, got \(error)")
            }
        } catch {
            XCTFail("expected AuthError, got \(error)")
        }
    }

    // MARK: - Keychain-write failure on success path

    /// The headline AC for this PR: when Okta returns success but a
    /// keychain write fails, signIn returns the UserSession ANYWAY.
    /// Failure is logged but not rethrown — that's the cache-not-source
    /// rule from the post-SDK-success lesson.
    ///
    /// Uses `FakeKeychain` so the failure is deterministic — does NOT
    /// depend on the simulator returning -34018 under specific
    /// conditions.
    func test_signIn_success_doesNotThrow_whenKeychainSetThrows_forEveryKey() async throws {
        struct ForcedKeychainError: Error, Equatable {
            let message: String
        }
        let keychain = FakeKeychain()
        keychain.setFailureForAnyKey = ForcedKeychainError(message: "forced for test")
        var capturedLogs: [String] = []
        let flow = FakeDirectAuthFlow(.success(
            idToken: validIDToken,
            accessToken: "acc",
            refreshToken: "ref"
        ))
        let service = makeService(
            flow: flow,
            keychain: keychain,
            logCapture: { capturedLogs.append($0) }
        )

        // The call must succeed and return a valid session, even though
        // every keychain write will fail.
        let session = try await service.signIn(
            username: "u", password: "p", keepSignedIn: true
        )
        XCTAssertEqual(session.userId, "u1")
        XCTAssertEqual(session.accessToken, "acc")
        XCTAssertEqual(session.displayName, "User One")

        // We attempted all three writes (id, access, refresh) but the
        // FakeKeychain rejected each one. The service must have logged
        // each failure rather than rethrowing.
        XCTAssertEqual(keychain.setCallCount, 3,
                       "all three writes should have been attempted")
        let keychainFailureLogs = capturedLogs.filter { $0.contains("keychain write failed") }
        XCTAssertEqual(keychainFailureLogs.count, 3,
                       "expected three 'keychain write failed' log lines, got: \(capturedLogs)")

        // Final cache state: storage stays empty because every write threw.
        XCTAssertTrue(keychain.storage.isEmpty,
                      "no token should have made it into storage")
    }

    // MARK: - hasPersistedSession

    func test_hasPersistedSession_returnsFalse_whenNoRefreshTokenStored() {
        let keychain = FakeKeychain()
        let flow = FakeDirectAuthFlow(.mfaRequired)
        let service = makeService(flow: flow, keychain: keychain)
        XCTAssertFalse(service.hasPersistedSession())
    }

    func test_hasPersistedSession_returnsTrue_afterRefreshTokenWritten() throws {
        let keychain = FakeKeychain()
        try keychain.set("a-refresh-token", for: .refreshToken)
        let flow = FakeDirectAuthFlow(.mfaRequired)
        let service = makeService(flow: flow, keychain: keychain)
        XCTAssertTrue(service.hasPersistedSession())
    }

    // MARK: - signOut

    func test_signOut_clearsAllThreeTokens() throws {
        let keychain = FakeKeychain()
        try keychain.set("id", for: .idToken)
        try keychain.set("acc", for: .accessToken)
        try keychain.set("ref", for: .refreshToken)

        let flow = FakeDirectAuthFlow(.mfaRequired)
        let service = makeService(flow: flow, keychain: keychain)
        XCTAssertNoThrow(try service.signOut())

        XCTAssertNil(try keychain.get(.idToken))
        XCTAssertNil(try keychain.get(.accessToken))
        XCTAssertNil(try keychain.get(.refreshToken))
    }

    func test_signOut_isIdempotent_whenNothingStored() {
        let keychain = FakeKeychain()
        let flow = FakeDirectAuthFlow(.mfaRequired)
        let service = makeService(flow: flow, keychain: keychain)
        XCTAssertNoThrow(try service.signOut())
    }

    /// The first `delete` (for `.idToken`) throws. The remaining two
    /// MUST still be attempted — otherwise `.accessToken` /
    /// `.refreshToken` would be left behind and `hasPersistedSession()`
    /// (which probes `.refreshToken`) would report a live session
    /// after a "failed" sign-out, letting the caller silently restore
    /// it. The first error is still rethrown so the UI can decide
    /// whether to surface a banner.
    func test_signOut_continuesDeletingRemainingKeys_whenFirstDeleteThrows() throws {
        struct ForcedDeleteError: Error, Equatable { let message: String }
        let firstError = ForcedDeleteError(message: "forced first-key failure")

        let keychain = FakeKeychain()
        try keychain.set("id",  for: .idToken)
        try keychain.set("acc", for: .accessToken)
        try keychain.set("ref", for: .refreshToken)
        // Only the FIRST delete throws; the next two succeed.
        keychain.deleteFailureQueue = [firstError, nil, nil]

        let flow = FakeDirectAuthFlow(.mfaRequired)
        let service = makeService(flow: flow, keychain: keychain)

        // The first error is preserved and rethrown after the loop.
        XCTAssertThrowsError(try service.signOut()) { error in
            XCTAssertEqual(error as? ForcedDeleteError, firstError,
                           "signOut should rethrow the FIRST keychain delete error")
        }

        // All three deletes were attempted, in the documented order.
        XCTAssertEqual(keychain.deleteCallCount, 3,
                       "signOut MUST attempt every delete even after one throws")
        XCTAssertEqual(keychain.deletedKeysInOrder,
                       [.idToken, .accessToken, .refreshToken])

        // .accessToken and .refreshToken were cleared by the successful
        // follow-up deletes; only .idToken remains because its delete
        // threw before reaching the `removeValue` line.
        XCTAssertEqual(try keychain.get(.idToken), "id",
                       ".idToken stays because its delete threw")
        XCTAssertNil(try keychain.get(.accessToken),
                     ".accessToken MUST be cleared even after the first delete throws")
        XCTAssertNil(try keychain.get(.refreshToken),
                     ".refreshToken MUST be cleared even after the first delete throws")
    }

    // MARK: - Common assertion helper

    private func assertSignInThrows(
        _ service: OktaAuthService,
        equal expected: AuthError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await service.signIn(username: "u", password: "p", keepSignedIn: false)
            XCTFail("expected signIn to throw \(expected)", file: file, line: line)
        } catch let error as AuthError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected AuthError, got \(type(of: error)): \(error)", file: file, line: line)
        }
    }
}
