# iOS Banking App — Seed Architecture

> **Purpose:** This document is the authoritative seed specification for agentic build-out of the Acme Bank iOS app.  
> Every screen, layer, and convention described here must be followed unless the agent receives an explicit override instruction on a per-story basis.

---

## 1. Project Overview

| Item | Value |
|---|---|
| Platform | iOS 17+ |
| Language | Swift 5.10 |
| UI Framework | SwiftUI |
| Architecture | MVVM + Coordinator (SwiftUI `NavigationStack`) |
| Auth | Okta OIDC via `okta-mobile-swift` |
| Networking | `URLSession` + async/await |
| Dependency Injection | Constructor injection; no service locator |
| Internal Notifications | `NotificationCenter` (typed wrappers) |
| Minimum Xcode | 16.0 |
| Bundle ID | `com.acmebank.mobile` |
| App Name | `AcmeBank` |

---

## 1.5 Project file mechanism — XcodeGen

The Xcode project (`AcmeBank.xcodeproj`) is **generated** from a
declarative `project.yml` at the repo root using
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The agent never
hand-edits `project.pbxproj` and never tries to add files to the
project programmatically — instead it:

1. Drops new `.swift` files into the right directory under `AcmeBank/`
   (or `AcmeBankTests/`).
2. The directory globs in `project.yml`'s `sources` block
   (`sources: [AcmeBank]`) auto-discover the file when XcodeGen runs.
3. CI (or the user, locally) runs `xcodegen generate` to materialise
   `AcmeBank.xcodeproj` from the spec.

Why this matters: the previous "agent hand-crafts pbxproj" approach
left agent-written files orphaned — they sat on disk but were never
registered in the project, so `xcodebuild` silently compiled the
original Hello-World scaffold instead. With XcodeGen the project file
is a generated artifact and stays in sync with the source tree by
construction.

**Reference `project.yml`** (matches the folder layout in §2):

```yaml
name: AcmeBank
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    iOS: "17.0"
targets:
  AcmeBank:
    type: application
    platform: iOS
    sources: [AcmeBank]               # globs every .swift under AcmeBank/
    resources: [AcmeBank/Resources]   # Assets.xcassets, Info.plist, etc.
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.acmebank
        SWIFT_VERSION: "5.10"
  AcmeBankTests:
    type: bundle.unit-test
    platform: iOS
    sources: [AcmeBankTests]
    dependencies:
      - target: AcmeBank
  AcmeBankUITests:
    # XCUITest target for end-to-end UI flows. Empty until the first
    # critical-flow story (login) lands; ios-build.yml's `xcodebuild
    # test` invocation runs both targets, so an empty UI-tests target
    # is a no-op in CI cost terms.
    type: bundle.ui-testing
    platform: iOS
    sources: [AcmeBankUITests]
    dependencies:
      - target: AcmeBank
schemes:
  AcmeBank:
    build:
      targets: { AcmeBank: all }
    test:
      targets: [AcmeBankTests, AcmeBankUITests]
