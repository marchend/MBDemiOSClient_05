import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Value-type representation of the signed-in user, derived from the
/// Okta ID-token JWT plus the matching access token.
///
/// `UserSession` is intentionally a `struct` (no reference identity) and
/// is constructed once at sign-in time from the JWT payload. It does not
/// hold the ID token itself — only the claims we need to render the UI
/// and authenticate API calls.
///
/// The ID token is a standard JWT: three base64URL-encoded segments
/// joined by '.'. We only decode the MIDDLE segment (the payload) — we
/// do NOT verify the signature here. Signature verification happens at
/// the BFF: it receives the access token, validates `iss` + `aud` +
/// signature against Okta's JWKS, and only then trusts the claims.
/// Inside this trusted iOS process we just want the display fields.
public struct UserSession: Equatable {
    /// Stable Okta user id (`sub` claim). Used for telemetry + as the
    /// primary key when caching per-user data.
    public let userId: String

    /// Human-readable name (`name` claim). Used for the greeting on Home.
    public let displayName: String

    /// Email (`email` claim). May be empty if the token didn't carry it.
    public let email: String

    /// OAuth2 access token. Caller is responsible for refreshing.
    public let accessToken: String

    /// Wall-clock time at which the session was created. Used to display
    /// "Signed in at …" on the More tab.
    public let authTimestamp: Date

    /// `UIDevice.current.name` at sign-in time, captured here so the
    /// session can render it without re-touching `UIKit` from view code.
    public let deviceName: String

    public init(
        userId: String,
        displayName: String,
        email: String,
        accessToken: String,
        authTimestamp: Date,
        deviceName: String
    ) {
        self.userId = userId
        self.displayName = displayName
        self.email = email
        self.accessToken = accessToken
        self.authTimestamp = authTimestamp
        self.deviceName = deviceName
    }

    // MARK: - JWT decode

    /// Decode an Okta ID-token JWT and bundle it with the matching
    /// access token into a `UserSession`.
    ///
    /// - Parameters:
    ///   - idTokenJWT: The raw `id_token` string returned by Okta.
    ///   - accessToken: The matching `access_token`.
    ///   - deviceName: Captured device name; defaults to
    ///     `UIDevice.current.name` on iOS, "Unknown device" elsewhere.
    ///   - now: Injection seam for tests; defaults to `Date()`.
    /// - Throws: `DecodeError` if the JWT is malformed or the payload
    ///   is missing required claims.
    public static func make(
        idTokenJWT: String,
        accessToken: String,
        deviceName: String? = nil,
        now: Date = Date()
    ) throws -> UserSession {
        let claims = try decodeClaims(from: idTokenJWT)
        return UserSession(
            userId: claims.sub,
            displayName: claims.name ?? "",
            email: claims.email ?? "",
            accessToken: accessToken,
            authTimestamp: now,
            deviceName: deviceName ?? defaultDeviceName()
        )
    }

    /// Errors thrown by JWT decoding. Distinct from `AuthError` so the
    /// caller (`OktaAuthService`) can map them to
    /// `AuthError.invalidServerResponse(...)` and never let them escape
    /// unwrapped — see the post-SDK-success error-mapping rule.
    public enum DecodeError: Error, Equatable {
        /// Token does not have three dot-separated segments.
        case malformedStructure
        /// Middle segment is not valid base64URL.
        case payloadNotBase64URL
        /// Middle segment decoded to bytes but is not valid UTF-8 JSON
        /// or is missing required claims (`sub`).
        case payloadNotJSON
    }

    // MARK: - Internals

    /// Mirror of the subset of OIDC claims we read. `sub` is required;
    /// `name` and `email` are best-effort and may be absent.
    private struct Claims: Decodable {
        let sub: String
        let name: String?
        let email: String?
    }

    private static func decodeClaims(from jwt: String) throws -> Claims {
        // 1. JWT must have exactly three segments: header.payload.signature.
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { throw DecodeError.malformedStructure }
        let payloadSegment = String(segments[1])
        guard !payloadSegment.isEmpty else { throw DecodeError.malformedStructure }

        // 2. base64URL → base64 → Data.
        guard let payloadData = base64URLDecode(payloadSegment) else {
            throw DecodeError.payloadNotBase64URL
        }

        // 3. JSON decode into our claim set.
        do {
            return try JSONDecoder().decode(Claims.self, from: payloadData)
        } catch {
            throw DecodeError.payloadNotJSON
        }
    }

    /// Convert a base64URL string (RFC 7515, `-`/`_` alphabet, no `=`
    /// padding) into raw bytes. Returns nil if the input is not valid
    /// base64URL.
    private static func base64URLDecode(_ input: String) -> Data? {
        var s = input.replacingOccurrences(of: "-", with: "+")
                     .replacingOccurrences(of: "_", with: "/")
        // Re-add `=` padding to a multiple of 4.
        let remainder = s.count % 4
        if remainder > 0 {
            s.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: s)
    }

    private static func defaultDeviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Unknown device"
        #endif
    }
}
