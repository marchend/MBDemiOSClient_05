import XCTest
@testable import AcmeBank

/// Decoding tests for the `HomeDashboard` value types against the
/// `acmebank-bff-home-v1` contract wire shape.
///
/// **This file IS the app-side contract-conformance drift gate** for
/// the Home boundary. `Generated/acmebank-bff-home-v1/` is not compiled
/// into the app target (see `project.yml`), so a renamed wire field
/// would not produce a Swift build error on its own. The tests below
/// — particularly `test_contractCoverage_everyWireFieldFromV1HomeIsRead`
/// — assert every snake_case field name in the contract is consumed by
/// the decoder. If the BFF or `scripts/contract-gate.py`'s regenerated
/// tree renames a field, the corresponding assertion here flips red.
///
/// Any change to `HomeDashboard.swift` MUST land alongside an update to
/// this file (and vice versa). Reviewers: treat this as the conformance
/// gate, not a secondary check.
final class HomeDashboardDecodingTests: XCTestCase {

    // MARK: - Decoder under test

    /// Single source of truth for the decoder configuration the app
    /// uses in production (`BFFHomeRepository`). Keep these strategies
    /// in sync with `BFFHomeRepository.decode`.
    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Contract-coverage gate

    /// Drift gate: every snake_case wire field documented in
    /// `contracts/acmebank-bff-home-v1.openapi.yaml` for the
    /// `HomeDashboard` / `CustomerDto` / `AccountDto` / `TransactionDto`
    /// schemas is read by the decoder into a non-default value here.
    ///
    /// If a BFF contract change renames a field (e.g. `masked_number`
    /// → `account_number_masked`), `convertFromSnakeCase` will fail to
    /// populate the corresponding Swift property, the asserted value
    /// will fall back to its default (or the decode will throw), and
    /// this test flips red. That is the in-app contract-drift signal.
    func test_contractCoverage_everyWireFieldFromV1HomeIsRead() throws {
        let dashboard = try makeDecoder().decode(HomeDashboard.self, from: Self.bankuserOneJSON)

        // ── customer (CustomerDto) ────────────────────────────────
        // wire: id, first_name, last_name, email, phone_number
        XCTAssertEqual(dashboard.customer.id, "cust_bankuser_one", "wire: customer.id")
        XCTAssertEqual(dashboard.customer.firstName, "Bank", "wire: customer.first_name")
        XCTAssertEqual(dashboard.customer.lastName, "User", "wire: customer.last_name")
        XCTAssertEqual(dashboard.customer.email, "bankuser.one@example.com", "wire: customer.email")
        XCTAssertEqual(dashboard.customer.phoneNumber, "+1-555-0100", "wire: customer.phone_number")

        // ── accounts[0] (AccountDto) ──────────────────────────────
        // wire: id, name, masked_number, balance, available_balance, type, currency_code
        let acct = try XCTUnwrap(dashboard.accounts.first, "wire: accounts (array root)")
        XCTAssertEqual(acct.id, "acct_chk_001", "wire: accounts[].id")
        XCTAssertEqual(acct.name, "Everyday Checking", "wire: accounts[].name")
        XCTAssertEqual(acct.maskedNumber, "••1234", "wire: accounts[].masked_number")
        XCTAssertEqual(acct.balance, Decimal(string: "4287.53"), "wire: accounts[].balance")
        XCTAssertEqual(acct.availableBalance, Decimal(string: "4187.53"),
                       "wire: accounts[].available_balance")
        XCTAssertEqual(acct.type, .checking, "wire: accounts[].type")
        XCTAssertEqual(acct.currencyCode, "USD", "wire: accounts[].currency_code")

        // ── recent_transactions[0] (TransactionDto) ───────────────
        // wire: id, account_id, description, amount, posted_date, category, merchant_name
        // Also exercises the `recent_transactions` top-level key.
        let txn = try XCTUnwrap(dashboard.recentTransactions.first,
                                "wire: recent_transactions (array root)")
        XCTAssertEqual(txn.id, "txn_001", "wire: recent_transactions[].id")
        XCTAssertEqual(txn.accountId, "acct_chk_001",
                       "wire: recent_transactions[].account_id")
        XCTAssertEqual(txn.description, "BLUE BOTTLE COFFEE",
                       "wire: recent_transactions[].description")
        XCTAssertEqual(txn.amount, Decimal(string: "-6.25"),
                       "wire: recent_transactions[].amount")
        XCTAssertEqual(txn.category, "DINING",
                       "wire: recent_transactions[].category")
        XCTAssertEqual(txn.merchantName, "Blue Bottle Coffee",
                       "wire: recent_transactions[].merchant_name")
        XCTAssertEqual(txn.postedDate,
                       ISO8601DateFormatter().date(from: "2025-03-14T15:42:00Z"),
                       "wire: recent_transactions[].posted_date")
    }