```

**One-time user setup** (after a fresh clone):
```
./setup.sh
```

The bootstrap-emitted `setup.sh` installs XcodeGen via Homebrew if
missing, runs `xcodegen generate`, and opens the resulting
`.xcodeproj` in Xcode. Manual fallback for environments that block
shell scripts:
```
brew install xcodegen
xcodegen generate
open AcmeBank.xcodeproj
```

`AcmeBank.xcodeproj` is git-ignored — only `project.yml` is the
source of truth. The bootstrap also commits a `.gitignore` covering
the standard iOS / XcodeGen / macOS noise (`.DS_Store`, `Pods/`,
`xcuserdata/`, `DerivedData/`, etc.) so the user never accidentally
commits a generated artifact. (For repos that already check the
.xcodeproj into git, the next generation step in PR B-bis will move
them to the generated-on-CI model.)

---

## 2. Folder Structure

```
AcmeBank/
├── App/
│   ├── AcmeBankApp.swift             # @main SwiftUI App entry (WindowGroup)
│   ├── RootView.swift               # switches Login vs TabBar on auth state
│   ├── AppCoordinator.swift          # root coordinator (ObservableObject)
│   └── Okta.plist                    # Okta tenant config (gitignored)
│
├── Core/
│   ├── Auth/
│   │   ├── AuthService.swift         # Okta token lifecycle
│   │   ├── KeychainStore.swift       # Keychain read/write helpers
│   │   └── UserSession.swift         # value type passed after login
│   ├── Networking/
│   │   ├── APIClient.swift           # URLSession wrapper
│   │   ├── APIRouter.swift           # endpoint enum
│   │   ├── APIError.swift            # typed error enum
│   │   └── RequestInterceptor.swift  # injects Bearer token
│   ├── Notifications/
│   │   ├── AppNotification.swift     # typed notification names
│   │   └── NotificationPublisher.swift
│   └── Extensions/
│       ├── Decimal+Currency.swift
│       ├── Date+Greeting.swift
│       └── String+Initials.swift
│
├── Domain/
│   ├── Models/
│   │   ├── Account.swift
│   │   ├── Transaction.swift
│   │   ├── Customer.swift
│   │   └── TransferRequest.swift
│   └── Repositories/              # protocol-only; no implementation here
│       ├── AccountRepository.swift
│       ├── TransactionRepository.swift
│       └── CustomerRepository.swift
│
├── Data/
│   ├── Remote/
│   │   ├── AccountAPIRepository.swift
│   │   ├── TransactionAPIRepository.swift
│   │   └── CustomerAPIRepository.swift
│   └── Mock/
│       ├── MockAccountRepository.swift
│       ├── MockTransactionRepository.swift
│       └── MockCustomerRepository.swift
│
├── Features/
│   ├── Login/
│   │   ├── LoginCoordinator.swift
│   │   ├── LoginView.swift
│   │   └── LoginViewModel.swift
│   ├── Home/
│   │   ├── HomeCoordinator.swift
│   │   ├── HomeView.swift
│   │   ├── HomeViewModel.swift
│   │   └── Views/
│   │       ├── SignedInCardView.swift
│   │       ├── QuickActionsView.swift
│   │       └── AccountRowView.swift
│   ├── Accounts/
│   │   └── (future)
│   ├── Transfer/
│   │   └── (future)
│   └── Cards/
│       └── (future)
│
├── DesignSystem/
│   ├── Colors.swift                  # named Color constants
│   ├── Typography.swift              # Font scale helpers
│   └── Assets.xcassets
│
├── Resources/
│   ├── Info.plist
│   └── Localizable.strings
│
└── AcmeBankTests/
    ├── Core/
    │   └── Auth/
    │       └── AuthServiceTests.swift
    ├── Features/
    │   ├── Login/
    │   │   └── LoginViewModelTests.swift
    │   └── Home/
    │       └── HomeViewModelTests.swift
    └── Mocks/
        └── (shared test doubles)
```

---

## 3. MVVM + Coordinator Pattern

### Rules

1. **View** is a SwiftUI `View` struct. It renders from its ViewModel's `@Published` state and forwards user intent to the ViewModel. It contains zero business logic.
2. **ViewModel** is a `final class: ObservableObject`. It holds state in `@Published` properties, calls repositories, and posts `AppNotification`s. It imports no SwiftUI view types — it stays a plain observable object so it's unit-testable without a rendered view.
3. **Coordinator** owns navigation. It is an `ObservableObject` that holds the `NavigationStack` path, creates child Views + ViewModels, injects dependencies, and drives push/present (path append, `.sheet`, `.fullScreenCover`). No View mutates navigation state directly — it asks the coordinator.
4. **Repository protocols** live in `Domain/`; concrete implementations live in `Data/`. ViewModels depend only on the protocol, never the concrete type.

### Binding Pattern

The View observes the ViewModel's `@Published` state via `@StateObject` — no manual callbacks:

```swift
// ViewModel
final class HomeViewModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published var errorMessage: String?

    func loadAccounts() async { /* sets accounts / errorMessage */ }
}

// View
struct HomeView: View {
    @StateObject var viewModel: HomeViewModel

