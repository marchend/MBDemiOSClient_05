import Foundation

/// Build-time configuration read from the main bundle's Info.plist.
///
/// Keys here follow the same xcconfig-baked pattern as the `OKTA_*`
/// values (see `OktaConfig`): the source `Info.plist` holds
/// `<key>X</key><string>$(X)</string>` references, an xcconfig in
/// `Config/` supplies the value (`Secrets.example.xcconfig` placeholders,
/// `Secrets.local.xcconfig` overrides), and Xcode's
/// `ProcessInfoPlistFile` bakes the real value on every build. No
/// post-build script touches the built plist.
///
/// `apiBaseURL` is read on demand rather than cached so unit tests can
/// swap the underlying lookup via `resolveAPIBaseURL(lookup:)`.
public enum AppConfig {

    /// Info.plist keys this loader consumes. Public so tests can drive
    /// the resolver and `setup.sh` / docs can grep for the canonical name.
    public enum Key {
        public static let apiBaseURL = "API_BASE_URL"
    }

    /// Strongly-typed errors surfaced by `apiBaseURL` in release builds.
    /// In DEBUG we `assertionFailure` so a misconfigured developer build
    /// fails loudly; in release we throw so the network call site can
    /// render the standard error state instead of crashing the app.
    public enum ConfigError: Error, Equatable {
        /// The key was absent, empty, or still carried the
        /// `placeholder.invalid` value from `Secrets.example.xcconfig`.
        case missing(key: String)
        /// The value was present but did not parse as a URL.
        case invalidURL(key: String, raw: String)
    }

    /// The BFF base URL. Trailing slash is stripped so callers can
    /// safely append `/v1/home`.
    ///
    /// - Throws: `ConfigError` if the key is missing / placeholder /
    ///   not a URL. In DEBUG builds an `assertionFailure` precedes the
    ///   throw so developer mis-configuration is caught at first run.
    public static func apiBaseURL(bundle: Bundle = .main) throws -> URL {
        return try resolveAPIBaseURL { key in bundle.object(forInfoDictionaryKey: key) }
    }

    /// Pure resolver used by both the public accessor and unit tests.
    static func resolveAPIBaseURL(lookup: (String) -> Any?) throws -> URL {
        let raw = (lookup(Key.apiBaseURL) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // `placeholder.invalid` is the value `Secrets.example.xcconfig`
        // ships when no `Secrets.local.xcconfig` is present — treat it
        // exactly like "missing".
        guard !raw.isEmpty, !raw.contains("placeholder.invalid") else {
            #if DEBUG
            assertionFailure("AppConfig.\(Key.apiBaseURL) is not configured (got \"\(raw)\")")
            #endif
            throw ConfigError.missing(key: Key.apiBaseURL)
        }

        guard let url = URL(string: raw), url.scheme != nil else {
            #if DEBUG
            assertionFailure("AppConfig.\(Key.apiBaseURL) is not a valid URL: \"\(raw)\"")
            #endif
            throw ConfigError.invalidURL(key: Key.apiBaseURL, raw: raw)
        }
        return url
    }
}
