import SwiftUI

/// One row in the "Recent transactions" list on the Home dashboard.
///
/// Layout:
///   * Monochrome circular avatar with the first letter of the
///     `merchant_name` (or `description` if no merchant — cash,
///     transfers, fees).
///   * Two-line label: `description` primary, `posted_date` formatted
///     "MMM d, yyyy" secondary.
///   * Right-aligned signed amount via `CurrencyFormatter`, so
///     negatives use U+2212 and POSITIVES use the SAME monochrome
///     text colour as negatives — sign is communicated by the glyph,
///     never by colour.
///
/// ## `transaction.description` naming-overlap trap
///
/// The `Transaction.description` field this row reads is a domain
/// property whose name happens to collide with the requirement of
/// Swift's `CustomStringConvertible`. The trap (and why a future
/// `extension Transaction: CustomStringConvertible {}` would silently
/// break this view) is documented in full on `Transaction` itself in
/// `AcmeBank/Features/Home/Model/HomeDashboard.swift`. If you find
/// yourself adding a `CustomStringConvertible` conformance, read that
/// note first.
public struct TransactionRow: View {

    public let transaction: Transaction
    public let currencyCode: String

    public init(transaction: Transaction, currencyCode: String) {
        self.transaction = transaction
        self.currencyCode = currencyCode
    }

    public var body: some View {
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AcmeColors.text)
                    .lineLimit(1)
                Text(Self.dateFormatter.string(from: transaction.postedDate))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AcmeColors.subtext)
            }
            Spacer(minLength: 8)
            Text(amountString)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AcmeColors.text)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.txn.\(transaction.id)")
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(AcmeColors.background)
            Circle()
                .stroke(AcmeColors.divider, lineWidth: 1)
            Text(avatarLetter)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AcmeColors.text)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    private var avatarLetter: String {
        let source = transaction.merchantName ?? transaction.description
        guard let first = source.first(where: { $0.isLetter || $0.isNumber }) else {
            return "?"
        }
        return String(first).uppercased()
    }

    /// The signed amount string. `CurrencyFormatter` handles the
    /// negative case by prepending U+2212; positives render as the
    /// plain currency string.
    private var amountString: String {
        CurrencyFormatter.string(from: transaction.amount, currencyCode: currencyCode)
    }

    /// Locale-pinned formatter so the rendered date is identical
    /// across CI agents and prod (e.g. "Jan 4, 2025").
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}

#Preview {
    VStack(spacing: 0) {
        TransactionRow(
            transaction: Transaction(
                id: "t1",
                accountId: "a1",
                description: "Blue Bottle Coffee",
                amount: Decimal(string: "-6.75")!,
                postedDate: Date(timeIntervalSince1970: 1_704_412_800),
                category: "DINING",
                merchantName: "Blue Bottle"
            ),
            currencyCode: "USD"
        )
        TransactionRow(
            transaction: Transaction(
                id: "t2",
                accountId: "a1",
                description: "Payroll deposit",
                amount: Decimal(string: "2450.00")!,
                postedDate: Date(timeIntervalSince1970: 1_704_326_400),
                category: "INCOME",
                merchantName: nil
            ),
            currencyCode: "USD"
        )
    }
    .padding()
    .background(AcmeColors.surface)
}
