import XCTest
@testable import AcmeBank

final class OktaConfigTests: XCTestCase {

    // MARK: - Happy path

    func test_load_returnsConfigured_whenAllFourKeysArePresent() {
        let result = OktaConfig.resolve(lookup: validLookup())

        guard case let .configured(issuer, clientId, redirectURI, scopes) = result else {
            return XCTFail("expected .configured, got \(result)")
        }
        XCTAssertEqual(issuer.absoluteString, "https://example.okta.com/oauth2/default")
        XCTAssertEqual(clientId, "abc123client")
        XCTAssertEqual(redirectURI.absoluteString, "com.acmebank.mobile://callback")
        XCTAssertEqual(scopes, ["openid", "profile", "offline_access"])
    }

    func test_load_splitsScopes_onArbitraryWhitespace() {
        var values = validValues()
        values[OktaConfig.Key.scopes] = "  openid \t profile\noffline_access  "
        let result = OktaConfig.resolve(lookup: lookup(values))

        guard case let .configured(_, _, _, scopes) = result else {
            return XCTFail("expected .configured, got \(result)")
        }
        XCTAssertEqual(scopes, ["openid", "profile", "offline_access"])
    }

    // MARK: - Missing / sentinel keys

    func test_load_returnsNotConfigured_whenIssuerKeyIsMissing() {
        var values = validValues()
        values.removeValue(forKey: OktaConfig.Key.issuer)

        guard case let .notConfigured(reason) = OktaConfig.resolve(lookup: lookup(values)) else {
            return XCTFail("expected .notConfigured")
        }
        XCTAssertTrue(reason.contains(OktaConfig.Key.issuer),
                      "reason should name the missing key, got: \(reason)")
    }

    func test_load_returnsNotConfigured_whenClientIdSentinelSurvives() {
        var values = validValues()
        values[OktaConfig.Key.clientId] = "__OKTA_CLIENT_ID_UNSET__"

        guard case let .notConfigured(reason) = OktaConfig.resolve(lookup: lookup(values)) else {
            return XCTFail("expected .notConfigured")
        }
        XCTAssertTrue(reason.contains(OktaConfig.Key.clientId),
                      "reason should name the sentinel-valued key, got: \(reason)")
    }

    func test_load_returnsNotConfigured_whenRedirectURIIsEmptyString() {
        var values = validValues()
        values[OktaConfig.Key.redirectURI] = ""

        guard case let .notConfigured(reason) = OktaConfig.resolve(lookup: lookup(values)) else {
            return XCTFail("expected .notConfigured")
        }
        XCTAssertTrue(reason.contains(OktaConfig.Key.redirectURI), "reason: \(reason)")
    }

    func test_load_returnsNotConfigured_whenAllSentinelsSurvive_andNamesAllFourKeys() {
        let allSentinels: [String: Any] = [
            OktaConfig.Key.issuer: "__OKTA_ISSUER_UNSET__",
            OktaConfig.Key.clientId: "__OKTA_CLIENT_ID_UNSET__",
            OktaConfig.Key.redirectURI: "__OKTA_REDIRECT_URI_UNSET__",
            OktaConfig.Key.scopes: "__OKTA_SCOPES_UNSET__"
        ]
        guard case let .notConfigured(reason) = OktaConfig.resolve(lookup: lookup(allSentinels)) else {
            return XCTFail("expected .notConfigured")
        }
        XCTAssertTrue(reason.contains(OktaConfig.Key.issuer), reason)
        XCTAssertTrue(reason.contains(OktaConfig.Key.clientId), reason)
        XCTAssertTrue(reason.contains(OktaConfig.Key.redirectURI), reason)
        XCTAssertTrue(reason.contains(OktaConfig.Key.scopes), reason)
    }

    // MARK: - Malformed URL

    func test_load_returnsNotConfigured_whenIssuerIsMalformedURL() {
        var values = validValues()
        values[OktaConfig.Key.issuer] = "not a url"

        guard case let .notConfigured(reason) = OktaConfig.resolve(lookup: lookup(values)) else {
            return XCTFail("expected .notConfigured")
        }
        XCTAssertTrue(reason.contains(OktaConfig.Key.issuer), "reason: \(reason)")
    }

    func test_load_returnsNotConfigured_whenIssuerHasNoScheme() {
        var values = validValues()
        values[OktaConfig.Key.issuer] = "example.okta.com/oauth2/default"

        guard case let .notConfigured(reason) = OktaConfig.resolve(lookup: lookup(values)) else {
            return XCTFail("expected .notConfigured")
        }
        XCTAssertTrue(reason.contains(OktaConfig.Key.issuer), "reason: \(reason)")
    }

    func test_load_returnsNotConfigured_whenRedirectURIIsMalformed() {
        var values = validValues()
        values[OktaConfig.Key.redirectURI] = "not a url either"

        guard case let .notConfigured(reason) = OktaConfig.resolve(lookup: lookup(values)) else {
            return XCTFail("expected .notConfigured")
        }
        XCTAssertTrue(reason.contains(OktaConfig.Key.redirectURI), "reason: \(reason)")
    }

    // MARK: - Public API smoke test

    func test_load_withMainBundle_doesNotCrash() {
        // The main bundle in the test host either has sentinels (no env
        // vars) or real values (CI with env vars set). Either way, `load`
        // must be total — no traps, no force-unwraps.
        _ = OktaConfig.load()
    }

    // MARK: - Fixtures

    private func validValues() -> [String: Any] {
        return [
            OktaConfig.Key.issuer: "https://example.okta.com/oauth2/default",
            OktaConfig.Key.clientId: "abc123client",
            OktaConfig.Key.redirectURI: "com.acmebank.mobile://callback",
            OktaConfig.Key.scopes: "openid profile offline_access"
        ]
    }

    private func validLookup() -> (String) -> Any? {
        return lookup(validValues())
    }

    private func lookup(_ values: [String: Any]) -> (String) -> Any? {
        return { key in values[key] }
    }
}
