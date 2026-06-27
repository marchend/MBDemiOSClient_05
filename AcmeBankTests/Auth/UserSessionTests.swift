import XCTest
@testable import AcmeBank

final class UserSessionTests: XCTestCase {

    // MARK: - Happy path

    func test_make_decodesSubNameEmailFromJWTPayload() throws {
        // Payload: {"sub":"00uABC","name":"Jane Doe","email":"jane@example.com"}
        let jwt = makeJWT(payload: #"""
        {"sub":"00uABC","name":"Jane Doe","email":"jane@example.com"}
        """#)
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

        let session = try UserSession.make(
            idTokenJWT: jwt,
            accessToken: "access-token-xyz",
            deviceName: "Jane's iPhone",
            now: fixedNow
        )

        XCTAssertEqual(session.userId, "00uABC")
        XCTAssertEqual(session.displayName, "Jane Doe")
        XCTAssertEqual(session.email, "jane@example.com")
        XCTAssertEqual(session.accessToken, "access-token-xyz")
        XCTAssertEqual(session.authTimestamp, fixedNow)
        XCTAssertEqual(session.deviceName, "Jane's iPhone")
    }

    func test_make_acceptsBase64URLAlphabet_withoutPadding() throws {
        // base64URL uses `-` and `_` and may omit `=` padding. Build a
        // payload whose base64 (standard alphabet) contains a `+` so
        // the URL-encoded form differs from the standard form.
        // Payload picked so its base64 contains '+/=' characters.
        let payload = #"{"sub":"u","name":"??>","email":""}"#
        // base64URL the payload manually to exercise that path.
        let payloadData = payload.data(using: .utf8)!
        var b64 = payloadData.base64EncodedString()
        b64 = b64.replacingOccurrences(of: "+", with: "-")
                 .replacingOccurrences(of: "/", with: "_")
                 .replacingOccurrences(of: "=", with: "")
        let jwt = "header.\(b64).signature"

        let session = try UserSession.make(
            idTokenJWT: jwt,
            accessToken: "tok"
        )
        XCTAssertEqual(session.userId, "u")
        XCTAssertEqual(session.displayName, "??>")
    }

    func test_make_treatsMissingNameAndEmailAsEmptyString() throws {
        let jwt = makeJWT(payload: #"{"sub":"only-sub"}"#)

        let session = try UserSession.make(
            idTokenJWT: jwt,
            accessToken: "tok"
        )
        XCTAssertEqual(session.userId, "only-sub")
        XCTAssertEqual(session.displayName, "")
        XCTAssertEqual(session.email, "")
    }

    // MARK: - Malformed structure

    func test_make_throwsMalformedStructure_whenJWTHasOneSegment() {
        XCTAssertThrowsError(try UserSession.make(idTokenJWT: "abc", accessToken: "tok")) { error in
            XCTAssertEqual(error as? UserSession.DecodeError, .malformedStructure)
        }
    }

    func test_make_throwsMalformedStructure_whenJWTHasTwoSegments() {
        XCTAssertThrowsError(try UserSession.make(idTokenJWT: "abc.def", accessToken: "tok")) { error in
            XCTAssertEqual(error as? UserSession.DecodeError, .malformedStructure)
        }
    }

    func test_make_throwsMalformedStructure_whenPayloadSegmentIsEmpty() {
        XCTAssertThrowsError(try UserSession.make(idTokenJWT: "abc..sig", accessToken: "tok")) { error in
            XCTAssertEqual(error as? UserSession.DecodeError, .malformedStructure)
        }
    }

    // MARK: - Malformed payload

    func test_make_throwsPayloadNotBase64URL_whenMiddleSegmentIsNotBase64() {
        // '!!!' contains no valid base64URL characters and fails padding.
        let jwt = "header.!!!.sig"
        XCTAssertThrowsError(try UserSession.make(idTokenJWT: jwt, accessToken: "tok")) { error in
            XCTAssertEqual(error as? UserSession.DecodeError, .payloadNotBase64URL)
        }
    }

    func test_make_throwsPayloadNotJSON_whenMiddleSegmentIsBase64ButNotJSON() {
        // base64URL of "not-json" → "bm90LWpzb24"
        let payloadData = "not-json".data(using: .utf8)!
        let b64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let jwt = "header.\(b64).sig"

        XCTAssertThrowsError(try UserSession.make(idTokenJWT: jwt, accessToken: "tok")) { error in
            XCTAssertEqual(error as? UserSession.DecodeError, .payloadNotJSON)
        }
    }

    func test_make_throwsPayloadNotJSON_whenSubClaimIsMissing() {
        // Valid JSON but missing the required `sub` claim.
        let jwt = makeJWT(payload: #"{"name":"NoSub"}"#)

        XCTAssertThrowsError(try UserSession.make(idTokenJWT: jwt, accessToken: "tok")) { error in
            XCTAssertEqual(error as? UserSession.DecodeError, .payloadNotJSON)
        }
    }

    // MARK: - Helpers

    /// Build a fake JWT with a fixed header + signature and the given
    /// JSON payload base64URL-encoded as the middle segment.
    private func makeJWT(payload: String) -> String {
        let payloadData = payload.data(using: .utf8)!
        let b64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(b64).signature"
    }
}