    var body: some View {
        List(viewModel.accounts) { AccountRowView(account: $0) }
            .task { await viewModel.loadAccounts() }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
    }
}
```

For finer-grained streams, Combine `@Published` + `sink` inside the ViewModel is acceptable — but keep all view-facing state on `@Published` properties; never push imperative callback closures across the View/ViewModel boundary.

---

## 4. Authentication — Okta OIDC

### SDK

```
// Swift Package Manager
https://github.com/okta/okta-mobile-swift  tag: 2.x
```

Products to link: `OktaOidc`, `WebAuthenticationUI`

### Okta.plist (gitignored — provide `.plist.example`)

```xml
<dict>
  <key>issuer</key>      <string>https://integrator-2745601.okta.com/oauth2/default</string>
  <key>clientId</key>   <string>REPLACE_ME</string>
  <key>redirectUri</key><string>com.acmebank.mobile:/callback</string>
  <key>scopes</key>     <string>openid profile email offline_access</string>
</dict>
```

### AuthService

```swift
protocol AuthServiceProtocol {
    func signIn() async throws -> UserSession   // presents Okta web auth via ASWebAuthenticationSession from the SwiftUI layer
    func signOut() async throws
    func refreshTokenIfNeeded() async throws -> String  // returns valid access token
    var isSignedIn: Bool { get }
}
```

`signIn` must:
1. Invoke the Okta browser-based OIDC flow
2. On success, decode the ID token claims: `sub`, `name`, `email`, `auth_time`
3. Persist access token + refresh token to Keychain via `KeychainStore`
4. Return a `UserSession` value type

### UserSession

```swift
struct UserSession: Codable {
    let userId: String        // `sub` claim
    let displayName: String   // `name` claim
    let email: String         // `email` claim
    let accessToken: String
    let authTimestamp: Date   // `auth_time` claim
    let deviceName: String    // UIDevice.current.name
}
```

Pass `UserSession` forward through coordinators. Never store it in `UserDefaults`. Do not store it as a global singleton — inject it.

### Token Refresh

`RequestInterceptor` calls `AuthService.refreshTokenIfNeeded()` before every request. If the refresh fails (token revoked / expired), post `AppNotification.sessionExpired` — the root coordinator listens and redirects to login.

---

## 5. Networking Layer

### APIClient

```swift
final class APIClient {
    init(baseURL: URL, interceptor: RequestInterceptorProtocol)

    func request<T: Decodable>(_ endpoint: APIRouter) async throws -> T
}
```

- Decodes via `JSONDecoder` with `.convertFromSnakeCase` key strategy and `.iso8601` date strategy
- On HTTP 401 → posts `AppNotification.sessionExpired`, throws `APIError.unauthorized`
- On HTTP 4xx → throws `APIError.clientError(statusCode:message:)`
- On HTTP 5xx → throws `APIError.serverError(statusCode:)`
- On `URLError` → throws `APIError.networkUnavailable`

### APIRouter

All endpoints are expressed as an enum with associated values:

```swift
enum APIRouter {
    // Customer
    case getCustomerProfile

    // Accounts
    case getAccounts
    case getAccount(id: String)

    // Transactions
    case getTransactions(accountId: String, limit: Int, offset: Int)

    // Transfers
    case initiateTransfer(TransferRequest)

    // Bills
    case getBillPayees
    case payBill(BillPaymentRequest)
}
```

Each case provides: `path: String`, `method: HTTPMethod`, `body: Encodable?`, `queryItems: [URLQueryItem]?`.

### Base URL

Read from `Info.plist` key `API_BASE_URL`. Do not hardcode. CI injects this via xcconfig.

---

## 6. Domain Models

### Account

```swift
struct Account: Identifiable, Codable {
    let id: String
    let name: String
    let maskedNumber: String      // e.g. "4821"
    let balance: Decimal
    let availableBalance: Decimal
    let type: AccountType
    let currencyCode: String      // e.g. "CAD"
}

