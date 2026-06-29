import SwiftUI

/// One row in the "Accounts" list on the Home dashboard.
///
/// Layout (left → right):
///   * Dark-navy rounded icon tile with a monochrome SF Symbol
///     reflecting the account type (purely decorative — no semantic
///     colour).
///   * Two-line label: account name + "<Type> · ···· <last4>" subtitle.
///   * Right-aligned balance: currency-formatted amount stacked over
///     the ISO currency code subtext. For negative balances, the
///     balance is prefixed with U+2212 (via `CurrencyFormatter`) and
///     the subtext is replaced with "<available_balance> available"
///     so the user sees what they can still spend.
///
/// All colour is in the monochrome palette; sign is communicated by
/// the glyph, never by tint.
public struct AccountRow: View {

    public let account: Account

    public init(account: Account) {
        self.account = account
    }

    public var body: some View {
        HStack(spacing: 14) {
            iconTile
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AcmeColors.text)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AcmeColors.subtext)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(balanceString)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AcmeColors.text)
                    .monospacedDigit()
                Text(balanceSubtext)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AcmeColors.subtext)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AcmeColors.surface)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.account.\(account.id)")
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AcmeColors.navy900)
            Image(systemName: iconSystemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AcmeColors.onNavy)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    private var iconSystemName: String {
        switch account.type {
        case .checking: return "banknote"
        case .savings: return "building.columns"
        case .credit: return "creditcard"
        case .loan: return "doc.text"
        case .unknown: return "questionmark.circle"
        }
    }

    private var subtitle: String {
        // U+00B7 MIDDLE DOT separator; the four dots before <last4>
        // are the standard masked-PAN convention.
        "\(typeLabel) \u{00B7} \u{00B7}\u{00B7}\u{00B7}\u{00B7} \(last4)"
    }

    private var typeLabel: String {
        switch account.type {
        case .checking: return "Checking"
        case .savings: return "Savings"
        case .credit: return "Credit"
        case .loan: return "Loan"
        case .unknown: return "Account"
        }
    }

    /// The last four characters of `maskedNumber` (or the whole
    /// string if it is shorter). The wire field already arrives
    /// masked from the BFF (e.g. `"****1234"`), so trimming to the
    /// suffix yields the visible digits.
    private var last4: String {
        let trimmed = account.maskedNumber.filter { $0.isLetter || $0.isNumber }
        return String(trimmed.suffix(4))
    }

    /// Formatted balance. For negative balances the
    /// `CurrencyFormatter` already prepends U+2212, but for the
    /// edge case where a future locale strips it we force-prepend
    /// the same glyph onto the absolute-value string. Today the
    /// formatter handles it, so the public string is always
    /// `CurrencyFormatter.string(from:currencyCode:)`.
    private var balanceString: String {
        CurrencyFormatter.string(from: account.balance, currencyCode: account.currencyCode)
    }

    private var balanceSubtext: String {
        if account.balance < 0 {
            let available = CurrencyFormatter.string(
                from: account.availableBalance,
                currencyCode: account.currencyCode
            )
            return "\(available) available"
        }
        return account.currencyCode
    }
}

#Preview {
    VStack(spacing: 8) {
        AccountRow(account: Account(
            id: "a1",
            name: "Everyday Checking",
            maskedNumber: "****1234",
            balance: Decimal(string: "1542.88")!,
            availableBalance: Decimal(string: "1542.88")!,
            type: .checking,
            currencyCode: "USD"
        ))
        AccountRow(account: Account(
            id: "a2",
            name: "Platinum Card",
            maskedNumber: "****9911",
            balance: Decimal(string: "-243.10")!,
            availableBalance: Decimal(string: "4756.90")!,
            type: .credit,
            currencyCode: "USD"
        ))
    }
    .padding()
    .background(AcmeColors.background)
}
