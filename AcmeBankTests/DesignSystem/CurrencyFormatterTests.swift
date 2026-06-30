import XCTest
@testable import AcmeBank

/// Behavioural contract for `CurrencyFormatter`.
///
/// The Home design spec requires:
///   1. Standard currency formatting for USD (`$1,234.56`).
///   2. Negatives use U+2212 MINUS SIGN, not U+002D HYPHEN-MINUS —
///      this is what the monochrome design uses to communicate sign
///      (no red/green colour). Asserted by codepoint.
///   3. Zero renders cleanly as `$0.00`.
///   4. `Decimal` values with > 2 fraction digits round to the
///      currency's default (2 for USD) without dropping into `Double`.
final class CurrencyFormatterTests: XCTestCase {

    func test_positiveUSD_formatsAsDollarsWithGrouping() {
        let amount = Decimal(string: "1542.88")!
        let formatted = CurrencyFormatter.string(from: amount, currencyCode: "USD")
        XCTAssertEqual(formatted, "$1,542.88")
    }

    func test_negativeUSD_startsWithU2212MinusSign_notHyphenMinus() {
        let amount = Decimal(string: "-243.10")!
        let formatted = CurrencyFormatter.string(from: amount, currencyCode: "USD")

        let first = formatted.unicodeScalars.first
        XCTAssertNotNil(first, "Formatted negative amount must not be empty")
        XCTAssertEqual(
            first?.value,
            0x2212,
            "Negative amounts must start with U+2212 MINUS SIGN (got codepoint \(first?.value ?? 0))"
        )
        // Defensive: the legacy ASCII hyphen-minus must not appear at
        // the start either.
        XCTAssertNotEqual(first?.value, 0x002D, "Must not use U+002D HYPHEN-MINUS")
        // And the remainder of the string is still the dollar amount.
        XCTAssertTrue(formatted.contains("$243.10"), "Expected '$243.10' in '\(formatted)'")
    }

    func test_zero_formatsAsCleanDollarZero() {
        let formatted = CurrencyFormatter.string(from: Decimal(0), currencyCode: "USD")
        XCTAssertEqual(formatted, "$0.00")
    }

    func test_decimalWithMoreThanTwoFractionDigits_roundsToCurrencyDefault() {
        // Decimal literal carries 4 fraction digits; USD uses 2.
        // Half-up rounding on 1.235 → 1.24 (NumberFormatter default).
        let amount = Decimal(string: "1.235")!
        let formatted = CurrencyFormatter.string(from: amount, currencyCode: "USD")
        XCTAssertEqual(formatted, "$1.24")
    }
}
