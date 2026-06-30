import Foundation

/// Formats monetary `Decimal` amounts as currency strings for display.
///
/// ## Why this exists
///
/// Money is `Decimal` everywhere in the domain (see `HomeDashboard`),
/// but `NumberFormatter` consumes `NSNumber`. This helper bridges that
/// safely without ever round-tripping through `Double` (which would
/// re-introduce the precision loss `Decimal` exists to prevent).
///
/// ## The U+2212 minus rule
///
/// The default `NumberFormatter` minus sign on iOS is U+002D
/// HYPHEN-MINUS — a typographically ugly ASCII hyphen. The design spec
/// for the monochrome Home redesign requires the proper U+2212 MINUS
/// SIGN (`−`) so a negative amount reads as "minus" rather than
/// "dash". `CurrencyFormatter` sets `formatter.minusSign = "\u{2212}"`
/// (BRACED Unicode escape — the brace-less `\u2212` form is a Swift
/// compile error) on every formatter it returns; tests assert the
/// emitted string starts with the U+2212 codepoint, not U+002D.
///
/// This is also why colour is not used to mark negatives: the
/// monochrome design communicates sign via the glyph alone.
public enum CurrencyFormatter {

    /// Format `amount` as a currency string for `currencyCode` (ISO
    /// 4217, e.g. `"USD"`). Always uses U+2212 for the negative sign,
    /// rounds to the currency's default fraction digits (2 for USD),
    /// and uses the `en_US` locale so grouping/decimal separators are
    /// stable across simulators and CI agents — the dashboard is
    /// USD-only today and the test fixtures pin to that locale.
    public static func string(from amount: Decimal, currencyCode: String) -> String {
        let formatter = makeFormatter(currencyCode: currencyCode)
        let number = NSDecimalNumber(decimal: amount)
        return formatter.string(from: number) ?? "\(amount) \(currencyCode)"
    }

    /// Build a fresh `NumberFormatter` configured for the given
    /// currency. Not cached: `NumberFormatter` is not documented as
    /// thread-safe across all configurations, and the call sites here
    /// are infrequent (a handful of rows on Home).
    private static func makeFormatter(currencyCode: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale(identifier: "en_US")
        // U+2212 MINUS SIGN — NOT U+002D HYPHEN-MINUS. Braced escape
        // is mandatory; `\u2212` (no braces) is a Swift compile error.
        formatter.minusSign = "\u{2212}"
        return formatter
    }
}