    // MARK: - Full-fixture happy path (bankuser.one)

    func test_decode_bankuserOneFixture_yieldsExpectedCustomerFields() throws {
        let dashboard = try makeDecoder().decode(HomeDashboard.self, from: Self.bankuserOneJSON)

        XCTAssertEqual(dashboard.customer.id, "cust_bankuser_one")
        XCTAssertEqual(dashboard.customer.firstName, "Bank")
        XCTAssertEqual(dashboard.customer.lastName, "User")
        XCTAssertEqual(dashboard.customer.email, "bankuser.one@example.com")
        XCTAssertEqual(dashboard.customer.phoneNumber, "+1-555-0100")
    }

    func test_decode_bankuserOneFixture_yieldsFourAccountsWithCorrectTypesAndBalances() throws {
        let dashboard = try makeDecoder().decode(HomeDashboard.self, from: Self.bankuserOneJSON)

        XCTAssertEqual(dashboard.accounts.count, 4)

        let chk = dashboard.accounts[0]
        XCTAssertEqual(chk.id, "acct_chk_001")
        XCTAssertEqual(chk.name, "Everyday Checking")
        XCTAssertEqual(chk.maskedNumber, "••1234")
        XCTAssertEqual(chk.type, .checking)
        XCTAssertEqual(chk.balance, Decimal(string: "4287.53"))
        XCTAssertEqual(chk.availableBalance, Decimal(string: "4187.53"))
        XCTAssertEqual(chk.currencyCode, "USD")

        let sav = dashboard.accounts[1]
        XCTAssertEqual(sav.type, .savings)
        XCTAssertEqual(sav.balance, Decimal(string: "21500.00"))

        let crd = dashboard.accounts[2]
        XCTAssertEqual(crd.type, .credit)
        XCTAssertEqual(crd.balance, Decimal(string: "-842.19"))
        XCTAssertEqual(crd.availableBalance, Decimal(string: "9157.81"))

        let lon = dashboard.accounts[3]
        XCTAssertEqual(lon.type, .loan)
        XCTAssertEqual(lon.balance, Decimal(string: "-12450.00"))
    }

    func test_decode_bankuserOneFixture_yieldsThreeTransactions_withISO8601DateParsed() throws {
        let dashboard = try makeDecoder().decode(HomeDashboard.self, from: Self.bankuserOneJSON)

        XCTAssertEqual(dashboard.recentTransactions.count, 3)

        let first = dashboard.recentTransactions[0]
        XCTAssertEqual(first.id, "txn_001")
        XCTAssertEqual(first.accountId, "acct_chk_001")
        XCTAssertEqual(first.description, "BLUE BOTTLE COFFEE")
        XCTAssertEqual(first.amount, Decimal(string: "-6.25"))
        XCTAssertEqual(first.category, "DINING")
        XCTAssertEqual(first.merchantName, "Blue Bottle Coffee")

        // ISO-8601 round-trip: "2025-03-14T15:42:00Z"
        let expected = ISO8601DateFormatter().date(from: "2025-03-14T15:42:00Z")
        XCTAssertEqual(first.postedDate, expected)
    }

    // MARK: - Edge cases

    func test_decode_tolerates_nullMerchantName() throws {
        let json = """
        {
          "customer": \(Self.minimalCustomerJSON),
          "accounts": [],
          "recent_transactions": [
            {
              "id": "txn_x",
              "account_id": "acct_chk_001",
              "description": "ATM WITHDRAWAL",
              "amount": -100.00,
              "posted_date": "2025-03-10T10:00:00Z",
              "category": "CASH",
              "merchant_name": null
            }
          ]
        }
        """.data(using: .utf8)!

        let dashboard = try makeDecoder().decode(HomeDashboard.self, from: json)
        XCTAssertNil(dashboard.recentTransactions.first?.merchantName)
    }

    func test_decode_tolerates_nullPhoneNumber() throws {
        let json = """
        {
          "customer": {
            "id": "cust_x",
            "first_name": "No",
            "last_name": "Phone",
            "email": "nophone@example.com",
            "phone_number": null
          },
          "accounts": [],
          "recent_transactions": []
        }
        """.data(using: .utf8)!

        let dashboard = try makeDecoder().decode(HomeDashboard.self, from: json)
        XCTAssertNil(dashboard.customer.phoneNumber)
    }

