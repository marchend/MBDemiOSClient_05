import Foundation

/// Non-shipping stub implementation of `HomeRepositoryProtocol` used by
/// SwiftUI previews and unit tests ONLY.
///
/// ⚠️ This type is intentionally available to the production target
/// (rather than test-only) so SwiftUI `#Preview` blocks in
/// `Features/Home/View/...` can construct it. **It must never be
/// referenced from a release code path** — the production composition
/// root wires `BFFHomeRepository`. A grep for `StubHomeRepository(` in
/// the App folder should only ever match `#Preview` blocks.
///
/// The fixture is the "bankuser.one" sample payload: one customer with
/// four accounts (Checking, Savings, Credit, Loan) and three recent
/// transactions, exercising every `AccountType` case + a null
/// `merchant_name`.
public final class StubHomeRepository: HomeRepositoryProtocol {

    /// Optional override so tests can drive failure paths without
    /// reaching for a separate test-only mock.
    public enum Behaviour {
        case success(HomeDashboard)
        case failure(APIError)
    }

    private let behaviour: Behaviour

    public init(behaviour: Behaviour = .success(StubHomeRepository.bankuserOne)) {
        self.behaviour = behaviour
    }

    public func fetchHome() async throws -> HomeDashboard {
        switch behaviour {
        case .success(let dashboard):
            return dashboard
        case .failure(let error):
            throw error
        }
    }

    /// The canonical "bankuser.one" sample — kept in code (vs a bundled
    /// JSON resource) so previews work without bundling test fixtures
    /// into the app target.
    public static let bankuserOne: HomeDashboard = HomeDashboard(
        customer: Customer(
            id: "cust_bankuser_one",
            firstName: "Bank",
            lastName: "User",
            email: "bankuser.one@example.com",
            phoneNumber: "+1-555-0100"
        ),
        accounts: [
            Account(
                id: "acct_chk_001",
                name: "Everyday Checking",
                maskedNumber: "••1234",
                balance: Decimal(string: "4287.53")!,
                availableBalance: Decimal(string: "4187.53")!,
                type: .checking,
                currencyCode: "USD"
            ),
            Account(
                id: "acct_sav_001",
                name: "High-Yield Savings",
                maskedNumber: "••5678",
                balance: Decimal(string: "21500.00")!,
                availableBalance: Decimal(string: "21500.00")!,
                type: .savings,
                currencyCode: "USD"
            ),
            Account(
                id: "acct_crd_001",
                name: "Acme Platinum Card",
                maskedNumber: "••9012",
                balance: Decimal(string: "-842.19")!,
                availableBalance: Decimal(string: "9157.81")!,
                type: .credit,
                currencyCode: "USD"
            ),
            Account(
                id: "acct_lon_001",
                name: "Auto Loan",
                maskedNumber: "••3456",
                balance: Decimal(string: "-12450.00")!,
                availableBalance: Decimal(string: "0.00")!,
                type: .loan,
                currencyCode: "USD"
            )
        ],
        recentTransactions: [
            Transaction(
                id: "txn_001",
                accountId: "acct_chk_001",
                description: "BLUE BOTTLE COFFEE",
                amount: Decimal(string: "-6.25")!,
                postedDate: ISO8601DateFormatter().date(from: "2025-03-14T15:42:00Z")!,
                category: "DINING",
                merchantName: "Blue Bottle Coffee"
            ),
            Transaction(
                id: "txn_002",
                accountId: "acct_chk_001",
                description: "PAYROLL DEPOSIT",
                amount: Decimal(string: "3250.00")!,
                postedDate: ISO8601DateFormatter().date(from: "2025-03-13T13:00:00Z")!,
                category: "INCOME",
                merchantName: nil
            ),
            Transaction(
                id: "txn_003",
                accountId: "acct_crd_001",
                description: "AMAZON.COM",
                amount: Decimal(string: "-42.99")!,
                postedDate: ISO8601DateFormatter().date(from: "2025-03-12T09:11:00Z")!,
                category: "SHOPPING",
                merchantName: "Amazon"
            )
        ]
    )
}