enum AccountType: String, Codable {
    case chequing, savings, credit, investment
}
```

### Transaction

```swift
struct Transaction: Identifiable, Codable {
    let id: String
    let accountId: String
    let description: String
    let amount: Decimal           // negative = debit
    let postedDate: Date
    let category: String?
    let merchantName: String?
}
```

### Customer

```swift
struct Customer: Codable {
    let id: String
    let firstName: String
    let lastName: String
    let email: String
    let phoneNumber: String?
    let address: Address?
}
```

### TransferRequest

```swift
struct TransferRequest: Encodable {
    let fromAccountId: String
    let toAccountId: String
    let amount: Decimal
    let memo: String?
    let scheduledDate: Date?      // nil = immediate
}
```

---

## 7. Repository Protocols

```swift
protocol AccountRepositoryProtocol {
    func fetchAccounts() async throws -> [Account]
    func fetchAccount(id: String) async throws -> Account
}

protocol TransactionRepositoryProtocol {
    func fetchTransactions(accountId: String, limit: Int, offset: Int) async throws -> [Transaction]
}

protocol CustomerRepositoryProtocol {
    func fetchProfile() async throws -> Customer
}

protocol TransferRepositoryProtocol {
    func initiateTransfer(_ request: TransferRequest) async throws -> TransferConfirmation
}
```

All ViewModels depend on these protocols — never on the concrete `APIRepository` or `MockRepository` types.

---

## 8. Mock Data Layer

Mock repositories return hardcoded fixtures. They exist so screens can be built and tested without a live API.

```swift
final class MockAccountRepository: AccountRepositoryProtocol {
    func fetchAccounts() async throws -> [Account] {
        return [
            Account(id: "acct-1", name: "Unlimited Chequing", maskedNumber: "4821",
                    balance: 4287.52, availableBalance: 4287.52, type: .chequing, currencyCode: "CAD"),
            Account(id: "acct-2", name: "High-Interest Savings", maskedNumber: "9203",
                    balance: 18940.00, availableBalance: 18940.00, type: .savings, currencyCode: "CAD"),
            Account(id: "acct-3", name: "Visa Platinum", maskedNumber: "1188",
                    balance: -612.34, availableBalance: 9387.66, type: .credit, currencyCode: "CAD"),
        ]
    }
}
```

Convention: every story that builds a screen must use the Mock repository first. Swapping to the real API repository is a separate story.

> **Note — Home screen is now data-driven.** Per the updated Home Dashboard story, the Home screen no longer renders static mock data: on appear after login it calls the BFF `GET /v1/home` (Authorization: Bearer `<Okta token>`), decodes the iOS snake_case `HomeDashboard` payload (`.convertFromSnakeCase` + `.iso8601`), and renders the logged-in user's CIF-resolved customer, accounts, and recent transactions live. Its `MockAccountRepository` has been replaced by a `HomeRepository` (behind `HomeRepositoryProtocol`); the mock fixture survives only for tests/previews.

---

## 9. Internal Notifications

All app-wide events flow through `NotificationCenter` using typed names. No magic strings.

### AppNotification

```swift
enum AppNotification {
    // Auth lifecycle
    static let sessionExpired   = Notification.Name("com.acmebank.sessionExpired")
    static let userSignedOut    = Notification.Name("com.acmebank.userSignedOut")

    // Data events
    static let accountsRefreshed   = Notification.Name("com.acmebank.accountsRefreshed")
    static let transferCompleted   = Notification.Name("com.acmebank.transferCompleted")
    static let billPaid            = Notification.Name("com.acmebank.billPaid")

    // UI alerts
    static let showGlobalError     = Notification.Name("com.acmebank.showGlobalError")
    static let showGlobalSuccess   = Notification.Name("com.acmebank.showGlobalSuccess")
    static let showGlobalBanner    = Notification.Name("com.acmebank.showGlobalBanner")
}
```

### NotificationPublisher

```swift
final class NotificationPublisher {
    static func post(_ name: Notification.Name, userInfo: [AnyHashable: Any]? = nil) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
    }
}
```

### UserInfo Keys

Define typed keys as an enum to avoid stringly-typed access:

```swift
enum NotificationKey {
    static let errorMessage   = "errorMessage"
    static let successMessage = "successMessage"
    static let bannerPayload  = "bannerPayload"
    static let accounts       = "accounts"
}
```

### Subscription Pattern

The root coordinator subscribes (or a root View via `.onReceive(NotificationCenter.default.publisher(for:))`); never subscribe inside a ViewModel.

```swift
// In AppCoordinator (ObservableObject) — Combine subscription
NotificationCenter.default.publisher(for: AppNotification.sessionExpired)
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in self?.handleSessionExpired() }
    .store(in: &cancellables)