    func test_decode_tolerates_unknownAccountType_asUnknown() throws {
        let json = """
        {
          "customer": \(Self.minimalCustomerJSON),
          "accounts": [
            {
              "id": "acct_new",
              "name": "Brokerage",
              "masked_number": "••0000",
              "balance": 0.00,
              "available_balance": 0.00,
              "type": "BROKERAGE",
              "currency_code": "USD"
            }
          ],
          "recent_transactions": []
        }
        """.data(using: .utf8)!

        let dashboard = try makeDecoder().decode(HomeDashboard.self, from: json)
        XCTAssertEqual(dashboard.accounts.first?.type, .unknown,
                       "unknown wire types must decode to .unknown, not throw")
    }

    func test_decode_decimalBalances_areExactNotDouble() throws {
        // A balance that lands on a value Double cannot represent
        // exactly (0.1 + 0.2 lore). If we silently went through Double
        // the comparison below would fail.
        let json = """
        {
          "customer": \(Self.minimalCustomerJSON),
          "accounts": [
            {
              "id": "acct_exact",
              "name": "Exact",
              "masked_number": "••0001",
              "balance": 0.10,
              "available_balance": 0.20,
              "type": "CHECKING",
              "currency_code": "USD"
            }
          ],
          "recent_transactions": []
        }
        """.data(using: .utf8)!

        let dashboard = try makeDecoder().decode(HomeDashboard.self, from: json)
        XCTAssertEqual(dashboard.accounts.first?.balance, Decimal(string: "0.10"))
        XCTAssertEqual(dashboard.accounts.first?.availableBalance, Decimal(string: "0.20"))
    }

    // MARK: - Fixtures

    private static let minimalCustomerJSON = """
    {
      "id": "cust_min",
      "first_name": "Min",
      "last_name": "Imal",
      "email": "min@example.com",
      "phone_number": "+1-555-0000"
    }
    """

    /// The "bankuser.one" sample payload referenced by the story. Kept
    /// inline so the test file is self-contained — no bundled-resource
    /// machinery in the test target.
    static let bankuserOneJSON: Data = """
    {
      "customer": {
        "id": "cust_bankuser_one",
        "first_name": "Bank",
        "last_name": "User",
        "email": "bankuser.one@example.com",
        "phone_number": "+1-555-0100"
      },
      "accounts": [
        {
          "id": "acct_chk_001",
          "name": "Everyday Checking",
          "masked_number": "••1234",
          "balance": 4287.53,
          "available_balance": 4187.53,
          "type": "CHECKING",
          "currency_code": "USD"
        },
        {
          "id": "acct_sav_001",
          "name": "High-Yield Savings",
          "masked_number": "••5678",
          "balance": 21500.00,
          "available_balance": 21500.00,
          "type": "SAVINGS",
          "currency_code": "USD"
        },
        {
          "id": "acct_crd_001",
          "name": "Acme Platinum Card",
          "masked_number": "••9012",
          "balance": -842.19,
          "available_balance": 9157.81,
          "type": "CREDIT",
          "currency_code": "USD"
        },
        {
          "id": "acct_lon_001",
          "name": "Auto Loan",
          "masked_number": "••3456",
          "balance": -12450.00,
          "available_balance": 0.00,
          "type": "LOAN",
          "currency_code": "USD"
        }
      ],
      "recent_transactions": [
        {
          "id": "txn_001",
          "account_id": "acct_chk_001",
          "description": "BLUE BOTTLE COFFEE",
          "amount": -6.25,
          "posted_date": "2025-03-14T15:42:00Z",
          "category": "DINING",
          "merchant_name": "Blue Bottle Coffee"
        },
        {
          "id": "txn_002",
          "account_id": "acct_chk_001",
          "description": "PAYROLL DEPOSIT",
          "amount": 3250.00,
          "posted_date": "2025-03-13T13:00:00Z",
          "category": "INCOME",
          "merchant_name": null
        },
        {
          "id": "txn_003",
          "account_id": "acct_crd_001",
          "description": "AMAZON.COM",
          "amount": -42.99,
          "posted_date": "2025-03-12T09:11:00Z",
          "category": "SHOPPING",
          "merchant_name": "Amazon"
        }
      ]
    }
    """.data(using: .utf8)!
}
