import XCTest
@testable import AcmeBank

/// Decoding tests for the `HomeDashboard` value types against the
/// `acmebank-bff-home-v1` contract wire shape.
///
/// These tests are the canonical specification of how the app reads the
/// BFF payload — if a contract field is renamed and the generator
/// regenerates, this file is the first to flip red.
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