```

### Alert / Banner Notifications

Post `showGlobalError` with `userInfo[NotificationKey.errorMessage]` to display a non-blocking error toast from any layer. The `AppCoordinator` owns the root banner view and renders it over all content.

---

## 10. Design System

### Colors (DesignSystem/Colors.swift)

**The app is STRICTLY MONOCHROME — navy + white + greys ONLY.** There are NO semantic
colours: amounts, badges, status icons, and account-type tiles are NEVER red or green
(a negative amount renders in the SAME near-black as a positive one). The palette below
is the COMPLETE set — do not add accent colours.

```swift
extension Color {
    static let acmeNavy       = Color(hex: "#1B2A4A")   // logo, SIGNED-IN card, account-type tiles, avatars, primary button
    static let acmeBackground = Color(hex: "#F2F3F5")   // screen background
    static let acmeSurface    = Color.white             // cards / fields
    static let acmeText       = Color(hex: "#1A1A1A")   // ALL amounts + primary text (positive AND negative)
    static let acmeSubtext    = Color(hex: "#6B7280")   // secondary / caption text
    // NO acmeGreen / acmeBadgeRed — semantic colour is deliberately absent (see above).
}
```

### Typography (DesignSystem/Typography.swift)

```swift
extension Font {
    static let acmeTitle       = Font.system(size: 28, weight: .bold)
    static let acmeHeadline    = Font.system(size: 17, weight: .semibold)
    static let acmeBody        = Font.system(size: 15, weight: .regular)
    static let acmeCaption     = Font.system(size: 13, weight: .regular)
    static let acmeMonoBalance = Font.system(size: 17, weight: .semibold).monospacedDigit()
}
```

All fonts must scale with Dynamic Type — prefer SwiftUI semantic text styles, or declare the fixed sizes above with `relativeTo:` (e.g. `Font.system(size: 28, weight: .bold)` paired with a relative text style) so they respond to the user's Dynamic Type setting.

---

## 11. Coordinator Pattern

```swift
@MainActor
protocol Coordinator: ObservableObject {
    /// Drives the screen's `NavigationStack`; push by appending a typed route.
    var path: NavigationPath { get set }
}
```

```
AppCoordinator (observed by RootView)
  └── LoginCoordinator   (shown full-screen when no session)
  └── TabBarCoordinator  (root TabView after login)
        ├── HomeCoordinator
        ├── TransferCoordinator
        ├── CardsCoordinator
        └── MoreCoordinator
