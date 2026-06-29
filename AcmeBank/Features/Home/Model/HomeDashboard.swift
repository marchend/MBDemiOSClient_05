import Foundation

/// The Home dashboard payload returned by `GET {API_BASE_URL}/v1/home`,
/// decoded as plain Swift value types.
///
/// ## Why hand-rolled vs the generated `Generated/acmebank-bff-home-v1/`
/// types?
///
/// The OpenAPI generator emits `HomeDashboard` / `CustomerDto` /
/// `AccountDto` / `TransactionDto` under `Generated/` from the
/// `acmebank-bff-home-v1` contract. Those generated structs are the
/// authoritative wire-shape contract — they pin every field name and
/// optionality — but for the in-app model we need two things the
/// generator does not give us:
///
/// 1. **`Decimal` for money**, not `Double`. The generated `AccountDto`
///    uses `Double` for `balance` / `available_balance`, which silently
///    loses precision for amounts a bank actually cares about (cent
///    rounding on subtraction, etc.). Money must be exact, full stop.
/// 2. **An `AccountType` enum that tolerates unknown wire values.** The
///    generated `type: String?` lets a stray new account type ("BROKERAGE",
///    "HELOC", …) sail through as a raw string the UI then can't switch
///    on. We model `.checking / .savings / .credit / .loan / .unknown` so
///    `default` cases are exhaustive and a forward-incompatible payload
///    degrades to "Unknown account type" instead of a crash.
///
/// The field names + snake_case wire shape are still pinned to the
/// generated contract — that's what `convertFromSnakeCase` on the
/// `JSONDecoder` consumes. If the contract evolves, these types must
/// evolve in lock-step (and a new generated tree will be regenerated).
///
/// ## How contract drift is caught (the drift gate, made explicit)
///
/// `Generated/acmebank-bff-home-v1/` is **NOT compiled into the app
/// target** (see `project.yml` — only `AcmeBank/` is in the source
/// root). The generated types therefore cannot fail a Swift build when
/// the contract changes; they exist on disk only as the input
/// `scripts/contract-gate.py` re-generates against to detect drift in
/// the committed tree itself.
///
/// The actual app-side drift gate is **`HomeDashboardDecodingTests`** in
/// `AcmeBankTests/Features/Home/`. Those tests:
///
///   * decode the full `bankuser.one` fixture and assert every field
///     by name (`first_name`, `phone_number`, `masked_number`,
///     `available_balance`, `currency_code`, `account_id`,
///     `posted_date`, `merchant_name`, `recent_transactions`, …), and
///   * assert that `Decimal` precision is preserved and unknown
///     `AccountType` values fall through to `.unknown`.
///
/// If the BFF contract renames a wire field (e.g. `masked_number` →
/// `account_number_masked`), `convertFromSnakeCase` will fail to find
/// the property and the decoding test for that field flips red BEFORE
/// the app ships. Any contract change MUST therefore land in lockstep
/// with an update to both this file AND
/// `HomeDashboardDecodingTests`. Reviewers: treat that test file as
/// the conformance assertion for this model — it is the gate, not a
/// secondary check.
public struct HomeDashboard: Decodable, Equatable {
    public let customer: Customer
    public let accounts: [Account]
    public let recentTransactions: [Transaction]

    public init(customer: Customer, accounts: [Account], recentTransactions: [Transaction]) {
        self.customer = customer
        self.accounts = accounts
        self.recentTransactions = recentTransactions
    }
}

public struct Customer: Decodable, Equatable {
    public let id: String
    public let firstName: String
    public let lastName: String
    public let email: String
    /// May be absent from the wire payload (null or missing).
    public let phoneNumber: String?

    public init(id: String, firstName: String, lastName: String, email: String, phoneNumber: String?) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phoneNumber = phoneNumber
    }
}

public struct Account: Decodable, Equatable {
    public let id: String
    public let name: String
    public let maskedNumber: String
    public let balance: Decimal
    public let availableBalance: Decimal
    public let type: AccountType
    public let currencyCode: String

    public init(
        id: String,
        name: String,
        maskedNumber: String,
        balance: Decimal,
        availableBalance: Decimal,
        type: AccountType,
        currencyCode: String
    ) {
        self.id = id
        self.name = name
        self.maskedNumber = maskedNumber
        self.balance = balance
        self.availableBalance = availableBalance
        self.type = type
        self.currencyCode = currencyCode
    }
}

public struct Transaction: Decodable, Equatable {
    public let id: String
    public let accountId: String
    public let description: String
    public let amount: Decimal
    public let postedDate: Date
    public let category: String
    /// May be absent (cash withdrawals, transfers, fees, …).
    public let merchantName: String?

    public init(
        id: String,
        accountId: String,
        description: String,
        amount: Decimal,
        postedDate: Date,
        category: String,
        merchantName: String?
    ) {
        self.id = id
        self.accountId = accountId
        self.description = description
        self.amount = amount
        self.postedDate = postedDate
        self.category = category
        self.merchantName = merchantName
    }
}

/// Account product type. Wire format is UPPERCASE ASCII; any value the
/// app doesn't recognise decodes to `.unknown` (never throws) so a
/// forward-incompatible payload still renders.
public enum AccountType: String, Decodable, Equatable {
    case checking = "CHECKING"
    case savings = "SAVINGS"
    case credit = "CREDIT"
    case loan = "LOAN"
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = AccountType(rawValue: raw) ?? .unknown
    }
}