```

`AppCoordinator` is an `ObservableObject` that `RootView` observes:
1. Check `AuthService.isSignedIn`
2. If false → `RootView` renders the Login flow (`LoginView` driven by `LoginCoordinator`)
3. If true → restore `UserSession` from Keychain, render `TabBarCoordinator`'s `TabView`
4. Observes `AppNotification.sessionExpired` → flips published state back to the Login flow

Each coordinator owns a `NavigationStack(path: $coordinator.path)`; child screens are pushed by appending a typed route to `path` and resolved with `.navigationDestination(for:)`. Modal / full-screen presentation uses `.sheet` / `.fullScreenCover` bound to coordinator state — purely declarative, no imperative `push`/`present` calls.

---

## 12. Error Handling Convention

- ViewModels catch errors from repositories and map them to user-facing strings.
- ViewModels call `NotificationPublisher.post(.showGlobalError, userInfo: [NotificationKey.errorMessage: message])` for errors that should surface globally (e.g., session expiry, network loss).
- For screen-local errors (e.g., a form validation failure), the ViewModel sets an `@Published errorMessage` (or a typed error enum); the View renders it via `.alert` or an inline error view.
- Never present alerts from a ViewModel. The ViewModel only publishes error state — the View decides how to render it (`.alert`, inline banner). All UI decisions belong in the View.

---

## 13. Testing Conventions

Two test layers — pick the right one for the change:

### 13.1 XCTest (unit) — the default

Used for: ViewModels, repositories, value-type extensions, format helpers.

- Every ViewModel has a corresponding `*Tests.swift` in `AcmeBankTests/Features/`.
- Inject mock repositories via constructor. No method swizzling or global state.
- Use `XCTestExpectation` + `async/await` for async ViewModel calls.
- Do not test SwiftUI view layout; test ViewModel `@Published` state transitions and outputs.
- Target ≥80% line coverage on `Core/` and `Features/` targets.

```swift
// Example
func test_fetchAccounts_populatesAccounts() async {
    let repo = MockAccountRepository()
    let vm = HomeViewModel(accountRepository: repo, session: .stub)

    await vm.loadAccounts()

    XCTAssertEqual(vm.accounts.count, 3)   // assert published state, not a callback
}
```

### 13.2 XCUITest (UI) — for critical flows only

Used for: end-to-end happy paths the user can't sign off on without
seeing a real screen — login, transfer confirmation, sign-out.

- Live in a separate target `AcmeBankUITests/` (XCUITest framework,
  declared in `project.yml` as `type: bundle.ui-testing`).
- Drive the app via `XCUIApplication`. Use accessibility identifiers
  (`accessibilityIdentifier = "loginButton"`) so locators are stable
  across copy / layout changes — never rely on visible text labels.
- One file per critical flow: `LoginUITests.swift`, `TransferUITests.swift`.
- Skip UI tests for individual ViewModel behaviour — that's what
  XCTest is for. UI tests are slow (10–60s each) and brittle; reserve
  them for the flows that genuinely need a rendered simulator.
- Mock the network at the boundary: launch with
  `XCUIApplication().launchArguments += ["-UITestMode", "YES"]` and
  wire the app to substitute `MockAccountRepository` (etc.) when
  that flag is set. Real Okta/network in a UI test is a CI flake source.

```swift
// Example
final class LoginUITests: XCTestCase {
    func test_login_with_valid_credentials_navigates_to_home() {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "YES"]
        app.launch()

        app.textFields["usernameField"].tap()
        app.textFields["usernameField"].typeText("user@example.com")
        app.secureTextFields["passwordField"].tap()
        app.secureTextFields["passwordField"].typeText("Password1!")
        app.buttons["signInButton"].tap()

        // Home tab bar appears within 5s on a successful auth flow.
        XCTAssertTrue(
            app.tabBars.element.waitForExistence(timeout: 5),
            "Home tab bar should appear after successful login"
        )
    }
}
```

### 13.3 Picking the right layer

| If the change is… | Write… |
|---|---|
| New / changed ViewModel logic, repository call, format helper | XCTest (always) |
| New screen on a critical user flow (login, transfer, sign-out) | XCTest for the ViewModel **and** XCUITest for the flow |
| UI polish (colour, spacing, copy) | XCTest for any ViewModel state change; no UI test needed |
| Pure refactor with no behaviour change | Existing tests should pass; don't add new ones |

---

## 14. CI Conventions

- `xcodebuild test -scheme AcmeBank -destination 'platform=iOS Simulator,name=iPhone 16'`
- Fail on any warning: `OTHER_SWIFT_FLAGS = -warnings-as-errors` in debug xcconfig
- Run `swiftlint` on every PR — rules file at `.swiftlint.yml` at repo root
- No secret values in source; all Okta / API config via xcconfig injected by CI

---

## 15. Story Implementation Checklist

Every agent story must complete **all** of the following before marking done:

- [ ] Feature compiles with zero warnings
- [ ] ViewModel has unit tests (≥80% coverage) — XCTest target `AcmeBankTests`
- [ ] If the story is a critical user flow (login / transfer / sign-out) it also has an XCUITest in `AcmeBankUITests/`
- [ ] Mock repository used (real API wired in a follow-up story)
- [ ] All touch targets ≥ 44×44 pt
- [ ] Dynamic Type tested at `accessibilityExtraExtraLarge`
- [ ] `NotificationPublisher` used for any cross-screen event (no delegate callbacks across feature boundaries)
- [ ] No SwiftUI view types in ViewModel files (ViewModels stay framework-free `ObservableObject`s)
- [ ] No business logic in View files
- [ ] SwiftLint passes with zero violations
- [ ] Coordinator handles all navigation; Views don't mutate navigation state directly